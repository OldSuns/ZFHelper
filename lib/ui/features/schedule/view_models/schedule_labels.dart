import 'package:zf_core/zf_core.dart';

extension ScheduleEntryViewText on ScheduleEntry {
  String get scheduleWeeksText {
    if (rawWeeks?.trim().isNotEmpty ?? false) return rawWeeks!;
    if (weeks.isEmpty) return '周次待安排';
    final sorted = weeks.toList()..sort();
    final ranges = <String>[];
    var first = sorted.first;
    var last = first;
    for (final week in sorted.skip(1)) {
      if (week == last + 1) {
        last = week;
        continue;
      }
      ranges.add(first == last ? '$first' : '$first–$last');
      first = last = week;
    }
    ranges.add(first == last ? '$first' : '$first–$last');
    return '第 ${ranges.join('、')} 周';
  }

  String get schedulePeriodsText => startPeriod == null
      ? '节次待安排'
      : startPeriod == endPeriod
      ? '第 $startPeriod 节'
      : '第 $startPeriod–$endPeriod 节';

  String get schedulePlaceText {
    final place = [
      if (campus?.trim().isNotEmpty ?? false) campus!,
      if (location?.trim().isNotEmpty ?? false) location!,
    ].join(' · ');
    return place.isEmpty ? '地点待安排' : place;
  }
}

String scheduleWeekdayText(int? weekday) => weekday == null
    ? '星期待安排'
    : const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][weekday - 1];

String scheduleClockText(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';
