import 'package:flutter/material.dart';
import 'package:zf_core/zf_core.dart';

import '../../../core/adaptive_sheet.dart';
import '../view_models/course_occurrences.dart';
import '../view_models/schedule_labels.dart';
import '../view_models/timetable_view_model.dart';
import 'course_detail_sheet.dart';
import 'schedule_adjustment_editor.dart';
import 'schedule_adjustment_widgets.dart';

Future<void> showScheduleCourseOccurrences(
  BuildContext context,
  TimetableViewModel viewModel, {
  required ScheduleEntry entry,
  required int week,
}) async {
  final editing = viewModel.adjustmentContext;
  if (editing == null) return;
  await showAdaptiveSheet<void>(
    context: context,
    maxWidth: 760,
    builder: (context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * .85,
      width: 760,
      child: _CourseOccurrencesSheet(
        viewModel: viewModel,
        initial: editing,
        entry: entry,
        week: week,
      ),
    ),
  );
}

class _CourseOccurrencesSheet extends StatefulWidget {
  const _CourseOccurrencesSheet({
    required this.viewModel,
    required this.initial,
    required this.entry,
    required this.week,
  });

  final TimetableViewModel viewModel;
  final ScheduleAdjustmentContext initial;
  final ScheduleEntry entry;
  final int week;

  @override
  State<_CourseOccurrencesSheet> createState() =>
      _CourseOccurrencesSheetState();
}

class _CourseOccurrencesSheetState extends State<_CourseOccurrencesSheet> {
  final _centerKey = GlobalKey();
  late int _focusWeek = widget.week;
  bool _saving = false;

  Future<void> _change(CourseOccurrenceRow row, ScheduleChangeKind kind) async {
    await showScheduleAdjustmentEditor(
      context,
      widget.viewModel,
      entry: row.isSource ? null : row.entry,
      week: row.week,
      weekday: row.entry.weekday,
      sourceOverride: row.isSource ? row.override : null,
      initialKind: kind,
    );
  }

  Future<void> _restore(
    ScheduleAdjustmentContext editing,
    ScheduleOccurrenceOverride record,
  ) async {
    setState(() => _saving = true);
    try {
      await restoreScheduleOccurrence(
        context,
        widget.viewModel,
        editing: editing,
        record: record,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.viewModel,
    builder: (context, _) {
      final current = widget.viewModel.adjustmentContext;
      final sameTarget = current?.target == widget.initial.target;
      final editing = sameTarget ? current! : widget.initial;
      final occurrences = CourseOccurrences.fromContext(editing, widget.entry);
      final weeks = {...occurrences.byWeek.keys, _focusWeek}.toList()..sort();
      final center = weeks.indexOf(_focusWeek);
      final theme = Theme.of(context);
      return PopScope(
        canPop: !_saving,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('课程逐周明细', style: theme.textTheme.titleLarge),
                  ),
                  IconButton(
                    tooltip: '关闭逐周明细',
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.entry.name,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ),
            Row(
              children: [
                IconButton(
                  tooltip: '前一个有安排的教学周',
                  onPressed: center == 0
                      ? null
                      : () => setState(() => _focusWeek = weeks[center - 1]),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    '第 $_focusWeek 周 · 可上下滚动查看',
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  tooltip: '后一个有安排的教学周',
                  onPressed: center == weeks.length - 1
                      ? null
                      : () => setState(() => _focusWeek = weeks[center + 1]),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            if (!sameTarget)
              const Padding(
                padding: EdgeInsets.all(12),
                child: ScheduleAdjustmentNotice(
                  message: '当前账号或学期已改变，请关闭后重新打开课程详情。',
                  isError: true,
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: CustomScrollView(
                key: ValueKey(('course-occurrence-weeks', _focusWeek)),
                center: _centerKey,
                slivers: [
                  SliverList.builder(
                    itemCount: center,
                    itemBuilder: (context, index) => _week(
                      editing,
                      occurrences,
                      weeks[center - index - 1],
                      enabled: sameTarget && !_saving,
                    ),
                  ),
                  SliverList.builder(
                    key: _centerKey,
                    itemCount: weeks.length - center,
                    itemBuilder: (context, index) => _week(
                      editing,
                      occurrences,
                      weeks[center + index],
                      enabled: sameTarget && !_saving,
                    ),
                  ),
                  if (occurrences.unassigned.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          '另有 ${occurrences.unassigned.length} 条安排未明确教学周，'
                          '请在课程编辑中填写周次后查看逐周明细。',
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: MediaQuery.paddingOf(context).bottom + 20,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _week(
    ScheduleAdjustmentContext editing,
    CourseOccurrences occurrences,
    int week, {
    required bool enabled,
  }) {
    final dates = editing.effective.calendar.weekDates(week);
    final rows = occurrences.byWeek[week] ?? const [];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              '第 $week 周'
              '${dates == null ? '' : ' · ${dates.start.month}/${dates.start.day}–${dates.end.month}/${dates.end.day}'}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty) const Text('本周没有这门课程的安排'),
          for (final row in rows) _row(editing, row, enabled: enabled),
        ],
      ),
    );
  }

  Widget _row(
    ScheduleAdjustmentContext editing,
    CourseOccurrenceRow row, {
    required bool enabled,
  }) {
    final theme = Theme.of(context);
    final record = row.override;
    final needsReview = record?.needsReview(editing.baseline.entries) ?? false;
    final label = row.isSource
        ? record!.parts.isEmpty
              ? '已停课 · 原始安排'
              : '调整前的原始安排'
        : switch (row.part?.kind) {
            ScheduleOccurrencePartKind.original => '保留的节次',
            ScheduleOccurrencePartKind.rescheduled => '已调课',
            ScheduleOccurrencePartKind.makeup => '补课',
            null =>
              row.entry.origin == ScheduleEntryOrigin.imported
                  ? '教务安排'
                  : '本地安排',
          };
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: row.isSource ? theme.colorScheme.surfaceContainerLow : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Text(
              '${scheduleAdjustmentDayText(editing.effective, row.week, row.entry.weekday)}'
              ' · ${row.entry.schedulePeriodsText}',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 4),
            Text(row.entry.schedulePlaceText),
            if (!row.isSource) ...[
              const SizedBox(height: 4),
              Text(scheduleClockRange(row.entry, editing.effective)),
              if (record != null)
                Text(
                  '来源：第 ${record.sourceWeek} 周 · '
                  '${scheduleWeekdayText(record.source.weekday)} · '
                  '${record.source.schedulePeriodsText}',
                ),
            ],
            if (row.isSource && record!.parts.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final part in record.parts)
                Text(scheduleAdjustmentPartText(editing.effective, part)),
            ],
            if (needsReview) ...[
              const SizedBox(height: 8),
              Text(
                '原始课程已变化，本地结果仍保留。请核对后恢复这项调整。',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: row.isSource
                  ? [
                      TextButton.icon(
                        onPressed: enabled && !needsReview
                            ? () => _change(row, ScheduleChangeKind.makeup)
                            : null,
                        icon: const Icon(Icons.add),
                        label: const Text('按原始安排补课'),
                      ),
                      TextButton.icon(
                        onPressed: enabled
                            ? () => _restore(editing, record!)
                            : null,
                        icon: const Icon(Icons.restore),
                        label: const Text('恢复这次安排'),
                      ),
                    ]
                  : [
                      for (final kind in ScheduleChangeKind.values)
                        TextButton(
                          onPressed: enabled && !needsReview
                              ? () => _change(row, kind)
                              : null,
                          child: Text(switch (kind) {
                            ScheduleChangeKind.reschedule => '调课',
                            ScheduleChangeKind.cancel => '停课',
                            ScheduleChangeKind.makeup => '补课',
                          }),
                        ),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}
