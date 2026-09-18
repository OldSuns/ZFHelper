import 'schedule_entry.dart';
import 'schedule_snapshot.dart';
import 'teaching_calendar.dart';

/// Resolves a period only when its campus and clock times are unambiguous.
PeriodTime? schedulePeriodTime(
  ScheduleSnapshot snapshot,
  int number, {
  String? campus,
}) {
  final periods = snapshot.periodTimes
      .where((period) => period.number == number)
      .toList();
  var candidates = periods;
  if (campus?.trim().isNotEmpty ?? false) {
    final matching = periods
        .where((period) => period.campus?.trim() == campus!.trim())
        .toList();
    candidates = matching.isNotEmpty
        ? matching
        : periods
              .where((period) => period.campus?.trim().isEmpty ?? true)
              .toList();
  }
  if (candidates.isEmpty) return null;
  final first = candidates.first;
  return candidates.every(
        (period) =>
            period.startMinutes == first.startMinutes &&
            period.endMinutes == first.endMinutes,
      )
      ? first
      : null;
}

enum ScheduleLessonPhase { upcoming, ongoing, breakTime, finished, unknown }

/// A dated occurrence of one arrangement, including its actual class breaks.
final class ScheduleLesson {
  ScheduleLesson({
    required this.entry,
    required DateTime date,
    required this.week,
    required ScheduleSnapshot snapshot,
  }) : date = DateTime(date.year, date.month, date.day),
       periods = List.unmodifiable([
         if (entry.startPeriod != null)
           for (
             var number = entry.startPeriod!;
             number <= entry.endPeriod!;
             number++
           )
             schedulePeriodTime(
               snapshot,
               number,
               campus: entry.campus ?? snapshot.periodCampus,
             ),
       ]);

  final ScheduleEntry entry;
  final DateTime date;
  final int week;
  final List<PeriodTime?> periods;

  bool get hasCompleteTimes {
    if (periods.isEmpty || periods.any((period) => period == null)) {
      return false;
    }
    for (var index = 1; index < periods.length; index++) {
      if (periods[index]!.startMinutes < periods[index - 1]!.endMinutes) {
        return false;
      }
    }
    return true;
  }

  int? get startMinutes =>
      hasCompleteTimes ? periods.first!.startMinutes : null;
  int? get endMinutes => hasCompleteTimes ? periods.last!.endMinutes : null;

  PeriodTime? activePeriodAt(DateTime now) {
    if (!sameScheduleDate(date, now)) return null;
    final minutes = now.hour * 60 + now.minute;
    return periods
        .whereType<PeriodTime>()
        .where(
          (period) =>
              minutes >= period.startMinutes && minutes < period.endMinutes,
        )
        .firstOrNull;
  }

  ScheduleLessonPhase phaseAt(DateTime now) {
    final day = DateTime(now.year, now.month, now.day);
    if (day.isAfter(date)) return ScheduleLessonPhase.finished;
    if (day.isBefore(date)) return ScheduleLessonPhase.upcoming;
    if (activePeriodAt(now) != null) return ScheduleLessonPhase.ongoing;
    if (!hasCompleteTimes) return ScheduleLessonPhase.unknown;
    final minutes = now.hour * 60 + now.minute;
    if (minutes < startMinutes!) return ScheduleLessonPhase.upcoming;
    if (minutes >= endMinutes!) return ScheduleLessonPhase.finished;
    return ScheduleLessonPhase.breakTime;
  }

  bool conflictsWith(ScheduleLesson other) {
    if (!sameScheduleDate(date, other.date)) return false;
    if (!hasCompleteTimes || !other.hasCompleteTimes) {
      return entry.conflictsWith(other.entry, week: week);
    }
    return periods.whereType<PeriodTime>().any(
      (left) => other.periods.whereType<PeriodTime>().any(
        (right) =>
            left.startMinutes < right.endMinutes &&
            right.startMinutes < left.endMinutes,
      ),
    );
  }
}

/// One civil day's courses derived from the effective, saved timetable.
final class ScheduleDay {
  ScheduleDay._({
    required this.date,
    required this.week,
    required this.lessons,
    required this.usesPeriodOrder,
    required this.calendarKnown,
    required this.beyondCalendar,
  });

  factory ScheduleDay.fromSnapshot(ScheduleSnapshot? snapshot, DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final week = snapshot?.calendar.weekNumberOn(day);
    final lessons = <ScheduleLesson>[
      if (snapshot != null && week != null)
        for (final entry in snapshot.entries)
          if (entry.weekday == day.weekday && entry.occursInWeek(week))
            ScheduleLesson(
              entry: entry,
              date: day,
              week: week,
              snapshot: snapshot,
            ),
    ];
    // Use one ordering for the whole day; missing clock times must not move an
    // early numbered class behind all classes whose clock times are known.
    final usesPeriodOrder = lessons.any(
      (lesson) => lesson.entry.startPeriod != null && !lesson.hasCompleteTimes,
    );
    lessons.sort((left, right) {
      if (!usesPeriodOrder) {
        final start = _compareKnownNumbers(
          left.startMinutes,
          right.startMinutes,
        );
        if (start != 0) return start;
      }
      final startPeriod = _compareKnownNumbers(
        left.entry.startPeriod,
        right.entry.startPeriod,
      );
      if (startPeriod != 0) return startPeriod;
      final endPeriod = _compareKnownNumbers(
        left.entry.endPeriod,
        right.entry.endPeriod,
      );
      if (endPeriod != 0) return endPeriod;
      final name = left.entry.name.compareTo(right.entry.name);
      return name != 0 ? name : left.entry.id.compareTo(right.entry.id);
    });
    return ScheduleDay._(
      date: day,
      week: week,
      lessons: List.unmodifiable(lessons),
      usesPeriodOrder: usesPeriodOrder,
      calendarKnown: snapshot?.calendar.firstWeekMonday != null,
      beyondCalendar:
          snapshot?.calendar.totalWeeks != null &&
          week != null &&
          week > snapshot!.calendar.totalWeeks!,
    );
  }

  final DateTime date;
  final int? week;
  final List<ScheduleLesson> lessons;
  final bool usesPeriodOrder;
  final bool calendarKnown;
  final bool beyondCalendar;

  bool hasConflict(ScheduleLesson lesson) => lessons.any(
    (other) => other.entry.id != lesson.entry.id && lesson.conflictsWith(other),
  );
}

int _compareKnownNumbers(int? left, int? right) {
  if (left == right) return 0;
  if (left == null) return 1;
  if (right == null) return -1;
  return left.compareTo(right);
}

bool sameScheduleDate(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;
