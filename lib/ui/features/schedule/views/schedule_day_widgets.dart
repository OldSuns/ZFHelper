import 'package:flutter/material.dart';
import 'package:zf_core/zf_core.dart';

import '../../../core/app_theme.dart';
import '../view_models/schedule_agenda.dart';
import '../view_models/schedule_labels.dart';
import '../view_models/timetable_view_model.dart';

extension ScheduleEventLabels on ScheduleEventCategory {
  String get label => switch (this) {
    ScheduleEventCategory.todo => '待办',
    ScheduleEventCategory.activity => '活动',
    ScheduleEventCategory.exam => '考试',
    ScheduleEventCategory.homework => '作业',
    ScheduleEventCategory.other => '其他',
  };
}

String scheduleDateText(DateTime date, {bool year = false}) =>
    '${year ? '${date.year}年' : ''}${date.month}月${date.day}日 ${scheduleWeekdayText(date.weekday)}';

String scheduleLessonPhaseText(ScheduleLessonPhase phase) => switch (phase) {
  ScheduleLessonPhase.upcoming => '未开始',
  ScheduleLessonPhase.ongoing => '正在上课',
  ScheduleLessonPhase.breakTime => '课间休息',
  ScheduleLessonPhase.finished => '已结束',
  ScheduleLessonPhase.unknown => '作息待完善',
};

Future<DateTime?> pickScheduleDate(BuildContext context, DateTime initial) =>
    showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year < 1900 ? initial.year : 1900),
      lastDate: DateTime(initial.year > 2200 ? initial.year : 2200, 12, 31),
      helpText: '选择日期',
      cancelText: '取消',
      confirmText: '确定',
    );

class SchedulePane extends StatelessWidget {
  const SchedulePane({required this.children, super.key});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView.separated(
    primary: false,
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
    itemCount: children.length,
    separatorBuilder: (_, _) => const SizedBox(height: 12),
    itemBuilder: (_, index) => children[index],
  );
}

class ScheduleSectionHeading extends StatelessWidget {
  const ScheduleSectionHeading(this.title, {this.count, super.key});
  final String title;
  final int? count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Semantics(
      header: true,
      child: Text(
        count == null ? title : '$title · $count',
        style: Theme.of(context).textTheme.titleSmall,
      ),
    ),
  );
}

class ScheduleCalendarNotice extends StatelessWidget {
  const ScheduleCalendarNotice({
    required this.model,
    required this.onSettings,
    super.key,
  });
  final TimetableViewModel model;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            model.hasSchedule ? '先填写本学期校历' : '还没有导入课表',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Text(
            model.hasSchedule
                ? '在设置中填写第一周周一，才能把课程对应到实际日期。个人日程可以正常使用。'
                : '导入课表并填写校历后，即可按日期查看课程。已有账号可先记录个人日程。',
          ),
          const SizedBox(height: 4),
          TextButton(onPressed: onSettings, child: const Text('前往设置')),
        ],
      ),
    ),
  );
}

class ScheduleLessonTile extends StatelessWidget {
  const ScheduleLessonTile({
    required this.lesson,
    required this.now,
    required this.onTap,
    this.conflict = false,
    super.key,
  });
  final ScheduleLesson lesson;
  final DateTime now;
  final VoidCallback onTap;
  final bool conflict;

  @override
  Widget build(BuildContext context) {
    final entry = lesson.entry;
    final phase = lesson.phaseAt(now);
    final active = phase == ScheduleLessonPhase.ongoing;
    final theme = Theme.of(context);
    final accent = AppTheme.courseAccent(theme.brightness, entry.groupKey);
    return _TimelineCard(
      time: lesson.startMinutes == null
          ? entry.schedulePeriodsText
          : scheduleClockText(lesson.startMinutes!),
      end: lesson.endMinutes == null
          ? null
          : scheduleClockText(lesson.endMinutes!),
      title: entry.name,
      accent: accent,
      highlighted: active,
      status: scheduleLessonPhaseText(phase),
      onTap: onTap,
      children: [
        if (lesson.startMinutes == null)
          Text(entry.schedulePeriodsText, style: theme.textTheme.labelMedium),
        _DetailLine(Icons.place_outlined, entry.schedulePlaceText),
        if (entry.teacher?.isNotEmpty ?? false)
          _DetailLine(Icons.person_outline, entry.teacher!),
        if (conflict)
          Text(
            '与其他课程时间或节次重叠',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
      ],
    );
  }
}

class ScheduleEventTile extends StatelessWidget {
  const ScheduleEventTile({
    required this.event,
    required this.now,
    required this.onTap,
    required this.onCompleted,
    this.saving = false,
    super.key,
  });
  final ScheduleEvent event;
  final DateTime now;
  final VoidCallback onTap;
  final ValueChanged<bool> onCompleted;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = scheduleEventStatus(event, now);
    return _TimelineCard(
      time: event.isAllDay ? '全天' : scheduleClockText(event.startMinutes!),
      end: event.endMinutes == null
          ? null
          : scheduleClockText(event.endMinutes!),
      title: event.title,
      accent: AppTheme.courseAccent(
        theme.brightness,
        'event:${event.category.name}',
      ),
      highlighted:
          !event.completed &&
          !event.isAllDay &&
          event.phaseAt(now) == ScheduleEventPhase.ongoing,
      status: status,
      completed: event.completed,
      onTap: onTap,
      action: event.canComplete
          ? Checkbox(
              semanticLabel: event.completed
                  ? '将${event.title}标为未完成'
                  : '完成${event.title}',
              value: event.completed,
              onChanged: saving ? null : (value) => onCompleted(value!),
            )
          : null,
      children: [
        Text(event.category.label, style: theme.textTheme.labelMedium),
        if (event.location?.isNotEmpty ?? false)
          _DetailLine(Icons.place_outlined, event.location!),
        if (event.note?.isNotEmpty ?? false)
          Text(
            event.note!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({
    required this.time,
    required this.end,
    required this.title,
    required this.accent,
    required this.highlighted,
    required this.status,
    required this.onTap,
    required this.children,
    this.completed = false,
    this.action,
  });
  final String time;
  final String? end;
  final String title;
  final Color accent;
  final bool highlighted;
  final bool completed;
  final String status;
  final VoidCallback onTap;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final largeText = MediaQuery.textScalerOf(context).scale(14) / 14 > 1.4;
    final card = Material(
      color: highlighted ? colors.primaryContainer : colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: highlighted ? accent : colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (largeText) ...[
                Text([time, ?end].join('–'), style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        decoration: completed
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                  ?action,
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    status,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: highlighted
                          ? colors.primary
                          : colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              for (final child in children) ...[
                const SizedBox(height: 4),
                child,
              ],
            ],
          ),
        ),
      ),
    );
    if (largeText) return card;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 62),
          child: Padding(
            padding: const EdgeInsets.only(top: 12, right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(time, style: theme.textTheme.labelLarge),
                if (end != null) Text(end!, style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                Icon(Icons.circle, size: 7, color: accent),
              ],
            ),
          ),
        ),
        Expanded(child: card),
      ],
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Icon(icon, size: 14),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ],
  );
}
