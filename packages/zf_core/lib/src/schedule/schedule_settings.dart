import 'period_time_plan.dart';
import 'schedule_entry.dart';
import 'schedule_occurrence.dart';
import 'schedule_snapshot.dart';
import 'teaching_calendar.dart';

/// User changes stored separately from the school's latest successful import.
final class ScheduleSettings {
  ScheduleSettings({
    this.calendarOverride,
    List<PeriodTime> periodTimes = const [],
    List<PeriodTimeSection> periodSections = const [],
    bool? useCustomPeriodTimes,
    this.periodCampus,
    List<ScheduleEntry> localEntries = const [],
    Iterable<String> hiddenEntryIds = const [],
    List<ScheduleOccurrenceOverride> occurrenceOverrides = const [],
    this.preferAgenda = false,
  }) : periodTimes = List.unmodifiable(periodTimes),
       periodSections = List.unmodifiable(periodSections),
       useCustomPeriodTimes = useCustomPeriodTimes ?? periodTimes.isNotEmpty,
       localEntries = List.unmodifiable(localEntries),
       hiddenEntryIds = Set.unmodifiable(hiddenEntryIds),
       occurrenceOverrides = List.unmodifiable(occurrenceOverrides) {
    validatePeriodTimeSections(this.periodTimes, this.periodSections);
    if (calendarOverride != null &&
        calendarOverride!.source != TeachingCalendarSource.user) {
      throw ArgumentError(
        'A calendar override must identify the user as source.',
      );
    }
    if (localEntries.any(
      (entry) =>
          entry.origin != ScheduleEntryOrigin.local ||
          entry.sourceEntryId != null,
    )) {
      throw ArgumentError('Local arrangements must identify the local origin.');
    }
    if (localEntries.map((entry) => entry.id).toSet().length !=
        localEntries.length) {
      throw ArgumentError('Local arrangements contain duplicate IDs.');
    }
    validateScheduleOccurrenceOverrides(
      this.occurrenceOverrides,
      baseline: this.localEntries,
    );
  }

  final TeachingCalendar? calendarOverride;
  final List<PeriodTime> periodTimes;
  final List<PeriodTimeSection> periodSections;
  final bool useCustomPeriodTimes;

  /// Campus used for imported arrangements that do not declare one.
  final String? periodCampus;
  final List<ScheduleEntry> localEntries;
  final Set<String> hiddenEntryIds;
  final List<ScheduleOccurrenceOverride> occurrenceOverrides;
  final bool preferAgenda;

  /// Combines imported data and legacy settings before occurrence adjustments.
  ScheduleSnapshot baseSnapshot(ScheduleSnapshot snapshot) => snapshot.copyWith(
    entries: [
      ...snapshot.entries.where((entry) => !hiddenEntryIds.contains(entry.id)),
      ...localEntries,
    ],
    calendar: calendarOverride ?? snapshot.calendar,
    periodTimes: useCustomPeriodTimes ? periodTimes : snapshot.periodTimes,
    periodCampus: _effectivePeriodCampus(
      useCustomPeriodTimes ? periodTimes : snapshot.periodTimes,
      periodCampus,
    ),
  );

  /// Projects saved settings without changing the school's original evidence.
  ScheduleSnapshot applyTo(ScheduleSnapshot snapshot) =>
      applyScheduleOccurrenceOverrides(
        baseline: baseSnapshot(snapshot),
        overrides: occurrenceOverrides,
      );

  /// Keeps adjustments linked when an import changes descriptive metadata.
  /// Changed teaching times/places are retained separately for user review.
  ScheduleSettings reconcileImport(
    ScheduleSnapshot previous,
    ScheduleSnapshot next,
  ) {
    final previousById = {
      for (final entry in previous.entries) entry.id: entry,
    };
    final nextById = {for (final entry in next.entries) entry.id: entry};
    final nextIds = nextById.keys.toSet();
    final replacements = <String, String>{};
    for (final entry in previous.entries) {
      if (nextIds.contains(entry.id)) continue;
      final matches = next.entries.where(entry.hasSameArrangement).toList();
      if (matches.length != 1 || previousById.containsKey(matches.single.id)) {
        continue;
      }
      final matched = matches.single;
      if (previous.entries.where(matched.hasSameArrangement).length == 1) {
        replacements[entry.id] = matched.id;
      }
    }
    return copyWith(
      hiddenEntryIds: hiddenEntryIds.map((id) => replacements[id] ?? id),
      localEntries: localEntries.map((entry) {
        final original = entry.metadata['replacesImportedId'];
        if (original == null) return entry;
        final updated = replacements[original] ?? original;
        return entry.withMetadata({
          ...entry.metadata,
          'replacesImportedId': updated,
          'schoolArrangementChanged': (!nextIds.contains(updated)).toString(),
        });
      }).toList(),
      occurrenceOverrides: occurrenceOverrides.map((value) {
        final nextId = replacements[value.source.id];
        final previousSource = previousById[value.source.id];
        if (value.source.origin != ScheduleEntryOrigin.imported ||
            nextId == null ||
            previousSource == null ||
            !value.source.hasSameArrangement(previousSource)) {
          return value;
        }
        return ScheduleOccurrenceOverride(
          source: nextById[nextId]!,
          sourceWeek: value.sourceWeek,
          parts: value.parts,
        );
      }).toList(),
    );
  }

  ScheduleSettings copyWith({
    TeachingCalendar? calendarOverride,
    bool clearCalendarOverride = false,
    List<PeriodTime>? periodTimes,
    List<PeriodTimeSection>? periodSections,
    bool? useCustomPeriodTimes,
    String? periodCampus,
    bool clearPeriodCampus = false,
    List<ScheduleEntry>? localEntries,
    Iterable<String>? hiddenEntryIds,
    List<ScheduleOccurrenceOverride>? occurrenceOverrides,
    bool? preferAgenda,
  }) => ScheduleSettings(
    calendarOverride: clearCalendarOverride
        ? null
        : calendarOverride ?? this.calendarOverride,
    periodTimes: periodTimes ?? this.periodTimes,
    periodSections: periodSections ?? this.periodSections,
    useCustomPeriodTimes: useCustomPeriodTimes ?? this.useCustomPeriodTimes,
    periodCampus: clearPeriodCampus ? null : periodCampus ?? this.periodCampus,
    localEntries: localEntries ?? this.localEntries,
    hiddenEntryIds: hiddenEntryIds ?? this.hiddenEntryIds,
    occurrenceOverrides: occurrenceOverrides ?? this.occurrenceOverrides,
    preferAgenda: preferAgenda ?? this.preferAgenda,
  );
}

String? _effectivePeriodCampus(List<PeriodTime> periods, String? selected) {
  final campuses = periods
      .map((period) => normalizePeriodCampus(period.campus))
      .whereType<String>()
      .toSet();
  final normalized = normalizePeriodCampus(selected);
  if (normalized != null && campuses.contains(normalized)) return normalized;
  return campuses.length == 1 ? campuses.single : null;
}
