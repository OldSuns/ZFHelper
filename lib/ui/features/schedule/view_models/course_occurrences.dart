import 'package:zf_core/zf_core.dart';

import 'timetable_view_model.dart';

final class CourseOccurrenceRow {
  const CourseOccurrenceRow({
    required this.entry,
    required this.week,
    this.override,
    this.part,
    this.isSource = false,
  });

  final ScheduleEntry entry;
  final int week;
  final ScheduleOccurrenceOverride? override;
  final ScheduleOccurrencePart? part;
  final bool isSource;
}

final class CourseOccurrences {
  CourseOccurrences._(this.byWeek, this.unassigned);

  factory CourseOccurrences.fromContext(
    ScheduleAdjustmentContext context,
    ScheduleEntry course,
  ) {
    final rootId = course.sourceEntryId ?? course.id;
    final records = context.overrides
        .where(
          (value) =>
              value.source.groupKey == course.groupKey ||
              value.source.id == rootId,
        )
        .toList();
    final roots = {
      rootId,
      for (final entry in context.baseline.entries)
        if (entry.groupKey == course.groupKey) entry.id,
      for (final record in records) record.source.id,
    };
    final parts = {
      for (final record in records)
        for (final part in record.parts) part.entry.id: (record, part),
    };
    final rows = <int, List<CourseOccurrenceRow>>{};
    final unassigned = <ScheduleEntry>[];
    for (final entry in context.effective.entries) {
      if (entry.groupKey != course.groupKey &&
          !roots.contains(entry.sourceEntryId ?? entry.id)) {
        continue;
      }
      if (entry.weeks.isEmpty) unassigned.add(entry);
      for (final week in entry.weeks) {
        final owner = parts[entry.id];
        rows
            .putIfAbsent(week, () => [])
            .add(
              CourseOccurrenceRow(
                entry: entry,
                week: week,
                override: owner?.$1,
                part: owner?.$2,
              ),
            );
      }
    }
    // The effective snapshot intentionally omits cancelled sources. Keep their
    // original rows visible beside the current results so they can be restored.
    for (final record in records) {
      rows
          .putIfAbsent(record.sourceWeek, () => [])
          .add(
            CourseOccurrenceRow(
              entry: record.source,
              week: record.sourceWeek,
              override: record,
              isSource: true,
            ),
          );
    }
    final weeks = rows.keys.toList()..sort();
    return CourseOccurrences._(
      Map.unmodifiable({
        for (final week in weeks)
          week: List<CourseOccurrenceRow>.unmodifiable(
            rows[week]!..sort(_compareRows),
          ),
      }),
      List.unmodifiable(unassigned),
    );
  }

  final Map<int, List<CourseOccurrenceRow>> byWeek;
  final List<ScheduleEntry> unassigned;

  static int _compareRows(CourseOccurrenceRow left, CourseOccurrenceRow right) {
    final day = (left.entry.weekday ?? 8).compareTo(right.entry.weekday ?? 8);
    if (day != 0) return day;
    final period = (left.entry.startPeriod ?? 0).compareTo(
      right.entry.startPeriod ?? 0,
    );
    if (period != 0) return period;
    if (left.isSource != right.isSource) return left.isSource ? -1 : 1;
    return left.entry.id.compareTo(right.entry.id);
  }
}
