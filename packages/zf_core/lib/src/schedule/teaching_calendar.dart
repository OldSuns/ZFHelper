import '../calendar_week.dart';

enum TeachingCalendarSource { unknown, school, user }

enum TeachingWeekStatus { unknown, beforeTerm, inTerm, afterTerm }

/// The relation between a civil date and a verified or user-set term calendar.
final class TeachingWeekPosition {
  const TeachingWeekPosition({required this.status, this.week});

  final TeachingWeekStatus status;

  /// The current teaching week, present only during the known term interval.
  final int? week;
}

/// Evidence for the first teaching week's Monday and the term's length.
final class TeachingCalendar {
  TeachingCalendar({
    DateTime? firstWeekMonday,
    this.totalWeeks,
    this.source = TeachingCalendarSource.unknown,
    this.sourceLabel,
  }) : firstWeekMonday = firstWeekMonday == null
           ? null
           : DateTime(
               firstWeekMonday.year,
               firstWeekMonday.month,
               firstWeekMonday.day,
             ) {
    if (this.firstWeekMonday?.weekday != null &&
        this.firstWeekMonday!.weekday != DateTime.monday) {
      throw ArgumentError('The first teaching week must start on a Monday.');
    }
    if (totalWeeks != null && totalWeeks! < 1) {
      throw ArgumentError('The number of teaching weeks must be positive.');
    }
    if (source == TeachingCalendarSource.unknown &&
        (firstWeekMonday != null || totalWeeks != null)) {
      throw ArgumentError('Calendar facts must identify their source.');
    }
  }

  const TeachingCalendar.unknown()
    : firstWeekMonday = null,
      totalWeeks = null,
      source = TeachingCalendarSource.unknown,
      sourceLabel = null;

  /// Derives the first Monday from an explicitly paired date and teaching week.
  factory TeachingCalendar.fromWeekReference({
    required DateTime date,
    required int week,
    int? totalWeeks,
    TeachingCalendarSource source = TeachingCalendarSource.school,
    String? sourceLabel,
  }) {
    if (week < 1 || (totalWeeks != null && week > totalWeeks)) {
      throw ArgumentError('The referenced teaching week is outside the term.');
    }
    return TeachingCalendar(
      firstWeekMonday: DateTime(
        date.year,
        date.month,
        date.day - date.weekday + 1 - (week - 1) * DateTime.daysPerWeek,
      ),
      totalWeeks: totalWeeks,
      source: source,
      sourceLabel: sourceLabel,
    );
  }

  final DateTime? firstWeekMonday;
  final int? totalWeeks;
  final TeachingCalendarSource source;
  final String? sourceLabel;

  /// Classifies [date] by civil days, independently of local DST transitions.
  TeachingWeekPosition positionOn(DateTime date) {
    final first = firstWeekMonday;
    if (first == null) {
      return const TeachingWeekPosition(status: TeachingWeekStatus.unknown);
    }
    final difference = DateTime.utc(
      date.year,
      date.month,
      date.day,
    ).difference(DateTime.utc(first.year, first.month, first.day)).inDays;
    if (difference < 0) {
      return const TeachingWeekPosition(status: TeachingWeekStatus.beforeTerm);
    }
    final week = difference ~/ DateTime.daysPerWeek + 1;
    if (totalWeeks != null && week > totalWeeks!) {
      return const TeachingWeekPosition(status: TeachingWeekStatus.afterTerm);
    }
    return TeachingWeekPosition(status: TeachingWeekStatus.inTerm, week: week);
  }

  /// Returns the dates for [week], or `null` when the first Monday is unknown.
  CalendarWeek? weekDates(int week) {
    if (week < 1) throw ArgumentError.value(week, 'week', 'Must be positive.');
    final first = firstWeekMonday;
    if (first == null) return null;
    return CalendarWeek.containing(
      DateTime(
        first.year,
        first.month,
        first.day + (week - 1) * DateTime.daysPerWeek,
      ),
    );
  }
}

/// A school or user-defined time range within one civil day.
final class PeriodTime {
  PeriodTime({
    required this.number,
    required this.startMinutes,
    required this.endMinutes,
    this.campus,
  }) {
    if (number < 1 ||
        startMinutes < 0 ||
        endMinutes > minutesPerDay ||
        startMinutes >= endMinutes) {
      throw ArgumentError('Invalid teaching period or time range.');
    }
  }

  static const minutesPerDay = 24 * 60;

  final int number;
  final int startMinutes;
  final int endMinutes;
  final String? campus;
}
