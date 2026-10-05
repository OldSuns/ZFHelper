import 'package:zf_core/zf_core.dart';

String courseScheduleLabel(CourseSchedule schedule) {
  if (schedule.hasAmbiguousPairing) {
    return [
      '学校提供的时间与地点段数不一致，无法确定对应关系',
      for (final meeting in schedule.meetings) ...[
        if (meeting.time case final time?) '时间：$time',
        if (meeting.location case final location?) '地点：$location',
      ],
    ].join('\n');
  }
  if (schedule.meetings.isEmpty) return '时间：学校未提供\n地点：学校未提供';
  return [
    for (final meeting in schedule.meetings)
      '时间：${meeting.time ?? '学校未提供'}\n'
          '地点：${meeting.location ?? '学校未提供'}',
  ].join('\n\n');
}
