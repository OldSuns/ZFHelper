import 'package:flutter/material.dart';
import 'package:zf_core/zf_core.dart';

import '../view_models/grades_view_model.dart';

class GradeRecordTable extends StatelessWidget {
  const GradeRecordTable({
    required this.records,
    required this.selectedId,
    required this.showTerm,
    required this.sort,
    required this.onSort,
    required this.onSelected,
    required this.controller,
    super.key,
  });

  final List<GradeRecord> records;
  final String? selectedId;
  final bool showTerm;
  final GradeSort sort;
  final ValueChanged<GradeSort> onSort;
  final ValueChanged<GradeRecord> onSelected;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _GradeColumns(
          course: _heading(context, '课程', GradeSort.name, numeric: false),
          score: _heading(context, '学校成绩', GradeSort.scoreDescending),
          credits: _heading(context, '学分', GradeSort.creditDescending),
          gradePoint: _heading(context, '学校绩点', GradeSort.gradePointDescending),
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: Scrollbar(
          controller: controller,
          thumbVisibility: true,
          child: ListView.separated(
            key: const PageStorageKey('grades-table'),
            controller: controller,
            padding: EdgeInsets.zero,
            itemCount: records.length,
            itemBuilder: (context, index) => _record(context, records[index]),
            separatorBuilder: (context, _) => const Divider(height: 1),
          ),
        ),
      ),
    ],
  );

  Widget _heading(
    BuildContext context,
    String label,
    GradeSort value, {
    bool numeric = true,
  }) {
    final selected = sort == value;
    return TextButton(
      onPressed: () => onSort(value),
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: EdgeInsets.zero,
        alignment: numeric ? Alignment.centerRight : Alignment.centerLeft,
        foregroundColor: selected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(label, maxLines: 1)),
          if (selected) ...[
            const SizedBox(width: 4),
            Icon(
              numeric
                  ? Icons.arrow_downward_rounded
                  : Icons.arrow_upward_rounded,
              size: 14,
            ),
          ],
        ],
      ),
    );
  }

  Widget _record(BuildContext context, GradeRecord record) {
    final theme = Theme.of(context);
    final selected = record.id == selectedId;
    final secondary = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final contextLabel = [
      record.courseCode,
      record.teacher,
      if (showTerm) record.term?.label ?? '学校未标注学期',
      record.examNature,
      if (record.retake != null) '重修：${record.retake}',
      record.gradeStatus,
      if (record.passed == false) '学校标记未通过',
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
    Widget number(String? value, {bool score = false}) => Tooltip(
      message: value ?? '学校未提供',
      child: Text(
        value ?? (score ? '未提供' : '—'),
        textAlign: TextAlign.end,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: score
            ? theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: record.passed == false
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              )
            : theme.textTheme.bodyMedium,
      ),
    );
    return Semantics(
      key: ValueKey(record.id),
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer
            : Colors.transparent,
        child: InkWell(
          onTap: () => onSelected(record),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: _GradeColumns(
              course: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Tooltip(
                    message: record.name,
                    child: Text(
                      record.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (contextLabel.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Tooltip(
                      message: contextLabel,
                      child: Text(
                        contextLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: secondary,
                      ),
                    ),
                  ],
                ],
              ),
              score: number(record.score, score: true),
              credits: number(record.credits),
              gradePoint: number(record.gradePoint),
            ),
          ),
        ),
      ),
    );
  }
}

class _GradeColumns extends StatelessWidget {
  const _GradeColumns({
    required this.course,
    required this.score,
    required this.credits,
    required this.gradePoint,
  });

  final Widget course;
  final Widget score;
  final Widget credits;
  final Widget gradePoint;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context);
    return Row(
      children: [
        Expanded(child: course),
        const SizedBox(width: 16),
        SizedBox(width: scale.scale(88), child: score),
        const SizedBox(width: 16),
        SizedBox(width: scale.scale(52), child: credits),
        const SizedBox(width: 16),
        SizedBox(width: scale.scale(76), child: gradePoint),
      ],
    );
  }
}
