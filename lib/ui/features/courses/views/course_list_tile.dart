import 'package:flutter/material.dart';
import 'package:zf_core/zf_core.dart';

class CourseListTile extends StatelessWidget {
  const CourseListTile({
    required this.course,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  final CourseOffering course;
  final bool? isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(course.name, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(
                    isSelected == true
                        ? '学校已标记选中'
                        : courseCapacityLabel(course.capacity, course.selected),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          isSelected == true ||
                              (course.available != null &&
                                  course.available! > 0)
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '学分 ${course.credit ?? '未提供'} · ${course.courseId}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
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
          ),
        ),
      ),
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
