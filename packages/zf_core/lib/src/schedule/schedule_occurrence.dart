import 'schedule_entry.dart';
import 'schedule_snapshot.dart';

enum ScheduleChangeKind { reschedule, cancel, makeup }

enum ScheduleOccurrencePartKind { original, rescheduled, makeup }

/// An explicit failure to apply a stale or invalid occurrence edit.
final class ScheduleOccurrenceException implements Exception {
  const ScheduleOccurrenceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A remaining or newly scheduled piece of a single source occurrence.
final class ScheduleOccurrencePart {
  ScheduleOccurrencePart({required this.entry, required this.kind}) {
    if (entry.origin != ScheduleEntryOrigin.local ||
        entry.weeks.length != 1 ||
        entry.rawWeeks != null ||
        entry.sourceEntryId != null) {
      throw ArgumentError(
        'Occurrence parts must be unprojected local single-week entries.',
      );
    }
  }

  final ScheduleEntry entry;
  final ScheduleOccurrencePartKind kind;

  bool hasSameValue(ScheduleOccurrencePart other) =>
      kind == other.kind && entry.hasSameValue(other.entry);
}

/// The complete replacement for one root arrangement in one teaching week.
///
/// Empty [parts] explicitly cancels the source occurrence. Derived entries
/// always belong to this root; moving a part never creates another owner.
final class ScheduleOccurrenceOverride {
  ScheduleOccurrenceOverride({
    required this.source,
    required this.sourceWeek,
    required List<ScheduleOccurrencePart> parts,
  }) : parts = List.unmodifiable(parts) {
    if (source.sourceEntryId != null || !source.occursInWeek(sourceWeek)) {
      throw ArgumentError(
        'An occurrence override needs an explicit root teaching week.',
      );
    }
    final ids = <String>{source.id};
    for (final part in this.parts) {
      final entry = part.entry;
      if (!ids.add(entry.id) ||
          entry.teachingClassId != source.teachingClassId ||
          entry.courseCode != source.courseCode ||
          entry.name != source.name ||
          entry.teacher != source.teacher ||
          entry.campus != source.campus ||
          entry.kind != source.kind) {
        throw ArgumentError(
          'An occurrence part has a duplicate or foreign identity.',
        );
      }
      if (part.kind == ScheduleOccurrencePartKind.original &&
          (entry.weeks.single != sourceWeek ||
              entry.weekday != source.weekday ||
              entry.location != source.location ||
              !_isWithinPeriods(entry, source))) {
        throw ArgumentError(
          'An original part must remain inside its source occurrence.',
        );
      }
      if (part.kind != ScheduleOccurrencePartKind.original &&
          entry.weekday == null) {
        throw ArgumentError(
          'Moved and makeup parts need an explicit target weekday.',
        );
      }
    }
  }

  final ScheduleEntry source;
  final int sourceWeek;
  final List<ScheduleOccurrencePart> parts;

  (String, int) get key => (source.id, sourceWeek);

  /// Whether the current baseline no longer confirms this source arrangement.
  bool needsReview(Iterable<ScheduleEntry> baseline) {
    final current = baseline.where((entry) => entry.id == source.id).toList();
    return current.length != 1 ||
        current.single.origin != source.origin ||
        !source.hasSameArrangement(current.single);
  }

  bool hasSameValue(ScheduleOccurrenceOverride other) =>
      sourceWeek == other.sourceWeek &&
      source.hasSameValue(other.source) &&
      parts.length == other.parts.length &&
      Iterable<int>.generate(parts.length)
          .every((index) => parts[index].hasSameValue(other.parts[index]));
}

/// The source and saved state captured when an occurrence editor is opened.
final class ScheduleOccurrenceSelection {
  ScheduleOccurrenceSelection._({
    required this.source,
    required this.sourceWeek,
    required this.expectedOverride,
    required this.entry,
    required this.startPeriod,
    required this.endPeriod,
    this.fromSource = false,
  });

  /// Captures an occurrence from the current baseline or effective projection.
  ///
  /// Weeks outside the selected occurrence and their raw display label do not
  /// change the selection; the complete current root is retained for saving.
  factory ScheduleOccurrenceSelection.capture({
    required ScheduleSnapshot baseline,
    required List<ScheduleOccurrenceOverride> overrides,
    required ScheduleEntry entry,
    required int week,
    int? startPeriod,
    int? endPeriod,
  }) {
    final effective = applyScheduleOccurrenceOverrides(
      baseline: baseline,
      overrides: overrides,
    );
    final current = effective.entries
        .where((item) => item.id == entry.id)
        .firstOrNull;
    if (current == null ||
        !current.occursInWeek(week) ||
        !entry.occursInWeek(week) ||
        !current
            .copyWith(weeks: [week], clearRawWeeks: true)
            .hasSameValue(entry.copyWith(weeks: [week], clearRawWeeks: true)) ||
        current.sourceEntryId != entry.sourceEntryId ||
        (current.sourceEntryId == null &&
            overrides.any((value) => value.key == (entry.id, week)))) {
      throw const ScheduleOccurrenceException('课程安排已更新，请重新打开课程详情。');
    }
    final owner = overrides
        .where((value) => value.parts.any((part) => part.entry.id == entry.id))
        .firstOrNull;
    if (owner?.needsReview(baseline.entries) ?? false) {
      throw const ScheduleOccurrenceException('原始课程已变化，请先核对并恢复这项调整。');
    }
    final source = owner == null
        ? baseline.entries.singleWhere((item) => item.id == entry.id)
        : baseline.entries.singleWhere((item) => item.id == owner.source.id);
    final range = _selectedPeriods(current, startPeriod, endPeriod);
    return ScheduleOccurrenceSelection._(
      source: source,
      sourceWeek: owner?.sourceWeek ?? week,
      expectedOverride: owner,
      entry: current.copyWith(weeks: [week], clearRawWeeks: true),
      startPeriod: range.$1,
      endPeriod: range.$2,
    );
  }

  /// Captures an original source for an explicitly requested makeup.
  ///
  /// Existing parts remain intact. Missing source periods are not inferred to
  /// be cancellations because a moved part may now use different period numbers.
  factory ScheduleOccurrenceSelection.captureSource({
    required ScheduleSnapshot baseline,
    required List<ScheduleOccurrenceOverride> overrides,
    required ScheduleOccurrenceOverride override,
    int? startPeriod,
    int? endPeriod,
  }) {
    validateScheduleOccurrenceOverrides(overrides, baseline: baseline.entries);
    final current = overrides
        .where((item) => item.key == override.key)
        .firstOrNull;
    if (current == null || !current.hasSameValue(override)) {
      throw const ScheduleOccurrenceException('调整记录已更新，请重新打开。');
    }
    if (current.needsReview(baseline.entries)) {
      throw const ScheduleOccurrenceException('原始课程已变化，请先核对并恢复这项调整。');
    }
    final source = baseline.entries.singleWhere(
      (item) => item.id == current.source.id,
    );
    final range = _selectedPeriods(source, startPeriod, endPeriod);
    return ScheduleOccurrenceSelection._(
      source: source,
      sourceWeek: current.sourceWeek,
      expectedOverride: current,
      entry: source.copyWith(weeks: [current.sourceWeek], clearRawWeeks: true),
      startPeriod: range.$1,
      endPeriod: range.$2,
      fromSource: true,
    );
  }

  final ScheduleEntry source;
  final int sourceWeek;
  final ScheduleOccurrenceOverride? expectedOverride;
  final ScheduleEntry entry;
  final int? startPeriod;
  final int? endPeriod;
  final bool fromSource;

  (String, int) get key => (source.id, sourceWeek);
  int get week => entry.weeks.single;
  bool get fromCancelledSource =>
      fromSource && (expectedOverride?.parts.isEmpty ?? false);
  bool get isPartial =>
      startPeriod != entry.startPeriod || endPeriod != entry.endPeriod;
}

/// A requested edit whose target is explicit and whose source was captured.
final class ScheduleOccurrenceChange {
  ScheduleOccurrenceChange({
    required this.selection,
    required this.kind,
    this.targetWeek,
    this.targetWeekday,
    this.targetStartPeriod,
    this.location,
  }) {
    if (selection.fromSource && kind != ScheduleChangeKind.makeup) {
      throw const ScheduleOccurrenceException('按原始安排选择的课程只能用于补课。');
    }
    if (kind == ScheduleChangeKind.cancel) {
      if (targetWeek != null ||
          targetWeekday != null ||
          targetStartPeriod != null ||
          location != null) {
        throw const ScheduleOccurrenceException('停课不应包含目标时间或地点。');
      }
      return;
    }
    if (targetWeek == null ||
        targetWeek! < 1 ||
        targetWeekday == null ||
        targetWeekday! < DateTime.monday ||
        targetWeekday! > DateTime.sunday) {
      throw const ScheduleOccurrenceException('请选择有效的目标周次和星期。');
    }
    if (targetStartPeriod != null &&
        (targetStartPeriod! < 1 || selection.startPeriod == null)) {
      throw const ScheduleOccurrenceException('目标节次无效；未排节次的课程请先完善原始安排。');
    }
  }

  final ScheduleOccurrenceSelection selection;
  final ScheduleChangeKind kind;
  final int? targetWeek;
  final int? targetWeekday;
  final int? targetStartPeriod;
  final String? location;
}

/// Checks persisted ownership and IDs without inferring or repairing data.
void validateScheduleOccurrenceOverrides(
  List<ScheduleOccurrenceOverride> overrides, {
  Iterable<ScheduleEntry> baseline = const [],
}) {
  final keys = <(String, int)>{};
  final roots = overrides.map((value) => value.source.id).toSet();
  final ids = <String>{...roots, ...baseline.map((entry) => entry.id)};
  for (final value in overrides) {
    if (!keys.add(value.key)) {
      throw ArgumentError('Duplicate source-week occurrence override.');
    }
    for (final part in value.parts) {
      if (!ids.add(part.entry.id)) {
        throw ArgumentError(
          'Occurrence part IDs must be globally unique and cannot be roots.',
        );
      }
    }
  }
}

/// Projects overrides while retaining changed source records for review.
ScheduleSnapshot applyScheduleOccurrenceOverrides({
  required ScheduleSnapshot baseline,
  required List<ScheduleOccurrenceOverride> overrides,
}) {
  validateScheduleOccurrenceOverrides(overrides, baseline: baseline.entries);
  final suppressed = <String, Set<int>>{};
  final warnings = <String>[...baseline.importWarnings];
  for (final value in overrides) {
    if (value.needsReview(baseline.entries)) {
      warnings.add(
        '${value.source.name} 第 ${value.sourceWeek} 周的原始安排已变化；本地调整已保留，请核对。',
      );
    } else {
      suppressed.putIfAbsent(value.source.id, () => {}).add(value.sourceWeek);
    }
  }
  return baseline.copyWith(
    entries: [
      for (final entry in baseline.entries)
        if (suppressed[entry.id] case final weeks?) ...[
          if (entry.weeks.any((week) => !weeks.contains(week)))
            entry.copyWith(
              weeks: entry.weeks.where((week) => !weeks.contains(week)),
              clearRawWeeks: true,
            ),
        ] else
          entry,
      for (final value in overrides)
        for (final part in value.parts)
          part.entry.copyWith(sourceEntryId: value.source.id),
    ],
    importWarnings: warnings,
  );
}

/// Applies a batch against one captured state and returns complete owner records.
///
/// Changes to the same owner are applied together, including whole-day edits.
/// Target conflicts remain visible; only overlapping destructive selections
/// within this batch are rejected. [maxPeriod] bounds targets when supplied.
List<ScheduleOccurrenceOverride> applyScheduleOccurrenceChanges({
  required ScheduleSnapshot baseline,
  required List<ScheduleOccurrenceOverride> overrides,
  required List<ScheduleOccurrenceChange> changes,
  int? maxPeriod,
}) {
  validateScheduleOccurrenceOverrides(overrides, baseline: baseline.entries);
  if (maxPeriod != null && maxPeriod < 1) {
    throw ArgumentError.value(
      maxPeriod,
      'maxPeriod',
      'Must be positive when supplied.',
    );
  }
  final current = {for (final value in overrides) value.key: value};
  final grouped = <(String, int), List<ScheduleOccurrenceChange>>{};
  for (final change in changes) {
    _validateSelection(
      baseline,
      current[change.selection.key],
      change.selection,
    );
    _validateTarget(change, maxPeriod);
    grouped.putIfAbsent(change.selection.key, () => []).add(change);
  }
  final ids = <String>{
    ...baseline.entries.map((entry) => entry.id),
    for (final value in overrides) ...[
      value.source.id,
      ...value.parts.map((part) => part.entry.id),
    ],
  };
  for (final group in grouped.entries) {
    current[group.key] = _applyOwnerChanges(group.value, ids);
  }
  final result = List<ScheduleOccurrenceOverride>.unmodifiable(current.values);
  validateScheduleOccurrenceOverrides(result, baseline: baseline.entries);
  return result;
}

/// Removes exactly the reviewed owner without recreating any old source entry.
List<ScheduleOccurrenceOverride> restoreScheduleOccurrenceOverride({
  required ScheduleSnapshot baseline,
  required List<ScheduleOccurrenceOverride> overrides,
  required ScheduleOccurrenceOverride expected,
}) {
  validateScheduleOccurrenceOverrides(overrides, baseline: baseline.entries);
  final current = overrides
      .where((item) => item.key == expected.key)
      .firstOrNull;
  if (current == null || !current.hasSameValue(expected)) {
    throw const ScheduleOccurrenceException('调整记录已更新，请重新打开后再恢复。');
  }
  return List.unmodifiable(overrides.where((item) => item.key != expected.key));
}

void _validateSelection(
  ScheduleSnapshot baseline,
  ScheduleOccurrenceOverride? current,
  ScheduleOccurrenceSelection selection,
) {
  final source = baseline.entries
      .where((entry) => entry.id == selection.source.id)
      .firstOrNull;
  if (source == null || !source.hasSameValue(selection.source)) {
    throw const ScheduleOccurrenceException('原始课程已更新，请重新打开课程详情。');
  }
  final expected = selection.expectedOverride;
  if ((expected == null && current != null) ||
      (expected != null &&
          (current == null || !current.hasSameValue(expected)))) {
    throw const ScheduleOccurrenceException('这次课程已有新的调整，请重新打开课程详情。');
  }
  if (current?.needsReview(baseline.entries) ?? false) {
    throw const ScheduleOccurrenceException('原始课程已变化，请先核对并恢复这项调整。');
  }
}

void _validateTarget(ScheduleOccurrenceChange change, int? maxPeriod) {
  if (change.kind == ScheduleChangeKind.cancel) return;
  final start = change.targetStartPeriod ?? change.selection.startPeriod;
  if (start == null) return;
  final end =
      start + change.selection.endPeriod! - change.selection.startPeriod!;
  if (end < start) {
    throw const ScheduleOccurrenceException('目标节次超出可保存范围。');
  }
  if (maxPeriod != null && end > maxPeriod) {
    throw ScheduleOccurrenceException('目标时间超出已设置的第 $maxPeriod 节，请先完善节次设置。');
  }
}

ScheduleOccurrenceOverride _applyOwnerChanges(
  List<ScheduleOccurrenceChange> changes,
  Set<String> ids,
) {
  final selection = changes.first.selection;
  var serial = 0;
  String newId() {
    while (true) {
      final id =
          'occurrence:${Uri.encodeComponent(selection.source.id)}:${selection.sourceWeek}:${++serial}';
      if (ids.add(id)) return id;
    }
  }

  final existing = selection.expectedOverride;
  final original =
      existing?.parts ??
      [
        ScheduleOccurrencePart(
          entry: selection.source.copyWith(
            id: newId(),
            weeks: [selection.sourceWeek],
            clearRawWeeks: true,
            origin: ScheduleEntryOrigin.local,
          ),
          kind: ScheduleOccurrencePartKind.original,
        ),
      ];
  final result = <ScheduleOccurrencePart>[];
  for (final part in original) {
    final edits = changes
        .where(
          (change) =>
              !change.selection.fromSource &&
              (existing == null || change.selection.entry.id == part.entry.id),
        )
        .toList();
    if (edits.isEmpty) {
      result.add(part);
    } else {
      result.addAll(_applyPartChanges(part, edits, newId));
    }
  }
  for (final change in changes.where((change) => change.selection.fromSource)) {
    final id = newId();
    final source = ScheduleOccurrencePart(
      entry: change.selection.entry.copyWith(
        id: id,
        origin: ScheduleEntryOrigin.local,
      ),
      kind: ScheduleOccurrencePartKind.original,
    );
    result.add(_targetPart(source, change, id));
  }
  return ScheduleOccurrenceOverride(
    source: selection.source,
    sourceWeek: selection.sourceWeek,
    parts: result,
  );
}

List<ScheduleOccurrencePart> _applyPartChanges(
  ScheduleOccurrencePart part,
  List<ScheduleOccurrenceChange> changes,
  String Function() newId,
) {
  final removed =
      changes
          .where((change) => change.kind != ScheduleChangeKind.makeup)
          .toList()
        ..sort(
          (left, right) => (left.selection.startPeriod ?? 0).compareTo(
            right.selection.startPeriod ?? 0,
          ),
        );
  for (var index = 1; index < removed.length; index++) {
    final previous = removed[index - 1].selection;
    final next = removed[index].selection;
    if (previous.endPeriod == null ||
        next.startPeriod == null ||
        previous.endPeriod! >= next.startPeriod!) {
      throw const ScheduleOccurrenceException('同一课程的调整节次重复，请重新选择。');
    }
  }
  final result = <ScheduleOccurrencePart>[];
  if (removed.isEmpty) {
    result.add(part);
  } else if (part.entry.startPeriod != null) {
    var start = part.entry.startPeriod!;
    for (final change in removed) {
      final selected = change.selection;
      if (start < selected.startPeriod!) {
        result.add(
          _retainedPart(
            part,
            start,
            selected.startPeriod! - 1,
            result.isEmpty ? part.entry.id : newId(),
          ),
        );
      }
      start = selected.endPeriod! + 1;
    }
    if (start <= part.entry.endPeriod!) {
      result.add(
        _retainedPart(
          part,
          start,
          part.entry.endPeriod!,
          result.isEmpty ? part.entry.id : newId(),
        ),
      );
    }
  }
  var reuseId = result.isEmpty;
  for (final change in changes) {
    if (change.kind == ScheduleChangeKind.cancel) continue;
    result.add(_targetPart(part, change, reuseId ? part.entry.id : newId()));
    reuseId = false;
  }
  return result;
}

ScheduleOccurrencePart _retainedPart(
  ScheduleOccurrencePart part,
  int first,
  int last,
  String id,
) => ScheduleOccurrencePart(
  entry: part.entry.copyWith(id: id, startPeriod: first, endPeriod: last),
  kind: part.kind,
);

ScheduleOccurrencePart _targetPart(
  ScheduleOccurrencePart part,
  ScheduleOccurrenceChange change,
  String id,
) {
  final selection = change.selection;
  final start = change.targetStartPeriod ?? selection.startPeriod;
  final location = change.location?.trim();
  return ScheduleOccurrencePart(
    entry: part.entry.copyWith(
      id: id,
      weeks: [change.targetWeek!],
      weekday: change.targetWeekday,
      startPeriod: start,
      endPeriod: start == null
          ? null
          : start + selection.endPeriod! - selection.startPeriod!,
      clearPeriods: start == null,
      location: location,
      clearLocation: location != null && location.isEmpty,
    ),
    kind:
        change.kind == ScheduleChangeKind.makeup ||
            part.kind == ScheduleOccurrencePartKind.makeup
        ? ScheduleOccurrencePartKind.makeup
        : ScheduleOccurrencePartKind.rescheduled,
  );
}

(int?, int?) _selectedPeriods(ScheduleEntry entry, int? first, int? last) {
  if (first == null && last == null) {
    return (entry.startPeriod, entry.endPeriod);
  }
  if (first == null ||
      last == null ||
      entry.startPeriod == null ||
      first < entry.startPeriod! ||
      last > entry.endPeriod! ||
      first > last) {
    throw const ScheduleOccurrenceException('请选择当前课程范围内的连续节次。');
  }
  return (first, last);
}

bool _isWithinPeriods(ScheduleEntry entry, ScheduleEntry source) =>
    source.startPeriod == null
    ? entry.startPeriod == null
    : entry.startPeriod != null &&
          entry.startPeriod! >= source.startPeriod! &&
          entry.endPeriod! <= source.endPeriod!;
