import 'package:flutter/material.dart';
import 'package:zf_core/zf_core.dart';

class GradeRecordTile extends StatelessWidget {
  const GradeRecordTile({
    required this.record,
    required this.showTerm,
    required this.onTap,
    super.key,
  });

  final GradeRecord record;
  final bool showTerm;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          record.name,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          [
            '学分 ${record.credits ?? '未提供'}',
            '绩点 ${record.gradePoint ?? '未提供'}',
            if (record.courseNature != null) record.courseNature!,
          ].join(' · '),
          style: secondary,
        ),
        if (showTerm) ...[
          const SizedBox(height: 2),
          Text(record.term?.label ?? '学校未标注学期', style: secondary),
        ],
        if (record.examNature != null ||
            record.retake != null ||
            record.gradeStatus != null ||
            record.passed == false) ...[
          const SizedBox(height: 2),
          Text(
            [
              if (record.examNature != null) record.examNature!,
              if (record.retake != null) '重修：${record.retake}',
              if (record.gradeStatus != null) record.gradeStatus!,
              if (record.passed == false) '学校标记未通过',
            ].join(' · '),
            style: secondary?.copyWith(
              color: record.passed == false ? theme.colorScheme.error : null,
            ),
          ),
        ],
      ],
    );
    final score = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          record.score ?? '未提供',
          textAlign: TextAlign.end,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: record.passed == false
                ? theme.colorScheme.error
                : theme.colorScheme.primary,
          ),
        ),
        Text('学校成绩', style: secondary),
      ],
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context);
              if (constraints.maxWidth < scale.scale(260)) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [content, const SizedBox(height: 8), score],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: content),
                  const SizedBox(width: 16),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * .28,
                    ),
                    child: score,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
