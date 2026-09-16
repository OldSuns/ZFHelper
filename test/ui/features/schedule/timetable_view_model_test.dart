import 'package:flutter_test/flutter_test.dart';
import 'package:zf_core/zf_core.dart';
import 'package:zfhelper/data/storage/schedule_store.dart';
import 'package:zfhelper/ui/features/schedule/view_models/timetable_view_model.dart';

import '../../../support/schedule_fakes.dart';

void main() {
  group('TimetableViewModel', () {
    late DateTime now;
    late TimetableViewModel viewModel;
    late TestScheduleStore store;

    setUp(() {
      now = DateTime(2026, 9, 12, 13);
      store = TestScheduleStore();
      final repository = testScheduleRepository(store: store);
      addTearDown(repository.dispose);
      viewModel = TimetableViewModel(repository: repository, clock: () => now);
    });

    tearDown(() => viewModel.dispose());

    test('saves section times and rejects a stale calendar editor', () async {
      store.library = ScheduleLibrary(
        accounts: [scheduleTestSaved()],
        selectedAccount: scheduleTestAccount.scope,
      );
      await viewModel.initialize();
      final original = viewModel.settings;
      final imported = viewModel.imported!;
      final target = viewModel.editTarget!;
      final plan = PeriodTimePlan(periods: imported.periodTimes)
          .withSections(
            sections: [
              PeriodTimeSection(
                session: PeriodSession.morning,
                firstPeriod: 1,
                lastPeriod: 2,
              ),
            ],
          )
          .edit(number: 1, startMinutes: 490);
      final edited = original.copyWith(
        periodTimes: plan.periods,
        periodSections: plan.sections,
        useCustomPeriodTimes: true,
      );
      Future<bool> save(ScheduleSettings value) => viewModel.saveSettings(
        value,
        target: target,
        original: original,
        originalImport: imported,
      );
      expect(await save(edited), isTrue);
      expect(
        store.library.accounts.single.settings.values.single.periodSections,
        plan.sections,
      );
      expect(
        viewModel.dayOn(DateTime(2026, 9, 14)).lessons.single.startMinutes,
        490,
      );
      expect(await save(original), isFalse);
      expect(viewModel.settings.periodTimes.first.startMinutes, 490);
      expect(viewModel.data.failure!.message, contains('已更新'));
    });

    test(
      'opens the current calendar week without assuming a teaching week',
      () {
        expect(viewModel.week.start, DateTime(2026, 9, 7));
        expect(viewModel.week.end, DateTime(2026, 9, 13));
        expect(viewModel.rangeLabel, '9月7日 — 9月13日');
        expect(viewModel.isCurrentWeek, isTrue);
      },
    );

    test('previous and next week notify observers with the new dates', () {
      final observedStarts = <DateTime>[];
      viewModel.addListener(() => observedStarts.add(viewModel.week.start));

      viewModel.previousWeek();
      viewModel.nextWeek();
      viewModel.nextWeek();

      expect(observedStarts, [
        DateTime(2026, 8, 31),
        DateTime(2026, 9, 7),
        DateTime(2026, 9, 14),
      ]);
      expect(viewModel.isCurrentWeek, isFalse);
    });

    test('return to current week reads the current clock', () {
      viewModel.previousWeek();
      now = DateTime(2026, 9, 21);

      viewModel.returnToCurrentWeek();

      expect(viewModel.week.start, DateTime(2026, 9, 21));
      expect(viewModel.today, now);
      expect(viewModel.isCurrentWeek, isTrue);
    });

    test('resuming on Monday follows a previously current week', () {
      now = DateTime(2026, 9, 14, 8);

      viewModel.refreshToday();

      expect(viewModel.week.start, DateTime(2026, 9, 14));
      expect(viewModel.isToday(DateTime(2026, 9, 14, 23)), isTrue);
      expect(viewModel.isToday(DateTime(2026, 9, 12)), isFalse);
    });

    test('resuming preserves a week the user was browsing', () {
      viewModel.previousWeek();
      now = DateTime(2026, 9, 14);

      viewModel.refreshToday();

      expect(viewModel.week.start, DateTime(2026, 8, 31));
      expect(viewModel.today, now);
      expect(viewModel.isCurrentWeek, isFalse);
    });

    test('refresh on the same calendar day does not rebuild observers', () {
      var notifications = 0;
      viewModel.addListener(() => notifications++);
      now = DateTime(2026, 9, 12, 23, 59);

      viewModel.refreshToday();

      expect(notifications, 0);
    });

    test('date range labels distinguish both years across New Year', () {
      now = DateTime(2027, 1, 1);
      viewModel.returnToCurrentWeek();

      expect(viewModel.rangeLabel, '2026年12月28日 — 2027年1月3日');
      expect(viewModel.yearLabel, '2026–2027年');
    });

    test('daily courses keep actual weeks, breaks and unknown clock data', () {
      final snapshot = scheduleTestSnapshot();
      final date = DateTime(2026, 9, 14);
      final day = ScheduleDay.fromSnapshot(snapshot, date);
      final lesson = day.lessons.single;
      expect(day.week, 2);
      expect(
        ScheduleDay.fromSnapshot(snapshot, DateTime(2026, 9, 13)).lessons,
        isEmpty,
      );
      expect(
        lesson.phaseAt(DateTime(2026, 9, 14, 8, 30)),
        ScheduleLessonPhase.ongoing,
      );
      expect(
        lesson.phaseAt(DateTime(2026, 9, 14, 8, 50)),
        ScheduleLessonPhase.breakTime,
      );
      final shortened = snapshot.copyWith(
        calendar: TeachingCalendar(
          firstWeekMonday: DateTime(2026, 9, 7),
          totalWeeks: 1,
          source: TeachingCalendarSource.user,
        ),
      );
      expect(ScheduleDay.fromSnapshot(shortened, date).lessons, hasLength(1));
      final unknown = snapshot.copyWith(
        calendar: const TeachingCalendar.unknown(),
      );
      expect(ScheduleDay.fromSnapshot(unknown, date).lessons, isEmpty);
      final partial = ScheduleDay.fromSnapshot(
        snapshot.copyWith(periodTimes: [snapshot.periodTimes.first]),
        date,
      ).lessons.single;
      expect(partial.startMinutes, isNull);
      expect(
        partial.phaseAt(DateTime(2026, 9, 14, 9)),
        ScheduleLessonPhase.unknown,
      );
    });

    test(
      'daily conflicts use campus clock times and events keep their phase',
      () {
        final date = DateTime(2026, 9, 7);
        final snapshot =
            scheduleTestSnapshot(
              entries: [
                ScheduleEntry(
                  id: 'a',
                  name: 'A',
                  campus: 'A',
                  weekday: 1,
                  startPeriod: 1,
                  endPeriod: 1,
                  weeks: [1],
                ),
                ScheduleEntry(
                  id: 'b',
                  name: 'B',
                  campus: 'B',
                  weekday: 1,
                  startPeriod: 2,
                  endPeriod: 2,
                  weeks: [1],
                ),
              ],
            ).copyWith(
              periodTimes: [
                PeriodTime(
                  number: 1,
                  campus: 'A',
                  startMinutes: 480,
                  endMinutes: 525,
                ),
                PeriodTime(
                  number: 2,
                  campus: 'B',
                  startMinutes: 510,
                  endMinutes: 555,
                ),
              ],
            );
        final day = ScheduleDay.fromSnapshot(snapshot, date);
        expect(day.hasConflict(day.lessons.first), isTrue);
        final event = ScheduleEvent(
          id: 'task',
          title: '小组讨论',
          date: date,
          category: ScheduleEventCategory.todo,
          startMinutes: 600,
          endMinutes: 660,
        );
        expect(
          event.phaseAt(DateTime(2026, 9, 7, 10, 30)),
          ScheduleEventPhase.ongoing,
        );
        expect(event.completed, isFalse);
        viewModel.selectAgendaDate(DateTime(2026, 1, 31));
        viewModel.shiftAgendaMonth(1);
        expect(viewModel.agendaDate, DateTime(2026, 2, 28));
        viewModel.returnToToday();
        now = DateTime(2026, 9, 13);
        viewModel.refreshToday();
        expect(viewModel.agendaDate, DateTime(2026, 9, 13));
      },
    );
  });
}
