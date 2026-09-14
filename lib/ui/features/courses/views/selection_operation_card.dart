import 'package:flutter/material.dart';
import 'package:zf_core/zf_core.dart';

import 'course_list_tile.dart';

class SelectionOperationCard extends StatelessWidget {
  const SelectionOperationCard({
    required this.operation,
    required this.busy,
    required this.canQuery,
    required this.onStop,
    required this.onResume,
    required this.onVerify,
    required this.onOpenSettings,
    this.compact = false,
    super.key,
  });

  final SelectionOperation operation;
  final bool busy;
  final bool canQuery;
  final VoidCallback onStop;
  final VoidCallback onResume;
  final VoidCallback onVerify;
  final VoidCallback onOpenSettings;
  final bool compact;

  bool get _hasActions =>
      operation.isActive ||
      operation.status == SelectionStatus.paused ||
      operation.status == SelectionStatus.uncertain;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final horizontal =
          compact &&
          constraints.maxWidth >= MediaQuery.textScalerOf(context).scale(720);
      return Card(
        margin: compact ? const EdgeInsets.only(bottom: 8) : null,
        child: Padding(
          padding: EdgeInsets.all(compact ? 12 : 16),
          child: horizontal
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 4, child: _identity(context)),
                    const SizedBox(width: 20),
                    Expanded(flex: 5, child: _progress(context)),
                    if (_hasActions) ...[
                      const SizedBox(width: 16),
                      SizedBox(
                        width: MediaQuery.textScalerOf(context).scale(148),
                        child: _actions(),
                      ),
                    ],
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _identity(context),
                    const SizedBox(height: 8),
                    _progress(context),
                    if (_hasActions) _actions(),
                  ],
                ),
        ),
      );
    },
  );

  Widget _identity(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = operation.status;
    final attention = const {
      SelectionStatus.uncertain,
      SelectionStatus.failed,
      SelectionStatus.rejected,
    }.contains(status);
    final target = operation.target;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              status == SelectionStatus.succeeded
                  ? Icons.check_circle_outline_rounded
                  : attention
                  ? Icons.info_outline_rounded
                  : operation.isActive
                  ? Icons.autorenew_rounded
                  : Icons.pause_circle_outline_rounded,
              color: attention ? colors.error : colors.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                target.name,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(
              selectionStatusLabel(status),
              style: TextStyle(
                color: attention ? colors.error : colors.primary,
              ),
            ),
            Text(operation.mode == SelectionMode.watch ? '持续捡漏' : '立即选课'),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${target.schoolName} · ${target.accountName}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text(target.round.label, style: Theme.of(context).textTheme.bodySmall),
        if (target.teacher != null || target.time != null)
          Text(
            [target.teacher, target.time].whereType<String>().join(' · '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }

  Widget _progress(BuildContext context) {
    final status = operation.status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          liveRegion: operation.isActive || status == SelectionStatus.uncertain,
          child: Text(
            operation.message.isEmpty
                ? selectionStatusLabel(status)
                : operation.message,
          ),
        ),
        if (operation.isActive) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(
            minHeight: 2,
            semanticsLabel: selectionStatusLabel(status),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          '检查 ${operation.checks} 次 · 提交 ${operation.submissions} 次'
          ' · ${courseDateTime(operation.updatedAt, seconds: true)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (operation.mode == SelectionMode.watch && operation.isActive)
          Text(
            '每 ${operation.interval.inSeconds} 秒检查'
            ' · ${courseDateTime(operation.expiresAt)} 停止'
            '${operation.nextCheckAt == null ? '' : '\n下次检查 ${courseDateTime(operation.nextCheckAt!, seconds: true)}'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (operation.cancelRequested && operation.mayHaveSubmitted)
          const Text('已请求停止，已发出的选课请求仍需核实。'),
        if (status == SelectionStatus.uncertain)
          const Text('核实会读取学校已选记录，不会再次提交选课。'),
      ],
    );
  }

  Widget _actions() {
    final status = operation.status;
    return Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        spacing: 8,
        children: [
          if (operation.isActive || status == SelectionStatus.paused)
            TextButton(
              onPressed: busy || operation.cancelRequested ? null : onStop,
              child: Text(operation.cancelRequested ? '正在停止' : '停止'),
            ),
          if (status == SelectionStatus.paused)
            FilledButton.tonal(
              onPressed: busy
                  ? null
                  : canQuery
                  ? onResume
                  : onOpenSettings,
              child: Text(canQuery ? '继续执行' : '登录后继续'),
            ),
          if (status == SelectionStatus.uncertain)
            FilledButton.tonal(
              onPressed: busy
                  ? null
                  : canQuery
                  ? onVerify
                  : onOpenSettings,
              child: Text(canQuery ? '核实已选记录' : '登录后核实'),
            ),
        ],
      ),
    );
  }
}

String selectionStatusLabel(SelectionStatus status) => switch (status) {
  SelectionStatus.queued => '等待执行',
  SelectionStatus.checking => '正在核对课程',
  SelectionStatus.submitting => '正在提交',
  SelectionStatus.verifying => '正在核实结果',
  SelectionStatus.waiting => '正在等待余量',
  SelectionStatus.paused => '已暂停',
  SelectionStatus.succeeded => '已核实选中',
  SelectionStatus.rejected => '学校拒绝',
  SelectionStatus.uncertain => '结果待核实',
  SelectionStatus.failed => '执行失败',
  SelectionStatus.cancelled => '已停止',
  SelectionStatus.expired => '已到停止时间',
};
