import 'package:flutter/material.dart';
import 'package:zf_core/zf_core.dart';

import '../../../core/adaptive_sheet.dart';

Future<void> showGradeDetails(
  BuildContext context, {
  required Listenable listenable,
  required GradeRecord? Function() resolveRecord,
}) => showAdaptiveSheet<void>(
  context: context,
  maxWidth: 640,
  builder: (context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .85,
    ),
    child: ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final record = resolveRecord();
        return GradeDetailsPane(
          key: ValueKey(record?.id),
          record: record,
          emptyMessage: '这条成绩已不在当前账号或筛选结果中，请关闭后重新选择。',
          onClose: () => Navigator.of(context).pop(),
        );
      },
    ),
  ),
);

class GradeDetailsPane extends StatefulWidget {
  const GradeDetailsPane({
    required this.record,
    this.onClose,
    this.emptyMessage = '在左侧选择一条成绩，查看学校公布的分项与课程信息。',
    super.key,
  });

  final GradeRecord? record;
  final VoidCallback? onClose;
  final String emptyMessage;

  @override
  State<GradeDetailsPane> createState() => _GradeDetailsPaneState();
}

class _GradeDetailsPaneState extends State<GradeDetailsPane> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final record = widget.record;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('成绩详情', style: theme.textTheme.titleMedium),
                ),
              ),
              if (widget.onClose != null)
                IconButton(
                  tooltip: '关闭成绩详情',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              key: const ValueKey('grade-details-scroll'),
              controller: _scroll,
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                20 + MediaQuery.paddingOf(context).bottom,
              ),
              child: record == null
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Column(
                        children: [
                          Icon(
                            Icons.article_outlined,
                            size: 32,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            widget.emptyMessage,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _content(record),
            ),
          ),
        ),
      ],
    );
  }

  Widget _content(GradeRecord record) {
    final theme = Theme.of(context);
    final fields = <(String, String?)>[
      ('学期', record.term?.label),
      ('学校成绩', record.score ?? '未提供'),
      ('学分', record.credits ?? '未提供'),
      ('学校绩点', record.gradePoint ?? '未提供'),
      ('课程代码', record.courseCode),
      ('教学班', record.teachingClassId),
      ('授课教师', record.teacher),
      ('开课学院', record.college),
      ('课程性质', record.courseNature),
      ('课程类别', record.courseCategory),
      ('考核方式', record.assessmentMethod),
      ('考试性质', record.examNature),
      ('重修信息', record.retake),
      ('成绩状态', record.gradeStatus),
      if (record.passed != null) ('学校通过状态', record.passed! ? '通过' : '未通过'),
    ].where((field) => field.$2 != null && field.$2!.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: SelectableText(
            record.name,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final field in fields)
          _DetailField(label: field.$1, value: field.$2!),
        if (record.term == null)
          const _DetailField(label: '学期', value: '学校未标注'),
        if (record.details.isNotEmpty) ...[
          const Divider(height: 24),
          Semantics(
            header: true,
            child: Text('分项与附加信息', style: theme.textTheme.titleSmall),
          ),
          const SizedBox(height: 8),
          for (final detail in record.details.entries)
            _DetailField(label: detail.key, value: detail.value),
        ],
        const SizedBox(height: 12),
        Text(
          '以上内容来自学校本次公布的成绩记录。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _DetailField extends StatelessWidget {
  const _DetailField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = Text(
      label,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    final content = SelectableText(value, style: theme.textTheme.bodyMedium);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final labelWidth = MediaQuery.textScalerOf(context).scale(96);
          if (constraints.maxWidth < labelWidth * 2.5) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [heading, const SizedBox(height: 2), content],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: labelWidth, child: heading),
              const SizedBox(width: 12),
              Expanded(child: content),
            ],
          );
        },
      ),
    );
  }
}
