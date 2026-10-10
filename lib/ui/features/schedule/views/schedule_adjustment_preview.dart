part of 'schedule_adjustment_editor.dart';

final class _AdjustmentPreview {
  _AdjustmentPreview._({
    required this.changes,
    required this.snapshot,
    required this.records,
    required this.conflicts,
  });

  factory _AdjustmentPreview.create({
    required ScheduleSnapshot baseline,
    required ScheduleSnapshot imported,
    required ScheduleSettings settings,
    required List<ScheduleOccurrenceChange> changes,
  }) {
    final overrides = applyScheduleOccurrenceChanges(
      baseline: baseline,
      overrides: settings.occurrenceOverrides,
      changes: changes,
    );
    final snapshot = settings
        .copyWith(occurrenceOverrides: overrides)
        .applyTo(imported);
    final affected = changes.map((change) => change.selection.key).toSet();
    final records = overrides
        .where((record) => affected.contains(record.key))
        .toList();
    return _AdjustmentPreview._(
      changes: List.unmodifiable(changes),
      snapshot: snapshot,
      records: List.unmodifiable(records),
      conflicts: _conflictLabels(snapshot, records),
    );
  }

  final List<ScheduleOccurrenceChange> changes;
  final ScheduleSnapshot snapshot;
  final List<ScheduleOccurrenceOverride> records;
  final List<String> conflicts;

  static List<String> _conflictLabels(
    ScheduleSnapshot snapshot,
    List<ScheduleOccurrenceOverride> records,
  ) {
    final days = <(int, int)>{};
    for (final record in records) {
      if (record.source.weekday case final weekday?) {
        days.add((record.sourceWeek, weekday));
      }
      for (final part in record.parts) {
        if (part.entry.weekday case final weekday?) {
          days.add((part.entry.weeks.single, weekday));
        }
      }
    }
    final conflicts = <String>[];
    for (final (week, weekday) in days) {
      final dates = snapshot.calendar.weekDates(week);
      final lessons = dates == null
          ? null
          : {
              for (final lesson in ScheduleDay.fromSnapshot(
                snapshot,
                dates.days[weekday - 1],
              ).lessons)
                lesson.entry.id: lesson,
            };
      final entries = snapshot.entries
          .where(
            (entry) => entry.weekday == weekday && entry.occursInWeek(week),
          )
          .toList();
      for (var first = 0; first < entries.length; first++) {
        for (var second = first + 1; second < entries.length; second++) {
          final left = entries[first];
          final right = entries[second];
          final conflict = lessons == null
              ? left.conflictsWith(right, week: week)
              : lessons[left.id]!.conflictsWith(lessons[right.id]!);
          if (!conflict) continue;
          conflicts.add(
            '${scheduleAdjustmentDayText(snapshot, week, weekday)}：'
            '${left.name}（${left.schedulePeriodsText}）与 '
            '${right.name}（${right.schedulePeriodsText}）',
          );
        }
      }
    }
    return List.unmodifiable(conflicts);
  }
}

class _AdjustmentPreviewView extends StatelessWidget {
  const _AdjustmentPreviewView({required this.preview});

  final _AdjustmentPreview preview;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('本次包含 ${preview.changes.length} 项安排，保存后的相关课程如下。'),
      const SizedBox(height: 12),
      for (final record in preview.records) ...[
        _record(context, record),
        const SizedBox(height: 12),
      ],
      if (preview.conflicts.isNotEmpty)
        ScheduleAdjustmentNotice(
          isError: true,
          message:
              '以下课程时间或节次重叠，保存后会一并保留：\n'
              '${preview.conflicts.join('\n\n')}',
        )
      else
        const Text('这些日期未发现课程冲突。作息不完整时按节次判断，未排节次的课程请另行核对。'),
    ],
  );

  Widget _record(
    BuildContext context,
    ScheduleOccurrenceOverride record,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            record.source.name,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '原安排：${scheduleAdjustmentDayText(preview.snapshot, record.sourceWeek, record.source.weekday)}'
            ' · ${record.source.schedulePeriodsText}',
          ),
          for (final change in preview.changes.where(
            (change) =>
                change.selection.key == record.key &&
                change.kind == ScheduleChangeKind.cancel,
          )) ...[
            const SizedBox(height: 8),
            Text(_cancellationLabel(change.selection)),
          ],
          const SizedBox(height: 8),
          if (record.parts.isEmpty)
            const Text('保存后：这次课程停课。可在调整记录中安排补课或恢复。')
          else
            for (final part in record.parts) ...[
              Text(scheduleAdjustmentPartText(preview.snapshot, part)),
              const SizedBox(height: 8),
            ],
        ],
      ),
    ),
  );

  String _cancellationLabel(ScheduleOccurrenceSelection selection) {
    final first = selection.startPeriod;
    final last = selection.endPeriod;
    final periods = first == null
        ? '整次安排'
        : first == last
        ? '第 $first 节'
        : '第 $first–$last 节';
    return '本次停课：${scheduleAdjustmentDayText(preview.snapshot, selection.week, selection.entry.weekday)} · $periods';
  }
}
