import 'package:flutter/material.dart';
import 'package:zf_core/zf_core.dart';

Future<void> showGradeDetails(
  BuildContext context, {
  required GradeRecord record,
}) {
  final size = MediaQuery.sizeOf(context);
  Widget panel(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: 640, maxHeight: size.height * .85),
    child: _GradeDetails(record: record),
  );
  return size.width >= 600
      ? showDialog<void>(
          context: context,
          builder: (context) => Dialog(child: panel(context)),
        )
      : showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: true,
          builder: panel,
        );
}

class _GradeDetails extends StatelessWidget {
  const _GradeDetails({required this.record});

  final GradeRecord record;

  @override
  Widget build(BuildContext context) {
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
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
          child: Row(
            children: [
              Expanded(child: Text('成绩详情', style: theme.textTheme.titleMedium)),
              IconButton(
                tooltip: '关闭成绩详情',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            key: const ValueKey('grade-details-scroll'),
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              20 + MediaQuery.paddingOf(context).bottom,
            ),
            child: Column(
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
            ),
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
