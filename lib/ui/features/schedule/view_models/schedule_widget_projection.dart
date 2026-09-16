import 'package:zf_core/zf_core.dart';

import '../../../../data/repositories/schedule_repository.dart';
import 'schedule_labels.dart';

/// Dates and ordering come from the same saved timetable as the agenda page.
/// Native widgets only filter these dated occurrences; they do not infer terms.
Map<String, Object?> projectScheduleWidget(ScheduleRepositoryState state) {
  final account = state.account?.account;
  final snapshot = state.effective;
  final dates = <DateTime>{};
  if (snapshot?.calendar.firstWeekMonday != null) {
    for (final entry in snapshot!.entries) {
      if (entry.weekday == null) continue;
      for (final week in entry.weeks) {
        dates.add(snapshot.calendar.weekDates(week)!.days[entry.weekday! - 1]);
      }
    }
  }
  final orderedDates = dates.toList()..sort();
  return {
    'version': 1,
    'status': account == null
        ? 'noAccount'
        : snapshot == null
        ? 'noSchedule'
        : snapshot.calendar.firstWeekMonday == null
        ? 'calendarMissing'
        : 'ready',
    'account': account == null
        ? null
        : {
            'schoolId': account.scope.schoolId,
            'accountId': account.scope.accountId,
            'schoolName': account.schoolName,
            'accountName': account.accountName,
          },
    'term': state.selectedTerm == null
        ? null
        : {'key': state.selectedTerm!.key, 'label': state.selectedTerm!.label},
    'days': [
      for (final date in orderedDates)
        _projectDay(ScheduleDay.fromSnapshot(snapshot, date)),
    ],
  };
}

Map<String, Object?> _projectDay(ScheduleDay day) => {
  'date': day.date.toIso8601String().split('T').first,
  'week': day.week,
  'byPeriod': day.usesPeriodOrder,
  'lessons': [
    for (final lesson in day.lessons)
      {
        'id': lesson.entry.id,
        'title': lesson.entry.name,
        'periodLabel': lesson.entry.schedulePeriodsText,
        'location': lesson.entry.schedulePlaceText,
        'teacher': lesson.entry.teacher,
        'startMinutes': lesson.startMinutes,
        'endMinutes': lesson.endMinutes,
        'periods': [
          for (final period in lesson.periods.whereType<PeriodTime>())
            {
              'startMinutes': period.startMinutes,
              'endMinutes': period.endMinutes,
            },
        ],
      },
  ],
};
