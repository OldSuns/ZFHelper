import 'package:flutter/material.dart';
import 'package:zf_core/zf_core.dart';

import '../view_models/schedule_labels.dart';
import '../view_models/timetable_view_model.dart';
import 'schedule_picker_sheets.dart';

Future<bool> restoreScheduleOccurrence(
  BuildContext context,
  TimetableViewModel viewModel, {
  required ScheduleAdjustmentContext editing,
  required ScheduleOccurrenceOverride record,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('恢复原始安排？'),
      content: Text(
        '将移除「${record.source.name}」第 ${record.sourceWeek} 周这次课程'
        '的所有本地调课、停课和补课，之后按当前原始课表显示。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('恢复'),
        ),
      ],
    ),
  );
  if (!context.mounted || confirmed != true) return false;
  final saved = await viewModel.restoreOccurrence(
    record,
    target: editing.target,
  );
  if (!saved && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(viewModel.data.failure?.message ?? '恢复未能保存，请重试。')),
    );
  }
  return saved;
}

String scheduleAdjustmentDayText(
  ScheduleSnapshot snapshot,
  int week,
  int? weekday,
) {
  final label = '第 $week 周 · ${scheduleWeekdayText(weekday)}';
  final monday = snapshot.calendar.weekDates(week)?.start;
  if (monday == null || weekday == null) return label;
  final date = DateTime(monday.year, monday.month, monday.day + weekday - 1);
  return '$label · ${date.year}/${date.month}/${date.day}';
}

String scheduleAdjustmentPartText(
  ScheduleSnapshot snapshot,
  ScheduleOccurrencePart part,
) {
  final entry = part.entry;
  final kind = switch (part.kind) {
    ScheduleOccurrencePartKind.original => '保留',
    ScheduleOccurrencePartKind.rescheduled => '调至',
    ScheduleOccurrencePartKind.makeup => '补课',
  };
  return '$kind：'
      '${scheduleAdjustmentDayText(snapshot, entry.weeks.single, entry.weekday)}'
      ' · ${entry.schedulePeriodsText} · ${entry.schedulePlaceText}';
}

class ScheduleAdjustmentNotice extends StatelessWidget {
  const ScheduleAdjustmentNotice({
    required this.message,
    this.isError = false,
    super.key,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: isError,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isError ? colors.errorContainer : colors.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            message,
            style: TextStyle(
              color: isError ? colors.onErrorContainer : colors.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class ScheduleAdjustmentDayPicker extends StatelessWidget {
  const ScheduleAdjustmentDayPicker({
    required this.label,
    required this.snapshot,
    required this.week,
    required this.weekday,
    required this.weekCount,
    required this.currentWeek,
    required this.onWeekChanged,
    required this.onWeekdayChanged,
    this.allowUnscheduled = false,
    super.key,
  });

  final String label;
  final ScheduleSnapshot snapshot;
  final int week;
  final int? weekday;
  final int weekCount;
  final int? currentWeek;
  final ValueChanged<int> onWeekChanged;
  final ValueChanged<int?> onWeekdayChanged;
  final bool allowUnscheduled;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      ScheduleAdjustmentFieldRow(
        first: OutlinedButton.icon(
          onPressed: () async {
            final value = await showScheduleWeekPicker(
              context,
              snapshot: snapshot,
              selectedWeek: week,
              weekCount: weekCount,
              currentWeek: currentWeek,
            );
            if (context.mounted && value != null) onWeekChanged(value);
          },
          icon: const Icon(Icons.calendar_view_week_outlined),
          label: Text('第 $week 周'),
        ),
        second: DropdownButtonFormField<int>(
          key: ValueKey('$label-weekday-$weekday'),
          initialValue: weekday ?? (allowUnscheduled ? 0 : null),
          isExpanded: true,
          decoration: const InputDecoration(labelText: '星期'),
          items: [
            if (allowUnscheduled)
              const DropdownMenuItem(value: 0, child: Text('星期待安排')),
            for (var day = DateTime.monday; day <= DateTime.sunday; day++)
              DropdownMenuItem(
                value: day,
                child: Text(scheduleWeekdayText(day)),
              ),
          ],
          onChanged: (value) => onWeekdayChanged(value == 0 ? null : value),
          validator: (value) =>
              !allowUnscheduled && value == null ? '请选择目标星期' : null,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        !allowUnscheduled && weekday == null
            ? '请选择目标星期'
            : scheduleAdjustmentDayText(snapshot, week, weekday),
      ),
    ],
  );
}

class ScheduleAdjustmentFieldRow extends StatelessWidget {
  const ScheduleAdjustmentFieldRow({
    required this.first,
    required this.second,
    super.key,
  });

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final threshold = 440 * MediaQuery.textScalerOf(context).scale(1);
      if (constraints.maxWidth < threshold) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [first, const SizedBox(height: 12), second],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: first),
          const SizedBox(width: 16),
          Expanded(child: second),
        ],
      );
    },
  );
}
