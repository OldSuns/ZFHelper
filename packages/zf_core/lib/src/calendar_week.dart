/// A Monday-to-Sunday calendar week, independent of a school's teaching weeks.
///
/// Inputs are interpreted by their year, month, and day without time zone
/// conversion. Returned dates use local time; hours and smaller units in an
/// input do not affect its calendar date.
final class CalendarWeek {
  factory CalendarWeek.containing(DateTime date) {
    final monday = DateTime(
      date.year,
      date.month,
      date.day - (date.weekday - DateTime.monday),
    );
    return CalendarWeek._(monday);
  }

  CalendarWeek._(DateTime monday)
    : days = List<DateTime>.unmodifiable(
        List<DateTime>.generate(
          DateTime.daysPerWeek,
          (offset) => DateTime(monday.year, monday.month, monday.day + offset),
        ),
      );

  /// The week's Monday, expressed as a local date.
  DateTime get start => days.first;

  /// The week's Sunday, expressed as a local date.
  DateTime get end => days.last;

  /// The seven local dates in order, in an unmodifiable list.
  final List<DateTime> days;

  /// Returns the week [weekOffset] calendar weeks after this one.
  ///
  /// Negative offsets move backwards. Calendar arithmetic preserves dates
  /// across daylight-saving changes without assuming a day lasts 24 hours.
  CalendarWeek shift(int weekOffset) => CalendarWeek.containing(
    DateTime(
      start.year,
      start.month,
      start.day + weekOffset * DateTime.daysPerWeek,
    ),
  );

  /// Reports whether the calendar date of [date] belongs to this week.
  bool contains(DateTime date) => days.any(
    (day) =>
        day.year == date.year && day.month == date.month && day.day == date.day,
  );

  @override
  bool operator ==(Object other) =>
      other is CalendarWeek &&
      start.year == other.start.year &&
      start.month == other.start.month &&
      start.day == other.start.day;

  @override
  int get hashCode => Object.hash(start.year, start.month, start.day);
}
