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
    this.sourceEntryId,
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
    if (sourceEntryId != null &&
        (sourceEntryId!.trim().isEmpty || sourceEntryId == id)) {
      throw ArgumentError(
        'A projected source identity must name another entry.',
      );
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

  /// The root arrangement used for grouping a projected occurrence.
  ///
  /// Ownership is persisted by the occurrence override, not by this field.
  final String? sourceEntryId;

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

  /// Whether persisted fields match, ignoring projection-only grouping.
  bool hasSameValue(ScheduleEntry other) =>
      id == other.id &&
      origin == other.origin &&
      rawWeeks == other.rawWeeks &&
      hasSameArrangement(other) &&
      metadata.length == other.metadata.length &&
      metadata.entries.every((item) => other.metadata[item.key] == item.value);

  ScheduleEntry copyWith({
    String? id,
    String? name,
    String? teachingClassId,
    String? courseCode,
    String? teacher,
    String? location,
    bool clearLocation = false,
    String? campus,
    int? weekday,
    bool clearWeekday = false,
    int? startPeriod,
    int? endPeriod,
    bool clearPeriods = false,
    Iterable<int>? weeks,
    String? rawWeeks,
    bool clearRawWeeks = false,
    Map<String, String>? metadata,
    ScheduleEntryOrigin? origin,
    ScheduleEntryKind? kind,
    String? sourceEntryId,
    bool clearSourceEntryId = false,
  }) => ScheduleEntry(
    id: id ?? this.id,
    name: name ?? this.name,
    teachingClassId: teachingClassId ?? this.teachingClassId,
    courseCode: courseCode ?? this.courseCode,
    teacher: teacher ?? this.teacher,
    location: clearLocation ? null : location ?? this.location,
    campus: campus ?? this.campus,
    weekday: clearWeekday ? null : weekday ?? this.weekday,
    startPeriod: clearPeriods ? null : startPeriod ?? this.startPeriod,
    endPeriod: clearPeriods ? null : endPeriod ?? this.endPeriod,
    weeks: weeks ?? this.weeks,
    rawWeeks: clearRawWeeks ? null : rawWeeks ?? this.rawWeeks,
    metadata: metadata ?? this.metadata,
    origin: origin ?? this.origin,
    kind: kind ?? this.kind,
    sourceEntryId: clearSourceEntryId
        ? null
        : sourceEntryId ?? this.sourceEntryId,
  );

  ScheduleEntry withMetadata(Map<String, String> values) =>
      copyWith(metadata: values);

  /// A grouping key that never merges unrelated teaching classes by name.
  String get groupKey => teachingClassId == null
      ? 'arrangement:${sourceEntryId ?? id}'
      : 'class:$teachingClassId';

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
