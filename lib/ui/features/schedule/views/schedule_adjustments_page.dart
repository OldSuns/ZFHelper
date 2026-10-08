import 'package:flutter/material.dart';
import 'package:zf_core/zf_core.dart';

import '../../../core/app_theme.dart';
import '../view_models/schedule_labels.dart';
import '../view_models/timetable_view_model.dart';
import 'course_occurrences_sheet.dart';
import 'schedule_adjustment_editor.dart';
import 'schedule_adjustment_widgets.dart';

class ScheduleAdjustmentsPage extends StatefulWidget {
  const ScheduleAdjustmentsPage({required this.viewModel, super.key});

  final TimetableViewModel viewModel;

  @override
  State<ScheduleAdjustmentsPage> createState() =>
      _ScheduleAdjustmentsPageState();
}

class _ScheduleAdjustmentsPageState extends State<ScheduleAdjustmentsPage> {
  bool _restoring = false;

  Future<void> _restore(
    ScheduleAdjustmentContext editing,
    ScheduleOccurrenceOverride record,
  ) async {
    if (_restoring) return;
    setState(() => _restoring = true);
    try {
      final saved = await restoreScheduleOccurrence(
        context,
        widget.viewModel,
        editing: editing,
        record: record,
      );
      if (!mounted) return;
      if (saved) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已恢复原始安排。')));
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.viewModel,
    builder: (context, _) {
      final editing = widget.viewModel.adjustmentContext;
      final records = [...?editing?.overrides]
        ..sort((left, right) {
          final week = left.sourceWeek.compareTo(right.sourceWeek);
          if (week != 0) return week;
          final day = (left.source.weekday ?? 0).compareTo(
            right.source.weekday ?? 0,
          );
          if (day != 0) return day;
          final period = (left.source.startPeriod ?? 0).compareTo(
            right.source.startPeriod ?? 0,
          );
          return period == 0
              ? left.source.name.compareTo(right.source.name)
              : period;
        });
      return PopScope(
        canPop: !_restoring,
        child: Scaffold(
          appBar: AppBar(title: const Text('调课 / 停课 / 补课')),
          body: SafeArea(
            top: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView.separated(
                  padding: const EdgeInsets.all(AppLayout.pagePadding),
                  itemCount: records.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 16),
                  itemBuilder: (context, index) => index == 0
                      ? _header(editing, records.length)
                      : _record(editing!, records[index - 1]),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _header(ScheduleAdjustmentContext? editing, int count) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (editing != null) ...[
        Text(
          editing.effective.term.label,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
      ],
      const Text('可调整一门课的部分节次，也可一起调整某一天的全部课程。每次课程的调整记录会保留在这里。'),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: editing == null || _restoring
            ? null
            : () => showScheduleAdjustmentEditor(context, widget.viewModel),
        icon: const Icon(Icons.add),
        label: const Text('新建调整'),
      ),
      if (_restoring) ...[
        const SizedBox(height: 16),
        const LinearProgressIndicator(),
      ],
      const SizedBox(height: AppLayout.sectionGap),
      Text('已保存的调整 · $count', style: Theme.of(context).textTheme.titleMedium),
      if (editing == null || count == 0) ...[
        const SizedBox(height: 12),
        Text(editing == null ? '请先选择一份已保存的课表。' : '还没有本地调整。停课后，也可从这里安排补课或恢复。'),
      ],
    ],
  );

  Widget _record(
    ScheduleAdjustmentContext editing,
    ScheduleOccurrenceOverride record,
  ) {
    final needsReview = record.needsReview(editing.baseline.entries);
    return Card(
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
              '原安排：${scheduleAdjustmentDayText(editing.effective, record.sourceWeek, record.source.weekday)}'
              ' · ${record.source.schedulePeriodsText} · ${record.source.schedulePlaceText}',
            ),
            const SizedBox(height: 12),
            if (needsReview) ...[
              const ScheduleAdjustmentNotice(
                isError: true,
                message: '原始课程已变化，本地调整仍保留。请先核对并恢复这项调整，再重新调整课程。',
              ),
              const SizedBox(height: 12),
            ],
            if (record.parts.isEmpty)
              const Text('这次课程已停课。')
            else
              for (final part in record.parts) ...[
                Text(scheduleAdjustmentPartText(editing.effective, part)),
                const SizedBox(height: 8),
              ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _restoring
                      ? null
                      : () => showScheduleCourseOccurrences(
                          context,
                          widget.viewModel,
                          entry: record.source,
                          week: record.sourceWeek,
                        ),
                  icon: const Icon(Icons.view_timeline_outlined),
                  label: const Text('逐周明细'),
                ),
                OutlinedButton.icon(
                  onPressed: _restoring || needsReview
                      ? null
                      : () => showScheduleAdjustmentEditor(
                          context,
                          widget.viewModel,
                          sourceOverride: record,
                          initialKind: ScheduleChangeKind.makeup,
                        ),
                  icon: const Icon(Icons.event_available_outlined),
                  label: const Text('按原始安排补课'),
                ),
                TextButton.icon(
                  onPressed: _restoring
                      ? null
                      : () => _restore(editing, record),
                  icon: const Icon(Icons.restore),
                  label: const Text('恢复原始安排'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
