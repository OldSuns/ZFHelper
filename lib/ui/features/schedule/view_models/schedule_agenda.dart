import 'package:zf_core/zf_core.dart';

enum AgendaTimeGroup {
  allDay,
  periods,
  morning,
  afternoon,
  evening,
  unspecified,
}

/// A common timeline projection; the course and event remain separate sources.
final class ScheduleAgendaItem {
  ScheduleAgendaItem._lesson(ScheduleLesson value, {required bool byPeriod})
    : lesson = value,
      event = null,
      group = value.entry.startPeriod == null
          ? AgendaTimeGroup.unspecified
          : byPeriod
          ? AgendaTimeGroup.periods
          : _clockGroup(value.startMinutes!);
  ScheduleAgendaItem._event(ScheduleEvent value)
    : lesson = null,
      event = value,
      group = value.isAllDay
          ? AgendaTimeGroup.allDay
          : _clockGroup(value.startMinutes!);

  final ScheduleLesson? lesson;
  final ScheduleEvent? event;
  final AgendaTimeGroup group;
  String get title => lesson?.entry.name ?? event!.title;
  int? get startMinutes => lesson?.startMinutes ?? event?.startMinutes;

  static AgendaTimeGroup _clockGroup(int start) {
    if (start < 12 * 60) return AgendaTimeGroup.morning;
    if (start < 18 * 60) return AgendaTimeGroup.afternoon;
    return AgendaTimeGroup.evening;
  }
}

List<ScheduleAgendaItem> scheduleAgendaItems(
  ScheduleDay day,
  Iterable<ScheduleEvent> events,
) {
  final lessonOrder = {
    for (var index = 0; index < day.lessons.length; index++)
      day.lessons[index]: index,
  };
  int compareLessons(ScheduleAgendaItem left, ScheduleAgendaItem right) =>
      lessonOrder[left.lesson]!.compareTo(lessonOrder[right.lesson]!);

  return [
    for (final lesson in day.lessons)
      ScheduleAgendaItem._lesson(lesson, byPeriod: day.usesPeriodOrder),
    ...events.map(ScheduleAgendaItem._event),
  ]..sort((left, right) {
    final group = left.group.index.compareTo(right.group.index);
    if (group != 0) return group;
    if (left.group == AgendaTimeGroup.periods ||
        left.group == AgendaTimeGroup.unspecified) {
      return compareLessons(left, right);
    }
    final time = (left.startMinutes ?? -1).compareTo(right.startMinutes ?? -1);
    if (time != 0) return time;
    if (left.lesson != null && right.lesson != null) {
      return compareLessons(left, right);
    }
    // Keep a consistent tie order between courses and personal events.
    if (left.lesson != null) return -1;
    if (right.lesson != null) return 1;
    final title = left.title.compareTo(right.title);
    return title != 0 ? title : left.event!.id.compareTo(right.event!.id);
  });
}

String scheduleEventStatus(ScheduleEvent event, DateTime now) {
  if (event.completed) return '已完成';
  if (event.canComplete) return '未完成';
  return switch (event.phaseAt(now)) {
    ScheduleEventPhase.upcoming => '未开始',
    ScheduleEventPhase.ongoing => event.isAllDay ? '全天' : '进行中',
    ScheduleEventPhase.finished => '已结束',
  };
}
