import 'package:test/test.dart';
import 'package:zf_core/src/schedule/teaching_calendar.dart';

void main() {
  group('teaching calendar', () {
    final calendar = TeachingCalendar(
      firstWeekMonday: DateTime(2025, 12, 29),
      totalWeeks: 3,
      source: TeachingCalendarSource.school,
    );

    test('distinguishes before term, current week and after term', () {
      expect(
        calendar.positionOn(DateTime(2025, 12, 28)).status,
        TeachingWeekStatus.beforeTerm,
      );
      expect(calendar.positionOn(DateTime(2025, 12, 29)).week, 1);
      expect(calendar.positionOn(DateTime(2026, 1, 4, 23, 59)).week, 1);
      expect(calendar.positionOn(DateTime(2026, 1, 5)).week, 2);
      expect(calendar.positionOn(DateTime(2026, 1, 18)).week, 3);
      final after = calendar.positionOn(DateTime(2026, 1, 19));
      expect(after.status, TeachingWeekStatus.afterTerm);
      expect(after.week, isNull);
    });

    test('preserves civil dates across a year and leap day', () {
      final days = calendar.weekDates(2)!.days;
      expect(days.first, DateTime(2026, 1, 5));
      expect(days.last, DateTime(2026, 1, 11));
      final leapTerm = TeachingCalendar(
        firstWeekMonday: DateTime(2024, 2, 26),
        source: TeachingCalendarSource.school,
      );
      expect(leapTerm.positionOn(DateTime(2024, 2, 29)).week, 1);
      expect(leapTerm.positionOn(DateTime(2024, 3, 4)).week, 2);
    });

    test('uses the supplied date fields rather than the UTC/local instant', () {
      expect(calendar.positionOn(DateTime.utc(2026, 1, 4, 23, 59)).week, 1);
      expect(calendar.positionOn(DateTime(2026, 1, 4, 0, 1)).week, 1);
      final aroundDst = TeachingCalendar(
        firstWeekMonday: DateTime(2026, 3, 2),
        source: TeachingCalendarSource.school,
      );
      expect(aroundDst.weekDates(2)!.start, DateTime(2026, 3, 9));
      expect(aroundDst.positionOn(DateTime(2026, 3, 9, 0, 1)).week, 2);
    });

    test('derives the first Monday from an explicit weekday/week pair', () {
      final evidence = TeachingCalendar.fromWeekReference(
        date: DateTime(2026, 9, 13),
        week: 2,
        totalWeeks: 20,
        sourceLabel: '学校校历',
      );
      expect(evidence.firstWeekMonday, DateTime(2026, 8, 31));
      expect(evidence.positionOn(DateTime(2026, 9, 14)).week, 3);
      expect(evidence.source, TeachingCalendarSource.school);
    });

    test(
      'does not invent a current teaching week when the anchor is absent',
      () {
        const unknown = TeachingCalendar.unknown();
        final lengthOnly = TeachingCalendar(
          totalWeeks: 30,
          source: TeachingCalendarSource.school,
        );
        expect(
          unknown.positionOn(DateTime(2026, 9, 13)).status,
          TeachingWeekStatus.unknown,
        );
        expect(lengthOnly.positionOn(DateTime(2026, 9, 13)).week, isNull);
        expect(lengthOnly.weekDates(1), isNull);
      },
    );

    test('does not impose a 25-week term or infer an unknown end', () {
      final longTerm = TeachingCalendar(
        firstWeekMonday: DateTime(2026, 1, 5),
        totalWeeks: 30,
        source: TeachingCalendarSource.school,
      );
      final week30 = longTerm.weekDates(30)!.start;
      expect(longTerm.positionOn(week30).week, 30);
      final openEnd = TeachingCalendar(
        firstWeekMonday: DateTime(2026, 1, 5),
        source: TeachingCalendarSource.user,
      );
      expect(openEnd.positionOn(openEnd.weekDates(31)!.start).week, 31);
    });

    test('rejects a reporting date used as a non-Monday anchor', () {
      expect(
        () => TeachingCalendar(
          firstWeekMonday: DateTime(2026, 9, 13),
          source: TeachingCalendarSource.user,
        ),
        throwsArgumentError,
      );
      expect(() => calendar.weekDates(0), throwsArgumentError);
      expect(
        () => TeachingCalendar(
          totalWeeks: 0,
          source: TeachingCalendarSource.school,
        ),
        throwsArgumentError,
      );
      expect(
        () => TeachingCalendar(firstWeekMonday: DateTime(2026, 9, 7)),
        throwsArgumentError,
      );
    });
  });
}
