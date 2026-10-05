import 'package:test/test.dart';
import 'package:zf_core/zf_core.dart';

void main() {
  group('CalendarWeek.containing', () {
    test('returns Monday through Sunday in calendar order', () {
      final week = CalendarWeek.containing(DateTime(2026, 9, 9, 16, 45));

      expect(week.start, DateTime(2026, 9, 7));
      expect(week.end, DateTime(2026, 9, 13));
      expect(week.days, [
        DateTime(2026, 9, 7),
        DateTime(2026, 9, 8),
        DateTime(2026, 9, 9),
        DateTime(2026, 9, 10),
        DateTime(2026, 9, 11),
        DateTime(2026, 9, 12),
        DateTime(2026, 9, 13),
      ]);
    });

    test('keeps a Monday in its own week', () {
      final week = CalendarWeek.containing(DateTime(2026, 9, 7));

      expect(week.start, DateTime(2026, 9, 7));
      expect(week.end, DateTime(2026, 9, 13));
    });

    test('keeps Sunday in the week that is ending', () {
      final week = CalendarWeek.containing(DateTime(2026, 9, 13, 23, 59));

      expect(week.start, DateTime(2026, 9, 7));
      expect(week.end, DateTime(2026, 9, 13));
    });

    test('spans a month boundary', () {
      final week = CalendarWeek.containing(DateTime(2026, 10, 1));

      expect(week.start, DateTime(2026, 9, 28));
      expect(week.end, DateTime(2026, 10, 4));
      expect(week.days[2], DateTime(2026, 9, 30));
      expect(week.days[3], DateTime(2026, 10, 1));
    });

    test('spans a year boundary', () {
      final week = CalendarWeek.containing(DateTime(2026, 1, 1));

      expect(week.start, DateTime(2025, 12, 29));
      expect(week.end, DateTime(2026, 1, 4));
      expect(week.days[2], DateTime(2025, 12, 31));
      expect(week.days[3], DateTime(2026, 1, 1));
    });

    test('includes February 29 in a leap year', () {
      final week = CalendarWeek.containing(DateTime(2024, 2, 29));

      expect(week.start, DateTime(2024, 2, 26));
      expect(week.end, DateTime(2024, 3, 3));
      expect(week.days[3], DateTime(2024, 2, 29));
      expect(week.days[4], DateTime(2024, 3, 1));
    });

    test('uses UTC input calendar fields without converting its time zone', () {
      final week = CalendarWeek.containing(DateTime.utc(2026, 9, 13, 23, 59));

      expect(week.start, DateTime(2026, 9, 7));
      expect(week.end, DateTime(2026, 9, 13));
      expect(week.days.every((day) => !day.isUtc), isTrue);
    });
  });

  group('CalendarWeek.shift', () {
    test('moves forwards and backwards across year boundaries', () {
      final week = CalendarWeek.containing(DateTime(2026, 1, 1));

      expect(week.shift(2).start, DateTime(2026, 1, 12));
      expect(week.shift(-1).start, DateTime(2025, 12, 22));
      expect(week.start, DateTime(2025, 12, 29));
    });

    test('moves from a leap week into March', () {
      final week = CalendarWeek.containing(DateTime(2024, 2, 29));

      expect(week.shift(1).start, DateTime(2024, 3, 4));
      expect(week.shift(-1).end, DateTime(2024, 2, 25));
    });

    test('a zero offset and a round trip preserve the same week', () {
      final week = CalendarWeek.containing(DateTime(2026, 9, 9));

      expect(week.shift(0), week);
      expect(week.shift(53).shift(-53), week);
    });
  });

  group('CalendarWeek.contains', () {
    test('ignores the time of day at both boundaries', () {
      final week = CalendarWeek.containing(DateTime(2026, 9, 9));

      expect(week.contains(DateTime(2026, 9, 7)), isTrue);
      expect(
        week.contains(DateTime(2026, 9, 13, 23, 59, 59, 999, 999)),
        isTrue,
      );
      expect(week.contains(DateTime(2026, 9, 6, 23, 59, 59)), isFalse);
      expect(week.contains(DateTime(2026, 9, 14)), isFalse);
    });

    test('uses UTC calendar fields without moving dates', () {
      final week = CalendarWeek.containing(DateTime(2026, 9, 9));

      expect(week.contains(DateTime.utc(2026, 9, 13, 23, 59)), isTrue);
      expect(week.contains(DateTime.utc(2026, 9, 14)), isFalse);
    });
  });

  test('days cannot be replaced, appended, or removed', () {
    final week = CalendarWeek.containing(DateTime(2026, 9, 9));

    expect(() => week.days[0] = DateTime(2020), throwsUnsupportedError);
    expect(() => week.days.add(DateTime(2020)), throwsUnsupportedError);
    expect(() => week.days.removeLast(), throwsUnsupportedError);
    expect(week.days, hasLength(7));
    expect(week.start, DateTime(2026, 9, 7));
  });

  test('equality and hashing identify the Monday calendar date', () {
    final monday = CalendarWeek.containing(DateTime(2026, 9, 7));
    final sunday = CalendarWeek.containing(DateTime.utc(2026, 9, 13, 23, 59));
    final nextWeek = CalendarWeek.containing(DateTime(2026, 9, 14));

    expect(monday, sunday);
    expect(monday.hashCode, sunday.hashCode);
    expect(monday, isNot(nextWeek));
    expect({monday, sunday, nextWeek}, hasLength(2));
  });
}
