import 'academic_term.dart';
import 'schedule_entry.dart';
import 'teaching_calendar.dart';

/// A complete successful import for one account's one academic term.
///
/// The account scope belongs to the repository key. The snapshot carries no
/// credentials or session data and remains useful after that session expires.
final class ScheduleSnapshot {
  ScheduleSnapshot({
    required this.term,
    required List<ScheduleEntry> entries,
    required this.fetchedAt,
    this.calendar = const TeachingCalendar.unknown(),
    List<PeriodTime> periodTimes = const [],
    this.sourceLabel,
    List<String> importWarnings = const [],
  }) : entries = List.unmodifiable(entries),
       periodTimes = List.unmodifiable(periodTimes),
       importWarnings = List.unmodifiable(importWarnings) {
    if (entries.map((entry) => entry.id).toSet().length != entries.length) {
      throw ArgumentError('A schedule contains duplicate arrangement IDs.');
    }
  }

  final AcademicTerm term;
  final List<ScheduleEntry> entries;
  final DateTime fetchedAt;
  final TeachingCalendar calendar;
  final List<PeriodTime> periodTimes;
  final String? sourceLabel;
  final List<String> importWarnings;

  /// The largest imported week number, not evidence of the term's duration.
  int get observedMaxWeek => entries.fold(
    0,
    (highest, entry) => entry.weeks.fold(
      highest,
      (previous, week) => week > previous ? week : previous,
    ),
  );

  /// A known calendar bounds navigation, but never hides actual arrangements.
  /// With an unknown term length, the user can keep browsing later weeks.
  int? get navigationWeekLimit {
    final total = calendar.totalWeeks;
    if (total == null) return null;
    final lastCourse = observedMaxWeek;
    return lastCourse > total ? lastCourse : total;
  }

  /// The largest known period, or zero when no period information is available.
  int get maxPeriod {
    var highest = 0;
    for (final entry in entries) {
      if (entry.endPeriod != null && entry.endPeriod! > highest) {
        highest = entry.endPeriod!;
      }
    }
    for (final period in periodTimes) {
      if (period.number > highest) highest = period.number;
    }
    return highest;
  }

  ScheduleSnapshot copyWith({
    AcademicTerm? term,
    List<ScheduleEntry>? entries,
    DateTime? fetchedAt,
    TeachingCalendar? calendar,
    List<PeriodTime>? periodTimes,
    String? sourceLabel,
    bool clearSourceLabel = false,
    List<String>? importWarnings,
  }) => ScheduleSnapshot(
    term: term ?? this.term,
    entries: entries ?? this.entries,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    calendar: calendar ?? this.calendar,
    periodTimes: periodTimes ?? this.periodTimes,
    sourceLabel: clearSourceLabel ? null : sourceLabel ?? this.sourceLabel,
    importWarnings: importWarnings ?? this.importWarnings,
  );
}
