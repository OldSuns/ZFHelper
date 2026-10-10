import 'package:flutter/material.dart';
import 'package:zf_core/zf_core.dart';

import '../view_models/schedule_labels.dart';

class TodayCourseCountdown extends StatelessWidget {
  const TodayCourseCountdown({
    required this.countdown,
    this.onCourse,
    super.key,
  });

  final ScheduleCountdown countdown;
  final ValueChanged<ScheduleLesson>? onCourse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final active = countdown.phase == ScheduleCountdownPhase.ongoing;
    final label = _phaseLabel;
    return Card(
      color: active ? colors.primaryContainer : colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Semantics(
                  header: true,
                  child: Text('今日课程', style: theme.textTheme.titleSmall),
                ),
                if (label != null)
                  Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_headline, style: theme.textTheme.titleLarge),
            for (final lesson in countdown.lessons) ...[
              const SizedBox(height: 8),
              _CountdownCourse(lesson: lesson, onCourse: onCourse),
            ],
            if (countdown.hasConflict) ...[
              const SizedBox(height: 8),
              Text(
                active && countdown.lessons.length > 1
                    ? '有 ${countdown.lessons.length} 项课程同时上课，请核对安排。'
                    : '课程安排有重叠，请核对时间和节次。',
                style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
              ),
            ],
            if (countdown.uncertainLessons.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${countdown.uncertainLessons.length} 项课程作息待完善，'
                '倒计时仅按已知时段计算。',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String? get _phaseLabel => switch (countdown.phase) {
    ScheduleCountdownPhase.ongoing => '正在上课',
    ScheduleCountdownPhase.breakTime => '课间休息',
    ScheduleCountdownPhase.upcoming => '下一节课',
    _ => null,
  };

  String get _headline {
    final time =
        '${countdown.remainingUnits} ${countdown.showSeconds ? '秒' : '分钟'}';
    return switch (countdown.phase) {
      ScheduleCountdownPhase.ongoing =>
        countdown.lessons.length > 1 ? '距最近一节下课还有 $time' : '距本节下课还有 $time',
      ScheduleCountdownPhase.breakTime => '距继续上课还有 $time',
      ScheduleCountdownPhase.upcoming => '距上课还有 $time',
      ScheduleCountdownPhase.empty => '今天没有已排定课程',
      ScheduleCountdownPhase.finished => '今日课程已结束',
      ScheduleCountdownPhase.timeUnknown => '完善作息后显示倒计时',
      ScheduleCountdownPhase.calendarUnknown => '填写校历后显示今日倒计时',
      ScheduleCountdownPhase.notToday => '倒计时仅显示今日课程',
    };
  }
}

class _CountdownCourse extends StatelessWidget {
  const _CountdownCourse({required this.lesson, required this.onCourse});

  final ScheduleLesson lesson;
  final ValueChanged<ScheduleLesson>? onCourse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${lesson.entry.name} · ${lesson.entry.schedulePeriodsText}',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(lesson.entry.schedulePlaceText, style: theme.textTheme.bodySmall),
      ],
    );
    final onTap = onCourse;
    if (onTap == null) return content;
    return TextButton(
      onPressed: () => onTap(lesson),
      style: TextButton.styleFrom(
        alignment: Alignment.centerLeft,
        foregroundColor: theme.colorScheme.onSurface,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      ),
      child: Row(
        children: [
          Expanded(child: content),
          const SizedBox(width: 8),
          const ExcludeSemantics(child: Icon(Icons.chevron_right)),
        ],
      ),
    );
  }
}
