import 'package:flutter/material.dart';
import 'package:zf_core/zf_core.dart';

import 'course_schedule_label.dart';

class CourseListTile extends StatelessWidget {
  static const _columnGap = 16.0;
  static const _titleColumnFraction = .4;
  static const _titleColumnMaxWidth = 280.0;

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
                  final titleWidth =
                      ((constraints.maxWidth - _columnGap) *
                              _titleColumnFraction)
                          .clamp(
                            0.0,
                            MediaQuery.textScalerOf(context)
                                .scale(_titleColumnMaxWidth),
                          );
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: titleWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [heading, _schedule(theme, combined: true)],
                        ),
                      ),
                      const SizedBox(width: _columnGap),
                      Expanded(child: _summary(theme)),
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

  Widget _summary(ThemeData theme) {
    final fields = [
      Tooltip(
        message: [
          if (course.sectionCount case final count?) '$count 个教学班，余量按各班剩余名额合计',
          if (course.availabilityFetchedAt case final updated?)
            '余量更新于 ${courseDateTime(updated, seconds: true)}',
        ].join('\n'),
        child: Text(
          isSelected == true
              ? '学校已标记选中'
              : courseCapacityLabel(
                  course.capacity,
                  course.selected,
                  available: course.available,
                  sectionCount: course.sectionCount,
                ),
          style: theme.textTheme.bodySmall?.copyWith(
            color:
                isSelected == true ||
                    (course.available != null && course.available! > 0)
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      Text(
        '学分 ${course.credit ?? '未提供'} · ${course.courseId}',
        style: theme.textTheme.bodySmall,
      ),
    ];
    return Wrap(spacing: 12, runSpacing: 4, children: fields);
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

class CourseSectionTile extends StatelessWidget {
  const CourseSectionTile({
    required this.section,
    required this.enabled,
    required this.selected,
    super.key,
  });

  final CourseSection section;
  final bool enabled;
  final bool selected;

  @override
  Widget build(BuildContext context) => RadioListTile<String>(
    value: section.key,
    enabled: enabled,
    selected: selected,
    title: Text(section.name),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
    subtitle: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        [
          section.teacher ?? '教师未提供',
          courseScheduleLabel(section.schedule),
          section.isSelected == true
              ? '学校已标记选中'
              : courseCapacityLabel(section.capacity, section.selected),
        ].join('\n'),
      ),
    ),
  );
}

String courseCapacityLabel(
  int? capacity,
  int? selected, {
  int? available,
  int? sectionCount,
}) {
  if (sectionCount == 0) return '暂无可选教学班';
  final remaining =
      available ??
      (capacity == null || selected == null ? null : capacity - selected);
  return [
    if (remaining == null) '余量未知',
    if (remaining != null)
      remaining > 0
          ? '${sectionCount != null && sectionCount > 1 ? '合计' : ''}余量 $remaining'
          : '暂无余量',
    if (capacity != null && selected != null)
      '已选 $selected/$capacity'
    else ...[
      if (capacity != null) '容量 $capacity',
      if (selected != null) '已选 $selected',
    ],
  ].join(' · ');
}

String courseDateTime(DateTime value, {bool seconds = false}) {
  final local = value.toLocal();
  String pad(int number) => number.toString().padLeft(2, '0');
  return '${local.month}/${local.day} ${pad(local.hour)}:${pad(local.minute)}'
      '${seconds ? ':${pad(local.second)}' : ''}';
}
