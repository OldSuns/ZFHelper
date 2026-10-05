enum ScheduleEntryOrigin { imported, local }

enum ScheduleEntryKind { lesson, practice, unscheduled }

/// One teaching arrangement, including arrangements without a grid position.
final class ScheduleEntry {
  ScheduleEntry({
    required this.id,
    required this.name,
    this.teachingClassId,
    this.courseCode,
    this.teacher,
    this.location,
    this.campus,
    this.weekday,
    this.startPeriod,
    this.endPeriod,
    required Iterable<int> weeks,
    this.rawWeeks,
    Map<String, String> metadata = const {},
    this.origin = ScheduleEntryOrigin.imported,
    this.kind = ScheduleEntryKind.lesson,
  }) : weeks = Set.unmodifiable(weeks.toList()..sort()),
       metadata = Map.unmodifiable(metadata) {
    if (id.trim().isEmpty || name.trim().isEmpty) {
      throw ArgumentError('A teaching arrangement needs an identity and name.');
    }
    if (weekday != null &&
        (weekday! < DateTime.monday || weekday! > DateTime.sunday)) {
      throw ArgumentError('The teaching weekday must be between 1 and 7.');
    }
    if ((startPeriod == null) != (endPeriod == null) ||
        (startPeriod != null &&
            (startPeriod! < 1 || endPeriod! < startPeriod!))) {
      throw ArgumentError('The teaching period range is invalid.');
    }
    if (this.weeks.any((week) => week < 1)) {
      throw ArgumentError('Teaching weeks must be positive.');
    }
  }

  final String id;
  final String? teachingClassId;
  final String? courseCode;
  final String name;
  final String? teacher;
  final String? location;
  final String? campus;
  final int? weekday;
  final int? startPeriod;
  final int? endPeriod;
  final Set<int> weeks;
  final String? rawWeeks;
  final Map<String, String> metadata;
  final ScheduleEntryOrigin origin;
  final ScheduleEntryKind kind;

  bool hasSameArrangement(ScheduleEntry other) =>
      teachingClassId == other.teachingClassId &&
      courseCode == other.courseCode &&
      name == other.name &&
      teacher == other.teacher &&
      location == other.location &&
      campus == other.campus &&
      weekday == other.weekday &&
      (metadata['xqh_id'] == null ||
          other.metadata['xqh_id'] == null ||
          metadata['xqh_id'] == other.metadata['xqh_id']) &&
      startPeriod == other.startPeriod &&
      endPeriod == other.endPeriod &&
      kind == other.kind &&
      weeks.length == other.weeks.length &&
      weeks.containsAll(other.weeks);

  ScheduleEntry withMetadata(Map<String, String> values) => ScheduleEntry(
    id: id,
    name: name,
    teachingClassId: teachingClassId,
    courseCode: courseCode,
    teacher: teacher,
    location: location,
    campus: campus,
    weekday: weekday,
    startPeriod: startPeriod,
    endPeriod: endPeriod,
    weeks: weeks,
    rawWeeks: rawWeeks,
    metadata: values,
    origin: origin,
    kind: kind,
  );

  /// A grouping key that never merges unrelated teaching classes by name.
  String get groupKey =>
      teachingClassId == null ? 'arrangement:$id' : 'class:$teachingClassId';

  /// Whether enough information is available to place this on a weekly grid.
  bool get isPlaced =>
      weekday != null && startPeriod != null && weeks.isNotEmpty;

  /// Reports whether this arrangement explicitly includes [week].
  bool occursInWeek(int week) => weeks.contains(week);

  /// Reports overlapping periods in at least one shared teaching week.
  ///
  /// When [week] is supplied, conflicts in other weeks do not count.
  bool conflictsWith(ScheduleEntry other, {int? week}) {
    if (!isPlaced ||
        !other.isPlaced ||
        weekday != other.weekday ||
        startPeriod! > other.endPeriod! ||
        other.startPeriod! > endPeriod!) {
      return false;
    }
    if (week != null) return occursInWeek(week) && other.occursInWeek(week);
    return weeks.any(other.weeks.contains);
  }
}
