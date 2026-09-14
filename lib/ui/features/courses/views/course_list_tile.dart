import 'package:flutter/material.dart';
import 'package:zf_core/zf_core.dart';

class CourseListTile extends StatelessWidget {
  const CourseListTile({
    required this.course,
    required this.isSelected,
    required this.onTap,
    this.isHighlighted = false,
    this.compact = false,
    super.key,
  });

  final CourseOffering course;
  final bool? isSelected;
  final VoidCallback onTap;
  final bool isHighlighted;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      selected: isHighlighted,
      child: Material(
        color: isHighlighted
            ? theme.colorScheme.primaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 4,
              vertical: compact ? 10 : 12,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final sideBySide =
                    compact &&
                    constraints.maxWidth >=
                        MediaQuery.textScalerOf(context).scale(520);
                final heading = Row(
                  children: [
                    Expanded(
                      child: Text(
                        course.name,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    if (isHighlighted) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ],
                );
                if (sideBySide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [heading, _schedule(theme, combined: true)],
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: constraints.maxWidth * .35,
                        child: _summary(theme, stacked: true),
                      ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    heading,
                    const SizedBox(height: 4),
                    _summary(theme),
                    _schedule(theme),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _summary(ThemeData theme, {bool stacked = false}) {
    final fields = [
      Text(
        isSelected == true
            ? '学校已标记选中'
            : courseCapacityLabel(course.capacity, course.selected),
        style: theme.textTheme.bodySmall?.copyWith(
          color:
              isSelected == true ||
                  (course.available != null && course.available! > 0)
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      Text(
        '学分 ${course.credit ?? '未提供'} · ${course.courseId}',
        style: theme.textTheme.bodySmall,
      ),
    ];
    return stacked
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [fields[0], const SizedBox(height: 4), fields[1]],
          )
        : Wrap(spacing: 12, runSpacing: 4, children: fields);
  }

  Widget _schedule(ThemeData theme, {bool combined = false}) {
    if (combined) {
      final description = [
        course.teacher,
        course.time,
        course.location,
      ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
      if (description.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Tooltip(
          message: description,
          child: Text(
            description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (course.teacher != null || course.time != null) ...[
          const SizedBox(height: 4),
          Text(
            [course.teacher, course.time].whereType<String>().join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (course.location != null) ...[
          const SizedBox(height: 2),
          Text(
            course.location!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

String courseCapacityLabel(int? capacity, int? selected) {
  if (capacity == null || selected == null) {
    return [
      '余量未知',
      if (capacity != null) '容量 $capacity',
      if (selected != null) '已选 $selected',
    ].join(' · ');
  }
  final available = capacity - selected;
  return available > 0
      ? '余量 $available · 已选 $selected/$capacity'
      : '暂无余量 · 已选 $selected/$capacity';
}

String courseDateTime(DateTime value, {bool seconds = false}) {
  final local = value.toLocal();
  String pad(int number) => number.toString().padLeft(2, '0');
  return '${local.month}/${local.day} ${pad(local.hour)}:${pad(local.minute)}'
      '${seconds ? ':${pad(local.second)}' : ''}';
}
