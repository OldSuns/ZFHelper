import 'package:test/test.dart';
import 'package:zf_core/src/schedule/academic_term.dart';
import 'package:zf_core/src/schedule/schedule_entry.dart';
import 'package:zf_core/src/schedule/schedule_occurrence.dart';
import 'package:zf_core/src/schedule/schedule_snapshot.dart';

void main() {
  final term = AcademicTerm(yearCode: '2026', termCode: '16', label: '2026 春');
  ScheduleEntry lesson({int start = 3, int end = 4}) => ScheduleEntry(
    id: 'course-1',
    teachingClassId: 'class-1',
    name: '有机化学',
    weekday: 2,
    startPeriod: start,
    endPeriod: end,
    weeks: [2, 4],
  );
  ScheduleSnapshot snapshot(List<ScheduleEntry> entries) => ScheduleSnapshot(
    term: term,
    entries: entries,
    fetchedAt: DateTime.utc(2026, 9, 13),
  );

  ScheduleOccurrenceChange change({
    ScheduleChangeKind kind = ScheduleChangeKind.reschedule,
    int targetWeek = 3,
    int targetWeekday = 5,
    int? targetStartPeriod,
    int? targetEndPeriod,
  }) => ScheduleOccurrenceChange(
    selection: ScheduleOccurrenceSelection.capture(
      baseline: snapshot([lesson()]),
      overrides: const [],
      entry: lesson(),
      week: 2,
    ),
    kind: kind,
    targetWeek: kind == ScheduleChangeKind.cancel ? null : targetWeek,
    targetWeekday: kind == ScheduleChangeKind.cancel ? null : targetWeekday,
    targetStartPeriod: targetStartPeriod,
    targetEndPeriod: targetEndPeriod,
  );

  test('target end period overrides the preserved lesson count', () {
    final baseline = snapshot([lesson()]);
    final overrides = applyScheduleOccurrenceChanges(
      baseline: baseline,
      overrides: const [],
      changes: [
        change(targetStartPeriod: 6, targetEndPeriod: 8),
        ScheduleOccurrenceChange(
          selection: ScheduleOccurrenceSelection.capture(
            baseline: baseline,
            overrides: const [],
            entry: lesson(),
            week: 4,
          ),
          kind: ScheduleChangeKind.cancel,
        ),
      ],
    );
    final moved = overrides
        .firstWhere((record) => record.parts.isNotEmpty)
        .parts
        .single
        .entry;
    expect(moved.weeks, [3]);
    expect(moved.weekday, 5);
    expect(moved.startPeriod, 6);
    expect(moved.endPeriod, 8);
  });

  test('target end period keeps the original count when omitted', () {
    final overrides = applyScheduleOccurrenceChanges(
      baseline: snapshot([lesson()]),
      overrides: const [],
      changes: [change(targetStartPeriod: 6)],
    );
    expect(overrides.single.parts.single.entry.endPeriod, 7);
  });

  test('target end period is rejected without a target start', () {
    expect(
      () => change(targetEndPeriod: 8),
      throwsA(
        isA<ScheduleOccurrenceException>().having(
          (error) => error.message,
          'message',
          '填写了目标结束节次时，也需要填写目标开始节次。',
        ),
      ),
    );
  });

  test('target end period cannot precede the target start', () {
    expect(
      () => change(targetStartPeriod: 6, targetEndPeriod: 5),
      throwsA(
        isA<ScheduleOccurrenceException>().having(
          (error) => error.message,
          'message',
          '目标结束节次不能早于目标开始节次。',
        ),
      ),
    );
  });

  test('target end period beyond maxPeriod is rejected', () {
    expect(
      () => applyScheduleOccurrenceChanges(
        baseline: snapshot([lesson()]),
        overrides: const [],
        changes: [change(targetStartPeriod: 6, targetEndPeriod: 9)],
        maxPeriod: 8,
      ),
      throwsA(isA<ScheduleOccurrenceException>()),
    );
  });
}
