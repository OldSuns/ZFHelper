import 'package:test/test.dart';
import 'package:zf_core/zf_core.dart';

const morning = PeriodSession.morning;
const afternoon = PeriodSession.afternoon;
PeriodTime p(int n, int start, int end, [String? campus]) =>
    PeriodTime(number: n, startMinutes: start, endMinutes: end, campus: campus);
PeriodTimeSection s(PeriodSession session, int first, int last) =>
    PeriodTimeSection(session: session, firstPeriod: first, lastPeriod: last);
PeriodSectionInput input(PeriodSession session, int count, int start) =>
    PeriodSectionInput(session: session, count: count, startMinutes: start);
List<(int, int, int)> rows(PeriodTimePlan plan) => [
  for (final p in plan.periodsForCampus(null))
    (p.number, p.startMinutes, p.endMinutes),
];
PeriodTimePlan sample() => PeriodTimePlan(
  periods: [p(1, 480, 520), p(2, 535, 580), p(3, 600, 630), p(4, 800, 850)],
  sections: [s(morning, 1, 3), s(afternoon, 4, 4)],
);

void main() {
  final invalid = throwsA(isA<PeriodTimeException>());
  group('period time drafts', () {
    test('generation restarts long breaks and preserves other campuses', () {
      final other = p(30, 10, 20, '南校区');
      final original = PeriodTimePlan(periods: [other, p(9, 1, 2)]);
      final plan = original.generate(
        inputs: [input(afternoon, 4, 800), input(morning, 4, 480)],
        classMinutes: 40,
        breakMinutes: 10,
        longBreakEvery: 2,
        longBreakMinutes: 20,
      );
      expect(rows(plan), [
        (1, 480, 520),
        (2, 530, 570),
        (3, 590, 630),
        (4, 640, 680),
        (5, 800, 840),
        (6, 850, 890),
        (7, 910, 950),
        (8, 960, 1000),
      ]);
      expect(plan.sections, [s(morning, 1, 4), s(afternoon, 5, 8)]);
      expect(plan.periodsForCampus(' 南校区 ').single, same(other));
      expect(() => plan.periods.clear(), throwsUnsupportedError);
      plan.validate();
    });

    test('edits preserve later durations and gaps within the section', () {
      final plan = sample();
      for (final (start, end) in [(490, null), (null, 530), (485, 530)]) {
        final changed = plan.edit(
          number: 1,
          startMinutes: start,
          endMinutes: end,
        );
        expect(rows(changed), [
          (1, start ?? 480, 530),
          (2, 545, 590),
          (3, 610, 640),
          (4, 800, 850),
        ]);
        changed.validate();
      }
      expect(rows(plan.changeBreak(afterNumber: 1, minutes: 30)), [
        (1, 480, 520),
        (2, 550, 595),
        (3, 615, 645),
        (4, 800, 850),
      ]);
      expect(rows(plan)[1], (2, 535, 580));
      expect(() => plan.changeBreak(afterNumber: 3, minutes: 5), invalid);
    });

    test('conflicting drafts remain editable but cannot pass validation', () {
      final plan = sample();
      final draft = plan.edit(
        number: 1,
        endMinutes: 550,
        shiftFollowing: false,
      );
      expect(draft.validate, invalid);
      draft.changeBreak(afterNumber: 1, minutes: 0).validate();
      final ungrouped = plan.withSections(sections: []);
      expect(rows(ungrouped.edit(number: 1, endMinutes: 550))[1], (
        2,
        535,
        580,
      ));
      final duplicate = PeriodTimePlan(periods: [p(1, 1, 2), p(1, 3, 4, ' ')]);
      expect(duplicate.validate, invalid);
      final overlapping = plan.generate(
        inputs: [input(morning, 2, 480), input(afternoon, 1, 500)],
        classMinutes: 40,
        breakMinutes: 10,
      );
      expect(overlapping.validate, invalid);
    });

    test('removal keeps identities and section metadata stays explicit', () {
      final plan = sample();
      expect(plan.removalClearsSection(number: 2), isTrue);
      expect(plan.removalClearsSection(number: 1), isFalse);
      final removed = plan.remove(number: 2);
      expect(rows(removed), [(1, 480, 520), (3, 600, 630), (4, 800, 850)]);
      expect(removed.sections, [s(afternoon, 4, 4)]);
      expect(plan.remove(number: 1).sections.first.firstPeriod, 2);
      expect(plan.remove(number: 4).sections, [s(morning, 1, 3)]);
      expect(() => plan.add(p(1, 1000, 1040, ' ')), invalid);
      expect(plan.add(p(5, 1000, 1040)).periods, hasLength(5));
      expect(() => removed.withSections(sections: [s(morning, 1, 3)]), invalid);
      for (final sections in [
        [s(morning, 1, 3), s(afternoon, 3, 4)],
        [s(afternoon, 1, 3), s(morning, 4, 4)],
        [s(morning, 1, 2), s(morning, 3, 4)],
        [s(morning, 1, 5)],
      ]) {
        expect(() => plan.withSections(sections: sections), invalid);
      }
    });

    test('physical bounds reject huge counts and midnight overflow', () {
      final empty = PeriodTimePlan(periods: []);
      for (final (count, start, duration) in [
        (1 << 50, 0, 1),
        (1, 1430, 20),
        (0, 480, 40),
      ]) {
        expect(
          () => empty.generate(
            inputs: [input(morning, count, start)],
            classMinutes: duration,
            breakMinutes: 0,
          ),
          invalid,
        );
      }
      final many = empty.generate(
        inputs: [input(morning, 16, 0)],
        classMinutes: 1,
        breakMinutes: 0,
      );
      expect(many.periods, hasLength(16));
      final midnight = PeriodTimePlan(periods: [p(1, 1400, 1440)]);
      expect(() => midnight.edit(number: 1, startMinutes: 1401), invalid);
      expect(midnight.periods.single.endMinutes, 1440);
    });
  });
}
