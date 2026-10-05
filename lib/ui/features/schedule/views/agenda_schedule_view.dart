import 'package:flutter/material.dart';
import 'package:zf_core/zf_core.dart';

import '../../../core/app_theme.dart';
import '../view_models/schedule_agenda.dart';
import '../view_models/timetable_view_model.dart';
import 'schedule_day_widgets.dart';

class AgendaScheduleView extends StatefulWidget {
  const AgendaScheduleView({
    required this.model,
    required this.onCourse,
    required this.onAdd,
    required this.onEvent,
    required this.onOpenSettings,
    super.key,
  });
  final TimetableViewModel model;
  final ValueChanged<ScheduleLesson> onCourse;
  final VoidCallback onAdd;
  final ValueChanged<ScheduleEvent> onEvent;
  final VoidCallback onOpenSettings;

  @override
  State<AgendaScheduleView> createState() => _AgendaScheduleViewState();
}

class _AgendaScheduleViewState extends State<AgendaScheduleView> {
  bool _monthExpanded = false;
  TimetableViewModel get model => widget.model;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final day = model.dayOn(model.agendaDate);
      final entries = scheduleAgendaItems(day, model.eventsOn(day.date));
      final wide =
          constraints.maxWidth /
              (MediaQuery.textScalerOf(context).scale(14) / 14) >=
          AppLayout.workspaceListMinWidth;
      final datePanel = _DatePanel(
        model: model,
        expanded: wide || _monthExpanded,
        canCollapse: !wide,
        onToggle: () => setState(() => _monthExpanded = !_monthExpanded),
        onSelect: (date) {
          model.selectAgendaDate(date);
          if (!wide) setState(() => _monthExpanded = false);
        },
      );
      final content = <Widget>[
        if (!wide) datePanel,
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    scheduleDateText(day.date),
                    style: theme.textTheme.titleLarge,
                  ),
                  if (model.isToday(day.date))
                    Text(
                      '今天',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              key: const ValueKey('schedule-add-event'),
              tooltip: '新建日程',
              onPressed: model.eventTarget == null || model.data.loading
                  ? null
                  : widget.onAdd,
              icon: const Icon(Icons.add),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
          ],
        ),
        Text(
          [
            if (day.week != null &&
                (!day.beyondCalendar || day.lessons.isNotEmpty))
              '第 ${day.week} 周',
            '${day.lessons.length} 项课程',
            '${entries.length - day.lessons.length} 项个人日程',
          ].join(' · '),
          style: theme.textTheme.bodySmall,
        ),
        if (!day.calendarKnown)
          ScheduleCalendarNotice(
            model: model,
            onSettings: widget.onOpenSettings,
          ),
        if (day.beyondCalendar && day.lessons.isNotEmpty)
          const Text('已保留超出设置周数的实际课程，请在设置中核对学期周数。'),
        if (entries.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('这一天没有已排定的安排'),
            ),
          ),
        for (final group in AgendaTimeGroup.values)
          if (entries.any((item) => item.group == group)) ...[
            if (group != AgendaTimeGroup.periods)
              ScheduleSectionHeading(switch (group) {
                AgendaTimeGroup.allDay => '全天',
                AgendaTimeGroup.morning => '上午',
                AgendaTimeGroup.afternoon => '下午',
                AgendaTimeGroup.evening => '晚上',
                AgendaTimeGroup.periods => '',
                AgendaTimeGroup.unspecified => '节次待安排',
              }, count: entries.where((item) => item.group == group).length),
            for (final item in entries.where((item) => item.group == group))
              if (item.lesson case final lesson?)
                ScheduleLessonTile(
                  lesson: lesson,
                  now: model.today,
                  conflict: day.hasConflict(lesson),
                  onTap: () => widget.onCourse(lesson),
                )
              else
                ScheduleEventTile(
                  event: item.event!,
                  now: model.today,
                  saving: model.isSavingEvent(item.event!.id),
                  onTap: () => widget.onEvent(item.event!),
                  onCompleted: (value) =>
                      model.setEventCompleted(item.event!, value),
                ),
          ],
      ];
      final timeline = SchedulePane(
        key: ValueKey((model.account?.account.scope, day.date)),
        children: content,
      );
      if (!wide) return timeline;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 336, child: SchedulePane(children: [datePanel])),
          Expanded(child: timeline),
        ],
      );
    },
  );
}

class _DatePanel extends StatelessWidget {
  const _DatePanel({
    required this.model,
    required this.expanded,
    required this.canCollapse,
    required this.onToggle,
    required this.onSelect,
  });
  final TimetableViewModel model;
  final bool expanded;
  final bool canCollapse;
  final VoidCallback onToggle;
  final ValueChanged<DateTime> onSelect;

  Future<void> _pick(BuildContext context) async {
    final selected = await pickScheduleDate(context, model.agendaDate);
    if (context.mounted && selected != null) onSelect(selected);
  }

  @override
  Widget build(BuildContext context) {
    final date = model.agendaDate;
    final theme = Theme.of(context);
    final first = DateTime(date.year, date.month);
    final firstGridDate = CalendarWeek.containing(first).start;
    final week = CalendarWeek.containing(date);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: expanded ? '上个月' : '上一周日期',
                  onPressed: () => expanded
                      ? model.shiftAgendaMonth(-1)
                      : model.shiftAgendaDate(-7),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: () => _pick(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    child: Text(
                      '${date.year}年${date.month}月',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: expanded ? '下个月' : '下一周日期',
                  onPressed: () => expanded
                      ? model.shiftAgendaMonth(1)
                      : model.shiftAgendaDate(7),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            Row(
              children: [
                for (final label in const ['一', '二', '三', '四', '五', '六', '日'])
                  Expanded(
                    child: Center(
                      child: Text(label, style: theme.textTheme.bodySmall),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            GestureDetector(
              onHorizontalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (velocity.abs() < 100) return;
                final direction = velocity < 0 ? 1 : -1;
                if (expanded) {
                  model.shiftAgendaMonth(direction);
                } else {
                  model.shiftAgendaDate(direction * 7);
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var row = 0; row < (expanded ? 6 : 1); row++)
                    Row(
                      children: [
                        for (
                          var column = 0;
                          column < DateTime.daysPerWeek;
                          column++
                        )
                          Expanded(
                            child: _dayCell(
                              context,
                              expanded
                                  ? DateTime(
                                      firstGridDate.year,
                                      firstGridDate.month,
                                      firstGridDate.day + row * 7 + column,
                                    )
                                  : week.days[column],
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canCollapse)
                  TextButton.icon(
                    onPressed: onToggle,
                    icon: Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                    ),
                    label: Text(expanded ? '收起月历' : '展开月历'),
                  ),
                if (!model.isToday(date))
                  TextButton(
                    onPressed: model.returnToToday,
                    child: const Text('回到今天'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayCell(BuildContext context, DateTime date) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selected = sameScheduleDate(model.agendaDate, date);
    final today = model.isToday(date);
    final hasEntries = model.hasAgendaOn(date);
    final inMonth = date.month == model.agendaDate.month;
    return Semantics(
      selected: selected,
      button: true,
      label:
          '${scheduleDateText(date, year: true)}${today ? '，今天' : ''}${hasEntries ? '，有安排' : ''}',
      child: Tooltip(
        message: scheduleDateText(date, year: true),
        child: Material(
          color: selected ? colors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            key: ValueKey('agenda-date-${date.year}-${date.month}-${date.day}'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => onSelect(date),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
              child: ExcludeSemantics(
                child: Column(
                  children: [
                    Text(
                      '${date.day}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: selected
                            ? colors.onPrimary
                            : today
                            ? colors.primary
                            : inMonth
                            ? colors.onSurface
                            : colors.onSurfaceVariant,
                        fontWeight: today || selected
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 5,
                      width: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hasEntries
                            ? selected
                                  ? colors.onPrimary
                                  : colors.primary
                            : Colors.transparent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
