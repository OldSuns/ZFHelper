import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:zf_core/zf_core.dart';

import '../../../../data/repositories/schedule_repository.dart';
import '../../../../data/storage/schedule_store.dart';

typedef DateRefreshTimerFactory = Timer Function(Duration, VoidCallback);

enum ScheduleSection { timetable, agenda }

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

  ScheduleRepositoryState get data => _repository.state;
  ScheduleSnapshot? get schedule => data.effective;
  ScheduleSnapshot? get imported => data.imported;
  ScheduleSettings get settings => data.settings;
  AcademicTerm? get selectedTerm => data.selectedTerm;
  StoredScheduleAccount? get account => data.account;
  ScheduleTarget? get editTarget => data.target;
  ScheduleEventTarget? get eventTarget => data.eventTarget;
  List<ScheduleEvent> get events => account?.events ?? const [];
  ScheduleSection get section => _section;
  DateTime get agendaDate => _agendaDate;
  DateTime get today => _today;
  CalendarWeek get week => schedule?.calendar.weekDates(_selectedWeek) ?? _week;
  bool get hasSchedule => schedule != null;
  int get selectedWeek => _selectedWeek;
  bool get agenda => settings.preferAgenda;
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
    notifyListeners();
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
                    timesSignature(imported.periodTimes))) {
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
  }) => _repository.updateSettings(
    target: target,
    update: (value, imported) {
      var saved = entry;
      final previousLocal = value.localEntries
          .where((item) => item.id == entry.id)
          .firstOrNull;
      final originalId =
          previousLocal?.metadata['replacesImportedId'] ??
          (replacing?.origin == ScheduleEntryOrigin.imported
              ? replacing!.id
              : entry.metadata['replacesImportedId']);
      var replacementId = originalId;
      if (originalId != null) {
        var original = imported.entries
            .where((item) => item.id == originalId)
            .firstOrNull;
        if (original == null &&
            replacing?.origin == ScheduleEntryOrigin.imported) {
          final matches = imported.entries
              .where(replacing!.hasSameArrangement)
              .toList();
          if (matches.length == 1) original = matches.single;
        }
        replacementId = original?.id ?? originalId;
        saved = entry.withMetadata({
          ...entry.metadata,
          'replacesImportedId': replacementId,
          'schoolArrangementChanged': (original == null).toString(),
        });
      }
      return value.copyWith(
        localEntries: [
          ...value.localEntries.where((existing) => existing.id != saved.id),
          saved,
        ],
        hiddenEntryIds: {
          ...value.hiddenEntryIds.where((id) => id != originalId),
          ?replacementId,
        },
      );
    },
  );

  Future<bool> removeEntry(
    ScheduleEntry entry, {
    required ScheduleTarget target,
  }) => _repository.updateSettings(
    target: target,
    update: (value, imported) {
      if (entry.origin == ScheduleEntryOrigin.imported) {
        final current = imported.entries
            .where(
              (item) => item.id == entry.id || item.hasSameArrangement(entry),
            )
            .toList();
        if (current.length != 1) {
          throw const ScheduleStorageException(
            operation: '隐藏课表安排',
            message: '学校安排已更新，请重新打开课程详情',
          );
        }
        return value.copyWith(
          hiddenEntryIds: {...value.hiddenEntryIds, current.single.id},
        );
      }
      final current = value.localEntries
          .where((item) => item.id == entry.id)
          .firstOrNull;
      final original = current?.metadata['replacesImportedId'];
      return value.copyWith(
        localEntries: value.localEntries
            .where((item) => item.id != entry.id)
            .toList(),
        hiddenEntryIds: value.hiddenEntryIds.where((id) => id != original),
      );
    },
  );

  Future<bool> restoreHiddenEntries({required ScheduleTarget target}) =>
      _repository.updateSettings(
        target: target,
        update: (value, _) => value.copyWith(
          hiddenEntryIds: const [],
          localEntries: value.localEntries
              .where(
                (entry) => !entry.metadata.containsKey('replacesImportedId'),
              )
              .toList(),
        ),
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
    _scheduleDateRefresh(now);
    if (changedDate && wasCurrent) {
      if (hasSchedule) {
        _selectedWeek = currentPosition.week ?? _selectedWeek;
        _rememberWeek();
      } else {
        _week = CalendarWeek.containing(now);
      }
    }
    if (changedDate || ((hasSchedule || events.isNotEmpty) && changedMinute)) {
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
    _dateRefreshTimer = _createTimer(next.difference(now), refreshToday);
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
