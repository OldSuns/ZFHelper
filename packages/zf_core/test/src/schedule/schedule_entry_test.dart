import 'package:test/test.dart';
import 'package:zf_core/src/schedule/schedule_entry.dart';

void main() {
  ScheduleEntry entry({
    required String id,
    String? classId,
    int weekday = 1,
    int start = 1,
    int end = 2,
    Iterable<int> weeks = const [1, 3, 5],
  }) => ScheduleEntry(
    id: id,
    teachingClassId: classId,
    name: '同名课程',
    weekday: weekday,
    startPeriod: start,
    endPeriod: end,
    weeks: weeks,
  );

  test(
    'conflicts depend on viewed teaching week as well as period overlap',
    () {
      final odd = entry(id: 'odd');
      final even = entry(id: 'even', weeks: [2, 4, 6]);
      final overlapping = entry(id: 'overlap', start: 2, end: 3, weeks: [3, 4]);
      expect(odd.conflictsWith(even), isFalse);
      expect(odd.conflictsWith(overlapping), isTrue);
      expect(odd.conflictsWith(overlapping, week: 3), isTrue);
      expect(odd.conflictsWith(overlapping, week: 1), isFalse);
      expect(odd.conflictsWith(entry(id: 'next', start: 3, end: 4)), isFalse);
      expect(odd.conflictsWith(entry(id: 'another-day', weekday: 2)), isFalse);
    },
  );

  test('unplaced courses do not create artificial conflicts', () {
    final pending = ScheduleEntry(id: 'pending', name: '待安排课程', weeks: [1]);
    expect(pending.isPlaced, isFalse);
    expect(pending.conflictsWith(entry(id: 'placed')), isFalse);
  });

  test('same names never establish teaching-class identity', () {
    expect(entry(id: 'a').groupKey, isNot(entry(id: 'b').groupKey));
    expect(
      entry(id: 'a', classId: 'same').groupKey,
      entry(id: 'b', classId: 'same').groupKey,
    );
  });

  test('caller mutations cannot change a saved arrangement', () {
    final input = <int>{1, 3};
    final value = entry(id: 'immutable', weeks: input);
    input.add(5);
    expect(value.weeks, {1, 3});
    expect(() => value.weeks.add(5), throwsUnsupportedError);
    expect(() => value.metadata['xf'] = '4', throwsUnsupportedError);
  });
}
