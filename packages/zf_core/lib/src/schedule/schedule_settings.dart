import 'period_time_plan.dart';
import 'schedule_entry.dart';
import 'schedule_snapshot.dart';
import 'teaching_calendar.dart';

/// User changes stored separately from the school's latest successful import.
final class ScheduleSettings {
  ScheduleSettings({
    this.calendarOverride,
    List<PeriodTime> periodTimes = const [],
    List<PeriodTimeSection> periodSections = const [],
    bool? useCustomPeriodTimes,
    List<ScheduleEntry> localEntries = const [],
    Iterable<String> hiddenEntryIds = const [],
    this.preferAgenda = false,
  }) : periodTimes = List.unmodifiable(periodTimes),
       periodSections = List.unmodifiable(periodSections),
       useCustomPeriodTimes = useCustomPeriodTimes ?? periodTimes.isNotEmpty,
       localEntries = List.unmodifiable(localEntries),
       hiddenEntryIds = Set.unmodifiable(hiddenEntryIds) {
    validatePeriodTimeSections(this.periodTimes, this.periodSections);
    if (calendarOverride != null &&
        calendarOverride!.source != TeachingCalendarSource.user) {
      throw ArgumentError(
        'A calendar override must identify the user as source.',
      );
    }
    if (localEntries.any(
      (entry) => entry.origin != ScheduleEntryOrigin.local,
    )) {
      throw ArgumentError('Local arrangements must identify the local origin.');
    }
    if (localEntries.map((entry) => entry.id).toSet().length !=
        localEntries.length) {
      throw ArgumentError('Local arrangements contain duplicate IDs.');
    }
  }

  final TeachingCalendar? calendarOverride;
  final List<PeriodTime> periodTimes;
  final List<PeriodTimeSection> periodSections;
  final bool useCustomPeriodTimes;
  final List<ScheduleEntry> localEntries;
  final Set<String> hiddenEntryIds;
  final bool preferAgenda;

  /// Combines saved preferences with a snapshot without changing import data.
  ScheduleSnapshot applyTo(ScheduleSnapshot snapshot) => snapshot.copyWith(
    entries: [
      ...snapshot.entries.where((entry) => !hiddenEntryIds.contains(entry.id)),
      ...localEntries,
    ],
    calendar: calendarOverride ?? snapshot.calendar,
    periodTimes: useCustomPeriodTimes ? periodTimes : snapshot.periodTimes,
  );

  /// Keeps adjustments linked when an import changes descriptive metadata.
  /// Changed teaching times/places are retained separately for user review.
  ScheduleSettings reconcileImport(
    ScheduleSnapshot previous,
    ScheduleSnapshot next,
  ) {
    final nextIds = next.entries.map((entry) => entry.id).toSet();
    final replacements = <String, String>{};
    for (final entry in previous.entries) {
      if (nextIds.contains(entry.id)) continue;
      final matches = next.entries.where(entry.hasSameArrangement).toList();
      if (matches.length == 1) replacements[entry.id] = matches.single.id;
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
    );
  }

  ScheduleSettings copyWith({
    TeachingCalendar? calendarOverride,
    bool clearCalendarOverride = false,
    List<PeriodTime>? periodTimes,
    List<PeriodTimeSection>? periodSections,
    bool? useCustomPeriodTimes,
    List<ScheduleEntry>? localEntries,
    Iterable<String>? hiddenEntryIds,
    bool? preferAgenda,
  }) => ScheduleSettings(
    calendarOverride: clearCalendarOverride
        ? null
        : calendarOverride ?? this.calendarOverride,
    periodTimes: periodTimes ?? this.periodTimes,
    periodSections: periodSections ?? this.periodSections,
    useCustomPeriodTimes: useCustomPeriodTimes ?? this.useCustomPeriodTimes,
    localEntries: localEntries ?? this.localEntries,
    hiddenEntryIds: hiddenEntryIds ?? this.hiddenEntryIds,
    preferAgenda: preferAgenda ?? this.preferAgenda,
  );
}
