import 'package:flutter/material.dart';
import 'package:zf_core/zf_core.dart';

import '../view_models/period_times_view_model.dart';
import 'period_time_edit_dialog.dart';
import 'period_time_fields.dart';
import 'period_time_generator_page.dart';

class PeriodTimesEditor extends StatelessWidget {
  const PeriodTimesEditor({super.key, required this.viewModel});

  final PeriodTimesViewModel viewModel;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: viewModel,
    builder: (context, _) {
      final theme = Theme.of(context);
      final periods = viewModel.periods;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('课节作息', style: theme.textTheme.titleLarge)),
              IconButton(
                key: const ValueKey('period-undo'),
                tooltip: '撤销上次作息修改',
                onPressed: viewModel.canUndo ? viewModel.undo : null,
                icon: const Icon(Icons.undo),
              ),
            ],
          ),
          Text(
            viewModel.hasChanges
                ? '作息预览 · 保存设置后生效'
                : viewModel.useCustomTimes
                ? '当前使用本地作息'
                : '当前使用学校作息',
            key: const ValueKey('period-source'),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey(('period-campus', viewModel.campus)),
                  initialValue: viewModel.campus ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '校区作息',
                    isDense: true,
                  ),
                  items: [
                    for (final campus in viewModel.campuses)
                      DropdownMenuItem(
                        value: campus ?? '',
                        child: Text(
                          campus ?? '通用（未指定校区）',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => viewModel.selectCampus(value),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '新增校区作息',
                onPressed: () => _addCampus(context),
                icon: const Icon(Icons.add_location_alt_outlined),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                key: const ValueKey('period-quick-arrange'),
                onPressed: () => _generate(context),
                icon: const Icon(Icons.auto_fix_high_outlined),
                label: const Text('快速排布'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('period-add'),
                onPressed: () => _edit(context),
                icon: const Icon(Icons.add),
                label: const Text('添加课节'),
              ),
              TextButton.icon(
                key: const ValueKey('period-restore'),
                onPressed: viewModel.useCustomTimes
                    ? () => _restore(context)
                    : null,
                icon: const Icon(Icons.restore),
                label: const Text('恢复学校作息'),
              ),
            ],
          ),
          if (viewModel.error case final error?) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Container(
                key: const ValueKey('period-error'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  error,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (periods.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('该校区尚未设置作息，课程仍可按节次显示。'),
            )
          else ...[
            if (periods.any(
              (period) => viewModel.plan.sectionFor(period) == null,
            ))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '未划分时段的课节只单独调整；快速排布中可仅划分时段，保留现有时间。',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            for (var index = 0; index < periods.length; index++) ...[
              if (index == 0 ||
                  viewModel.plan.sectionFor(periods[index]) !=
                      viewModel.plan.sectionFor(periods[index - 1]))
                _sectionHeader(context, periods[index]),
              _periodRow(context, periods[index]),
              if (index + 1 < periods.length)
                _breakRow(context, periods[index], periods[index + 1]),
            ],
          ],
        ],
      );
    },
  );

  Widget _sectionHeader(BuildContext context, PeriodTime period) {
    final section = viewModel.plan.sectionFor(period);
    final label = section == null
        ? '未划分时段'
        : '${periodSessionLabel(section.session)} · 第 ${section.firstPeriod}'
              '${section.lastPeriod == section.firstPeriod ? '' : '–${section.lastPeriod}'} 节';
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(label, style: Theme.of(context).textTheme.titleSmall),
    );
  }

  Widget _periodRow(BuildContext context, PeriodTime period) => Card(
    child: ListTile(
      key: ValueKey('period-row-${period.number}'),
      visualDensity: VisualDensity.compact,
      leading: Semantics(
        label: '第 ${period.number} 节',
        child: SizedBox(
          width: 36,
          child: Center(
            child: Text(
              '${period.number}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
      ),
      title: Text(
        '${periodClock(period.startMinutes)} – ${periodClock(period.endMinutes)}',
      ),
      subtitle: Text('${period.endMinutes - period.startMinutes} 分钟'),
      onTap: () => _edit(context, period),
      trailing: PopupMenuButton<String>(
        tooltip: '第 ${period.number} 节操作',
        onSelected: (action) => action == 'edit'
            ? _edit(context, period)
            : _remove(context, period),
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'edit', child: Text('调整时间')),
          PopupMenuItem(value: 'remove', child: Text('删除课节时间')),
        ],
      ),
    ),
  );

  Widget _breakRow(BuildContext context, PeriodTime period, PeriodTime next) {
    final section = viewModel.plan.sectionFor(period);
    final editable =
        section != null &&
        section == viewModel.plan.sectionFor(next) &&
        next.number == period.number + 1;
    final minutes = next.startMinutes - period.endMinutes;
    final label = minutes < 0
        ? '与下一节重叠 ${-minutes} 分钟'
        : '${editable ? '课间' : '间隔'} $minutes 分钟';
    return Align(
      alignment: Alignment.centerRight,
      child: editable
          ? TextButton.icon(
              key: ValueKey('period-break-${period.number}'),
              onPressed: () => _editBreak(context, period, minutes),
              icon: const Icon(Icons.more_time_outlined, size: 16),
              label: Text(label),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),
            ),
    );
  }

  Future<void> _generate(BuildContext context) async {
    final next = await Navigator.of(context).push<PeriodTimePlan>(
      MaterialPageRoute(
        builder: (_) => PeriodTimeGeneratorPage(
          initialPlan: viewModel.plan,
          campus: viewModel.campus,
        ),
      ),
    );
    if (context.mounted && next != null) viewModel.change((_) => next);
  }

  Future<void> _edit(BuildContext context, [PeriodTime? period]) => showDialog(
    context: context,
    builder: (_) => PeriodTimeEditDialog(viewModel: viewModel, period: period),
  );

  Future<void> _editBreak(
    BuildContext context,
    PeriodTime period,
    int minutes,
  ) => showDialog(
    context: context,
    builder: (_) => PeriodValueDialog(
      title: '第 ${period.number} 节后的课间',
      label: '休息时长（分钟）',
      description: '下一节及本时段后续课节会同步移动，保留原有课长和其他课间。',
      initialValue: '$minutes',
      numeric: true,
      onApply: (value) {
        final changed = viewModel.change(
          (plan) => plan.changeBreak(
            afterNumber: period.number,
            campus: period.campus,
            minutes: int.parse(value),
          ),
        );
        return changed ? null : viewModel.error;
      },
    ),
  );

  Future<void> _addCampus(BuildContext context) => showDialog(
    context: context,
    builder: (_) => PeriodValueDialog(
      title: '新增校区作息',
      label: '校区名称',
      description: '填写课程所在的校区名称，各校区的作息独立编辑。',
      onApply: (value) {
        viewModel.selectCampus(value);
        return null;
      },
    ),
  );

  Future<void> _remove(BuildContext context, PeriodTime period) async {
    final clearsSection = viewModel.plan.removalClearsSection(
      number: period.number,
      campus: period.campus,
    );
    final confirmed = await _confirm(
      context,
      '删除第 ${period.number} 节的时间？',
      '课程本身会保留。'
          '${clearsSection ? '删除后将取消该时段划分，其他课节时间保持。' : '其他课节的节号和时间保持不变。'}'
          '保存前可以撤销。',
      '删除',
    );
    if (confirmed && context.mounted) {
      viewModel.change(
        (plan) => plan.remove(number: period.number, campus: period.campus),
      );
    }
  }

  Future<void> _restore(BuildContext context) async {
    final confirmed = await _confirm(
      context,
      '恢复学校作息？',
      '所有校区将使用最近导入的学校作息，本地时段划分会清除。保存前可以撤销。',
      '恢复',
    );
    if (confirmed && context.mounted) viewModel.restoreSchool();
  }

  Future<bool> _confirm(
    BuildContext context,
    String title,
    String message,
    String action,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
}
