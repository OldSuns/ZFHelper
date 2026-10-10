import 'schedule_day.dart';
import 'teaching_calendar.dart';

enum ScheduleCountdownPhase {
  notToday,
  calendarUnknown,
  empty,
  ongoing,
  breakTime,
  upcoming,
  finished,
  timeUnknown,
}

/// A clock-derived view of today's current or next known teaching period.
final class ScheduleCountdown {
  ScheduleCountdown._({
    required this.phase,
    List<ScheduleLesson> lessons = const [],
    List<ScheduleLesson> uncertainLessons = const [],
    this.targetTime,
    this.remaining,
    this.hasConflict = false,
  }) : lessons = List.unmodifiable(lessons),
       uncertainLessons = List.unmodifiable(uncertainLessons);

  /// Computes a fresh countdown without retaining a timer or decrementing state.
  ///
  /// A browsed date is never treated as today. Incomplete times remain visible
  /// through [uncertainLessons], while their known periods can still contribute.
  factory ScheduleCountdown.fromDay(ScheduleDay day, DateTime now) {
    if (!sameScheduleDate(day.date, now)) {
      return ScheduleCountdown._(phase: ScheduleCountdownPhase.notToday);
    }
    if (!day.calendarKnown) {
      return ScheduleCountdown._(phase: ScheduleCountdownPhase.calendarUnknown);
    }
    if (day.lessons.isEmpty) {
      return ScheduleCountdown._(phase: ScheduleCountdownPhase.empty);
    }

    final uncertain = day.lessons
        .where((lesson) => !lesson.hasCompleteTimes)
        .toList();
    final periods =
        <(ScheduleLesson, PeriodTime)>[
          for (final lesson in day.lessons)
            for (final period in lesson.periods.whereType<PeriodTime>())
              (lesson, period),
        ]..sort(
          (left, right) =>
              left.$2.startMinutes.compareTo(right.$2.startMinutes),
        );
    final minutes = now.hour * Duration.minutesPerHour + now.minute;
    final active =
        periods
            .where(
              (item) =>
                  item.$2.startMinutes <= minutes &&
                  item.$2.endMinutes > minutes,
            )
            .toList()
          ..sort(
            (left, right) => left.$2.endMinutes.compareTo(right.$2.endMinutes),
          );
    final next = periods
        .where((item) => item.$2.startMinutes > minutes)
        .firstOrNull;
    if (active.isEmpty && next == null) {
      return ScheduleCountdown._(
        phase: uncertain.isEmpty
            ? ScheduleCountdownPhase.finished
            : ScheduleCountdownPhase.timeUnknown,
        uncertainLessons: uncertain,
      );
    }

    final focused = active.isNotEmpty
        ? active
        : periods
              .where((item) => item.$2.startMinutes == next!.$2.startMinutes)
              .toList();
    final lessons = focused.map((item) => item.$1).toSet().toList();
    final phase = active.isNotEmpty
        ? ScheduleCountdownPhase.ongoing
        : lessons.every(
            (lesson) => lesson.phaseAt(now) == ScheduleLessonPhase.breakTime,
          )
        ? ScheduleCountdownPhase.breakTime
        : ScheduleCountdownPhase.upcoming;
    final targetMinutes = active.isNotEmpty
        ? active.first.$2.endMinutes
        : next!.$2.startMinutes;
    // Construct a civil clock time so 24:00 is the next midnight, including
    // when the injected clock uses UTC rather than the device's local zone.
    final target = now.isUtc
        ? DateTime.utc(now.year, now.month, now.day, 0, targetMinutes)
        : DateTime(now.year, now.month, now.day, 0, targetMinutes);
    return ScheduleCountdown._(
      phase: phase,
      lessons: lessons,
      uncertainLessons: uncertain,
      targetTime: target,
      remaining: target.difference(now),
      hasConflict: lessons.length > 1 || lessons.any(day.hasConflict),
    );
  }

  final ScheduleCountdownPhase phase;

  /// The active courses, or all courses starting at the earliest known time.
  final List<ScheduleLesson> lessons;

  /// The courses with missing or inconsistent period times.
  final List<ScheduleLesson> uncertainLessons;

  /// The earliest active period's end, or the earliest upcoming period's start.
  final DateTime? targetTime;
  final Duration? remaining;

  /// Whether a focused course overlaps another course in the day's schedule.
  final bool hasConflict;

  /// Whether the remaining duration is within its final minute.
  bool get showSeconds =>
      remaining != null && remaining! <= const Duration(minutes: 1);

  /// The remaining seconds or minutes, rounded up to avoid showing zero early.
  int? get remainingUnits {
    final duration = remaining;
    if (duration == null) return null;
    final unit = _displayUnitMicroseconds;
    return (duration.inMicroseconds + unit - 1) ~/ unit;
  }

  /// The delay until the displayed count changes or reaches its time boundary.
  ///
  /// The owner's clock should also refresh at minute and date boundaries so
  /// other courses starting during an ongoing period become visible promptly.
  Duration? get nextRefresh {
    final duration = remaining;
    if (duration == null) return null;
    final unit = _displayUnitMicroseconds;
    final remainder = duration.inMicroseconds % unit;
    return Duration(microseconds: remainder == 0 ? unit : remainder);
  }

  int get _displayUnitMicroseconds => showSeconds
      ? Duration.microsecondsPerSecond
      : Duration.microsecondsPerMinute;
}
