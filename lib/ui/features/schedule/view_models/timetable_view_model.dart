import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:zf_core/zf_core.dart';

import '../../../../data/repositories/schedule_repository.dart';
import '../../../../data/storage/schedule_store.dart';

typedef DateRefreshTimerFactory = Timer Function(Duration, VoidCallback);

bool _belongsToEntry(ScheduleOccurrenceOverride change, ScheduleEntry entry) =>
    change.source.id == entry.id ||
    change.source.id == entry.metadata['replacesImportedId'];

bool _isSchoolChange(ScheduleOccurrenceOverride change) =>
    change.source.origin == ScheduleEntryOrigin.imported ||
    change.source.metadata.containsKey('replacesImportedId');

String _schoolChangesSignature(ScheduleSettings settings) =>
    ScheduleSettingsCodec.encode(
      ScheduleSettings(
        hiddenEntryIds: settings.hiddenEntryIds,
        localEntries: settings.localEntries
            .where((entry) => entry.metadata.containsKey('replacesImportedId'))
            .toList(),
        occurrenceOverrides: settings.occurrenceOverrides
            .where(_isSchoolChange)
            .toList(),
      ),
    );

void _checkRootEdit(
  ScheduleSettings settings,
  ScheduleSnapshot baseline,
  ScheduleEntry expected,
  List<ScheduleOccurrenceOverride> expectedOverrides,
) {
  final current = baseline.entries
      .where((entry) => entry.id == expected.id)
      .firstOrNull;
  final changes = settings.occurrenceOverrides
      .where((change) => _belongsToEntry(change, expected))
      .toList();
  if (expected.sourceEntryId != null ||
      current == null ||
      !current.hasSameValue(expected) ||
      changes.length != expectedOverrides.length ||
      changes.any((change) => !expectedOverrides.any(change.hasSameValue))) {
    throw const ScheduleStorageException(
      operation: '修改课程安排',
      message: '课程或调停补课记录已更新，请重新打开后修改',
    );
  }
}

enum ScheduleSection { timetable, agenda }

final class ScheduleAdjustmentContext {
  ScheduleAdjustmentContext({
    required this.target,
    required this.imported,
    required this.settings,
  }) : baseline = settings.baseSnapshot(imported),
       effective = settings.applyTo(imported);

  final ScheduleTarget target;
  final ScheduleSnapshot imported;
  final ScheduleSettings settings;
  final ScheduleSnapshot baseline;
  final ScheduleSnapshot effective;
  List<ScheduleOccurrenceOverride> get overrides =>
      settings.occurrenceOverrides;

  ScheduleEntry? rootFor(ScheduleEntry entry) => baseline.entries
      .where((item) => item.id == (entry.sourceEntryId ?? entry.id))
      .firstOrNull;

  List<ScheduleOccurrenceOverride> changesFor(ScheduleEntry root) =>
      overrides.where((value) => _belongsToEntry(value, root)).toList();
}

final class TimetableViewModel extends ChangeNotifier {
  TimetableViewModel({
    required ScheduleRepository repository,
    required DateTime Function() clock,
    this._createTimer = Timer.new,
  }) : _repository = repository,
       _clock = clock,
       _today = clock() {
    _week = CalendarWeek.containing(_today);
    _agendaDate = DateTime(_today.year, _today.month, _today.day);
    _subscription = repository.changes.listen(_dataChanged);
    _scheduleDateRefresh(_today);
    _dataChanged(repository.state);
  }

  final ScheduleRepository _repository;
  final DateTime Function() _clock;
  final DateRefreshTimerFactory _createTimer;
  late final StreamSubscription<ScheduleRepositoryState> _subscription;
  final _browsedWeeks = <(AccountScope, String), int>{};
  final _browsedDates = <AccountScope, DateTime>{};
  final _savingEvents = <(AccountScope, String)>{};
  Timer? _dateRefreshTimer;
  DateTime _today;
  late CalendarWeek _week;
  (AccountScope, String)? _termKey;
  int _selectedWeek = 1;
  bool _hadSchedule = false;
  DateTime? _calendarMonday;
  ScheduleSection _section = ScheduleSection.timetable;
  late DateTime _agendaDate;
  AccountScope? _agendaScope;
  bool _countdownVisible = true;

  ScheduleRepositoryState get data => _repository.state;
  ScheduleSnapshot? get schedule => data.effective;
  ScheduleSnapshot? get imported => data.imported;
  ScheduleSettings get settings => data.settings;
  AcademicTerm? get selectedTerm => data.selectedTerm;
  StoredScheduleAccount? get account => data.account;
  ScheduleTarget? get editTarget => data.target;
  ScheduleAdjustmentContext? get adjustmentContext {
    final state = data;
    final target = state.target;
    final snapshot = state.imported;
    if (target == null || snapshot == null) return null;
    return ScheduleAdjustmentContext(
      target: target,
      imported: snapshot,
      settings: state.settings,
    );
  }

  ScheduleEventTarget? get eventTarget => data.eventTarget;
  List<ScheduleEvent> get events => account?.events ?? const [];
  ScheduleSection get section => _section;
  DateTime get agendaDate => _agendaDate;
  DateTime get today => _today;
  ScheduleCountdown get todayCountdown =>
      ScheduleCountdown.fromDay(dayOn(_today), _today);
  ScheduleCountdown? get headerCountdown {
    if (_section != ScheduleSection.timetable || !isCurrentWeek) return null;
    final countdown = todayCountdown;
    return countdown.phase == ScheduleCountdownPhase.ongoing ? countdown : null;
  }

  bool get _usesCountdownClock =>
      _countdownVisible &&
      (headerCountdown != null ||
          (_section == ScheduleSection.agenda &&
              sameScheduleDate(_agendaDate, _today)));
  CalendarWeek get week => schedule?.calendar.weekDates(_selectedWeek) ?? _week;
  bool get hasSchedule => schedule != null;
  int get selectedWeek => _selectedWeek;
  bool get agenda => settings.preferAgenda;
  bool get hasSchoolAdjustments =>
      settings.hiddenEntryIds.isNotEmpty ||
      settings.localEntries.any(
        (entry) => entry.metadata.containsKey('replacesImportedId'),
      ) ||
      settings.occurrenceOverrides.any(_isSchoolChange);
  int get adjustmentsNeedingReview {
    final snapshot = imported;
    if (snapshot == null) return 0;
    final baseline = settings.baseSnapshot(snapshot);
    return settings.occurrenceOverrides
        .where((change) => change.needsReview(baseline.entries))
        .length;
  }

  bool get canPreviousWeek => !hasSchedule || _selectedWeek > 1;
  bool get canNextWeek =>
      !hasSchedule ||
      schedule!.navigationWeekLimit == null ||
      _selectedWeek < schedule!.navigationWeekLimit!;
  bool get canRefresh =>
      account != null && _repository.canRefresh(account!.account.scope);

  TeachingWeekPosition get currentPosition =>
      schedule?.calendar.positionOn(_today) ??
      const TeachingWeekPosition(status: TeachingWeekStatus.unknown);

  bool get isCurrentWeek => hasSchedule
      ? currentPosition.week == _selectedWeek
      : _week.contains(_today);

  int get weekCount {
    final snapshot = schedule;
    if (snapshot == null) return 0;
    return snapshot.navigationWeekLimit ??
        math.max(snapshot.observedMaxWeek, _selectedWeek + 1);
  }

  String get rangeLabel {
    if (hasSchedule && schedule!.calendar.firstWeekMonday == null) {
      return '设置校历后显示每周日期';
    }
    final value = week;
    final crossesYear = value.start.year != value.end.year;
    return '${_dateLabel(value.start, crossesYear)} — '
        '${_dateLabel(value.end, crossesYear)}';
  }

  String get yearLabel => week.start.year == week.end.year
      ? '${week.start.year}年'
      : '${week.start.year}–${week.end.year}年';

  Future<void> initialize() => _repository.initialize();
  Future<void> retryLocalLoad() => _repository.retryLocalLoad();
  Future<bool> refresh({bool useSchoolDefault = false}) =>
      _repository.refresh(useSchoolDefault: useSchoolDefault);
  Future<bool> refreshCatalog() => _repository.refreshCatalog();

  void previousWeek() {
    if (!canPreviousWeek) return;
    if (hasSchedule) {
      showTeachingWeek(_selectedWeek - 1);
    } else {
      _week = _week.shift(-1);
      notifyListeners();
    }
  }

  void nextWeek() {
    if (!canNextWeek) return;
    if (hasSchedule) {
      showTeachingWeek(_selectedWeek + 1);
    } else {
      _week = _week.shift(1);
      notifyListeners();
    }
  }

  void showTeachingWeek(int value) {
    if (value < 1 ||
        (schedule?.navigationWeekLimit != null &&
            value > schedule!.navigationWeekLimit!)) {
      throw ArgumentError('教学周不在所选学期范围内');
    }
    if (_selectedWeek == value) return;
    _selectedWeek = value;
    _rememberWeek();
    refreshToday();
    notifyListeners();
  }

  Future<void> returnToCurrentWeek() async {
    refreshToday();
    if (!hasSchedule) {
      _week = CalendarWeek.containing(_today);
      notifyListeners();
      return;
    }
    if (currentPosition.week case final current?) {
      showTeachingWeek(current);
      return;
    }
    final stored = account;
    if (stored == null) return;
    for (final snapshot in stored.schedules.values) {
      final effective =
          (stored.settings[snapshot.term.key] ?? ScheduleSettings()).applyTo(
            snapshot,
          );
      if (effective.calendar.totalWeeks == null) continue;
      final current = effective.calendar.positionOn(_today).week;
      if (current != null && await selectTerm(snapshot.term)) {
        showTeachingWeek(current);
        return;
      }
    }
  }

  Future<bool> selectTerm(AcademicTerm term) => _repository.selectTerm(term);
  Future<bool> selectAccount(AccountScope scope) =>
      _repository.selectAccount(scope);

  void showSection(ScheduleSection value) {
    if (_section == value) return;
    _section = value;
    refreshToday();
    notifyListeners();
  }

  void selectAgendaDate(DateTime value) {
    final date = DateTime(value.year, value.month, value.day);
    if (sameScheduleDate(date, _agendaDate)) return;
    _agendaDate = date;
    final scope = account?.account.scope;
    if (scope != null) _browsedDates[scope] = date;
    refreshToday();
    notifyListeners();
  }

  void setCountdownVisible(bool value) {
    if (_countdownVisible == value) return;
    _countdownVisible = value;
    refreshToday();
  }

  void shiftAgendaDate(int days) => selectAgendaDate(
    DateTime(_agendaDate.year, _agendaDate.month, _agendaDate.day + days),
  );

  void shiftAgendaMonth(int months) {
    final first = DateTime(_agendaDate.year, _agendaDate.month + months);
    final lastDay = DateTime(first.year, first.month + 1, 0).day;
    selectAgendaDate(
      DateTime(first.year, first.month, math.min(_agendaDate.day, lastDay)),
    );
  }

  void returnToToday() {
    refreshToday();
    selectAgendaDate(_today);
  }

  ScheduleDay dayOn(DateTime date) => ScheduleDay.fromSnapshot(schedule, date);

  List<ScheduleEvent> eventsOn(DateTime date) =>
      events.where((event) => sameScheduleDate(event.date, date)).toList()
        ..sort((left, right) {
          final time = (left.startMinutes ?? -1).compareTo(
            right.startMinutes ?? -1,
          );
          return time != 0 ? time : left.title.compareTo(right.title);
        });

  bool hasAgendaOn(DateTime date) =>
      events.any((event) => sameScheduleDate(event.date, date)) ||
      dayOn(date).lessons.isNotEmpty;

  bool isSavingEvent(String id) =>
      _savingEvents.contains((account?.account.scope, id));

  Future<bool> saveEvent(
    ScheduleEvent event, {
    required ScheduleEventTarget target,
    ScheduleEvent? replacing,
  }) => _repository.saveEvent(event, target: target, replacing: replacing);

  Future<bool> removeEvent(
    ScheduleEvent event, {
    required ScheduleEventTarget target,
  }) => _repository.removeEvent(event, target: target);

  Future<bool> setEventCompleted(ScheduleEvent event, bool completed) async {
    final target = eventTarget;
    if (target == null) return false;
    final key = (target.scope, event.id);
    if (!_savingEvents.add(key)) return false;
    notifyListeners();
    try {
      return await _repository.setEventCompleted(
        event,
        completed,
        target: target,
      );
    } finally {
      _savingEvents.remove(key);
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> saveSettings(
    ScheduleSettings value, {
    required ScheduleTarget target,
    required ScheduleSettings original,
    required ScheduleSnapshot originalImport,
  }) async {
    String settingsSignature(ScheduleSettings settings) {
      final plan = PeriodTimePlan(
        periods: settings.periodTimes,
        sections: settings.periodSections,
      );
      return ScheduleSettingsCodec.encode(
        settings.copyWith(
          periodTimes: plan.periods,
          periodSections: plan.sections,
          localEntries: const [],
          hiddenEntryIds: const [],
          occurrenceOverrides: const [],
          preferAgenda: false,
        ),
      );
    }

    String timesSignature(List<PeriodTime> times) =>
        ScheduleSettingsCodec.encode(
          ScheduleSettings(
            periodTimes: PeriodTimePlan(periods: times).periods,
            useCustomPeriodTimes: true,
          ),
        );
    final originalSignature = settingsSignature(original);
    final originalCampus = normalizePeriodCampus(original.periodCampus);
    final inheritsCalendar =
        original.calendarOverride == null && value.calendarOverride != null;
    final inheritsTimes =
        !original.useCustomPeriodTimes && value.useCustomPeriodTimes;
    TeachingCalendar? previous;
    final saved = await _repository.updateSettings(
      target: target,
      update: (current, imported) {
        if (value.useCustomPeriodTimes) {
          try {
            PeriodTimePlan(
              periods: value.periodTimes,
              sections: value.periodSections,
            ).validate();
          } on PeriodTimeException catch (error) {
            throw ScheduleStorageException(
              operation: '保存课节作息',
              message: error.message,
            );
          }
        }
        if (settingsSignature(current) != originalSignature ||
            (inheritsCalendar &&
                (
                      originalImport.calendar.firstWeekMonday,
                      originalImport.calendar.totalWeeks,
                    ) !=
                    (
                      imported.calendar.firstWeekMonday,
                      imported.calendar.totalWeeks,
                    )) ||
            (inheritsTimes &&
                timesSignature(originalImport.periodTimes) !=
                    timesSignature(imported.periodTimes)) ||
            normalizePeriodCampus(current.periodCampus) != originalCampus) {
          throw const ScheduleStorageException(
            operation: '保存校历与作息',
            message: '校历或作息已更新，本次未覆盖新设置，请重新打开后修改',
          );
        }
        previous = current.applyTo(imported).calendar;
        return current.copyWith(
          calendarOverride: value.calendarOverride,
          clearCalendarOverride: value.calendarOverride == null,
          periodTimes: value.periodTimes,
          periodSections: value.useCustomPeriodTimes
              ? value.periodSections
              : const [],
          useCustomPeriodTimes: value.useCustomPeriodTimes,
          periodCampus: value.periodCampus,
          clearPeriodCampus: value.periodCampus == null,
        );
      },
    );
    if (saved &&
        editTarget == target &&
        (previous?.firstWeekMonday != schedule?.calendar.firstWeekMonday ||
            previous?.totalWeeks != schedule?.calendar.totalWeeks)) {
      _selectedWeek = currentPosition.week ?? 1;
      _rememberWeek();
      notifyListeners();
    }
    return saved;
  }

  Future<bool> saveLocalEntry(
    ScheduleEntry entry, {
    required ScheduleTarget target,
    ScheduleEntry? replacing,
    List<ScheduleOccurrenceOverride> expectedOverrides = const [],
  }) => _repository.updateSettings(
    target: target,
    update: (value, imported) {
      final baseline = value.baseSnapshot(imported);
      if (replacing != null) {
        _checkRootEdit(value, baseline, replacing, expectedOverrides);
      } else if (baseline.entries.any((item) => item.id == entry.id)) {
        throw const ScheduleStorageException(
          operation: '保存课程',
          message: '这条课程已保存，请重新打开后编辑',
        );
      }
      final originalId = replacing?.origin == ScheduleEntryOrigin.imported
          ? replacing!.id
          : replacing?.metadata['replacesImportedId'];
      final saved = originalId == null
          ? entry
          : entry.withMetadata({
              ...entry.metadata,
              'replacesImportedId': originalId,
              'schoolArrangementChanged': (!imported.entries.any(
                (item) => item.id == originalId,
              )).toString(),
            });
      return value.copyWith(
        localEntries: [
          ...value.localEntries.where((existing) => existing.id != saved.id),
          saved,
        ],
        hiddenEntryIds: {...value.hiddenEntryIds, ?originalId},
        occurrenceOverrides: replacing == null
            ? value.occurrenceOverrides
            : value.occurrenceOverrides
                  .where((change) => !_belongsToEntry(change, replacing))
                  .toList(),
      );
    },
  );

  Future<bool> removeEntry(
    ScheduleEntry entry, {
    required ScheduleTarget target,
    List<ScheduleOccurrenceOverride> expectedOverrides = const [],
  }) => _repository.updateSettings(
    target: target,
    update: (value, imported) {
      _checkRootEdit(
        value,
        value.baseSnapshot(imported),
        entry,
        expectedOverrides,
      );
      final overrides = value.occurrenceOverrides
          .where((change) => !_belongsToEntry(change, entry))
          .toList();
      if (entry.origin == ScheduleEntryOrigin.imported) {
        return value.copyWith(
          hiddenEntryIds: {...value.hiddenEntryIds, entry.id},
          occurrenceOverrides: overrides,
        );
      }
      final original = entry.metadata['replacesImportedId'];
      return value.copyWith(
        localEntries: value.localEntries
            .where((item) => item.id != entry.id)
            .toList(),
        hiddenEntryIds: value.hiddenEntryIds.where((id) => id != original),
        occurrenceOverrides: overrides,
      );
    },
  );

  Future<bool> restoreHiddenEntries({
    required ScheduleTarget target,
    required ScheduleSettings expected,
  }) => _repository.updateSettings(
    target: target,
    update: (value, _) {
      if (_schoolChangesSignature(value) != _schoolChangesSignature(expected)) {
        throw const ScheduleStorageException(
          operation: '恢复学校安排',
          message: '学校课程的本地调整已更新，请重新核对后恢复',
        );
      }
      return value.copyWith(
        hiddenEntryIds: const [],
        localEntries: value.localEntries
            .where((entry) => !entry.metadata.containsKey('replacesImportedId'))
            .toList(),
        occurrenceOverrides: value.occurrenceOverrides
            .where((change) => !_isSchoolChange(change))
            .toList(),
      );
    },
  );

  Future<bool> applyOccurrenceChanges(
    List<ScheduleOccurrenceChange> changes, {
    required ScheduleTarget target,
  }) => _repository.updateSettings(
    target: target,
    update: (value, imported) {
      try {
        return value.copyWith(
          occurrenceOverrides: applyScheduleOccurrenceChanges(
            baseline: value.baseSnapshot(imported),
            overrides: value.occurrenceOverrides,
            changes: changes,
          ),
        );
      } on ScheduleOccurrenceException catch (error) {
        throw ScheduleStorageException(
          operation: '保存调停补课',
          message: error.message,
        );
      }
    },
  );

  Future<bool> restoreOccurrence(
    ScheduleOccurrenceOverride expected, {
    required ScheduleTarget target,
  }) => _repository.updateSettings(
    target: target,
    update: (value, imported) {
      try {
        return value.copyWith(
          occurrenceOverrides: restoreScheduleOccurrenceOverride(
            baseline: value.baseSnapshot(imported),
            overrides: value.occurrenceOverrides,
            expected: expected,
          ),
        );
      } on ScheduleOccurrenceException catch (error) {
        throw ScheduleStorageException(
          operation: '恢复课程安排',
          message: error.message,
        );
      }
    },
  );
  Future<bool> clearSavedSchedules(AccountScope scope) =>
      _repository.clearSchedules(scope);
  void dismissFailure() => _repository.dismissFailure();

  Future<bool> toggleAgenda() {
    final target = editTarget;
    if (target == null) return Future.value(false);
    return _repository.updateSettings(
      target: target,
      update: (value, _) => value.copyWith(preferAgenda: !value.preferAgenda),
    );
  }

  void refreshToday() {
    final now = _clock();
    final changedSecond = _today.second != now.second;
    final hadSecondCountdown =
        _usesCountdownClock && todayCountdown.showSeconds;
    final wasCurrent = isCurrentWeek;
    final changedDate = !_isSameDate(_today, now);
    final agendaWasToday = _isSameDate(_agendaDate, _today);
    final changedMinute =
        _today.hour != now.hour || _today.minute != now.minute;
    _today = now;
    if (changedDate && agendaWasToday) {
      _agendaDate = DateTime(now.year, now.month, now.day);
      final scope = _agendaScope;
      if (scope != null) _browsedDates[scope] = _agendaDate;
    }
    if (changedDate && wasCurrent) {
      if (hasSchedule) {
        _selectedWeek = currentPosition.week ?? _selectedWeek;
        _rememberWeek();
      } else {
        _week = CalendarWeek.containing(now);
      }
    }
    _scheduleDateRefresh(now);
    if (changedDate ||
        ((hasSchedule || events.isNotEmpty) && changedMinute) ||
        (changedSecond &&
            _usesCountdownClock &&
            (hadSecondCountdown || todayCountdown.showSeconds))) {
      notifyListeners();
    }
  }

  bool isToday(DateTime date) => _isSameDate(date, _today);

  void _dataChanged(ScheduleRepositoryState state) {
    final scope = state.account?.account.scope;
    if (scope != _agendaScope) {
      _agendaScope = scope;
      _agendaDate =
          _browsedDates[scope] ??
          DateTime(_today.year, _today.month, _today.day);
    }
    final term = state.selectedTerm;
    final nextKey = scope != null && term != null ? (scope, term.key) : null;
    if (nextKey != _termKey ||
        (!_hadSchedule && hasSchedule) ||
        (_calendarMonday == null &&
            schedule?.calendar.firstWeekMonday != null)) {
      _termKey = nextKey;
      _selectedWeek = _browsedWeeks[nextKey] ?? currentPosition.week ?? 1;
    }
    final total = schedule?.navigationWeekLimit;
    if (total != null && _selectedWeek > total) _selectedWeek = total;
    _hadSchedule = hasSchedule;
    _calendarMonday = schedule?.calendar.firstWeekMonday;
    refreshToday();
    notifyListeners();
  }

  void _rememberWeek() {
    final key = _termKey;
    if (key != null) _browsedWeeks[key] = _selectedWeek;
  }

  void _scheduleDateRefresh(DateTime now) {
    _dateRefreshTimer?.cancel();
    final next = hasSchedule || events.isNotEmpty
        ? (now.isUtc
              ? DateTime.utc(
                  now.year,
                  now.month,
                  now.day,
                  now.hour,
                  now.minute + 1,
                )
              : DateTime(
                  now.year,
                  now.month,
                  now.day,
                  now.hour,
                  now.minute + 1,
                ))
        : (now.isUtc
              ? DateTime.utc(now.year, now.month, now.day + 1)
              : DateTime(now.year, now.month, now.day + 1));
    var delay = next.difference(now);
    if (_usesCountdownClock) {
      final countdownDelay = todayCountdown.nextRefresh;
      if (countdownDelay != null && countdownDelay < delay) {
        delay = countdownDelay;
      }
    }
    _dateRefreshTimer = _createTimer(delay, refreshToday);
  }

  @override
  void dispose() {
    _disposed = true;
    _dateRefreshTimer?.cancel();
    unawaited(_subscription.cancel());
    super.dispose();
  }

  bool _disposed = false;

  static String _dateLabel(DateTime date, bool includeYear) =>
      '${includeYear ? '${date.year}年' : ''}${date.month}月${date.day}日';
  static bool _isSameDate(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}
