import 'package:flutter/material.dart';
import 'package:zf_core/zf_core.dart';

import '../../../core/adaptive_sheet.dart';
import '../../../core/app_theme.dart';

enum _DetailAction { edit, delete }

Future<void> showScheduleCourseDetails(
  BuildContext context, {
  required ScheduleEntry entry,
  required ScheduleSnapshot snapshot,
  required int week,
  VoidCallback? onEdit,
  VoidCallback? onDelete,
}) async {
  final size = MediaQuery.sizeOf(context);
  Widget panel(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: 640, maxHeight: size.height * 0.85),
    child: _CourseDetails(
      entry: entry,
      snapshot: snapshot,
      week: week,
      canEdit: onEdit != null,
      canDelete: onDelete != null,
    ),
  );
  final action = await showAdaptiveSheet<_DetailAction>(
    context: context,
    maxWidth: 640,
    builder: panel,
  );
  if (!context.mounted) return;
  switch (action) {
    case _DetailAction.edit:
      onEdit?.call();
    case _DetailAction.delete:
      onDelete?.call();
    case null:
      break;
  }
}

class _CourseDetails extends StatelessWidget {
  const _CourseDetails({
    required this.entry,
    required this.snapshot,
    required this.week,
    required this.canEdit,
    required this.canDelete,
  });

  final ScheduleEntry entry;
  final ScheduleSnapshot snapshot;
  final int week;
  final bool canEdit;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = AppTheme.courseAccent(theme.brightness, entry.groupKey);
    final arrangements =
        snapshot.entries
            .where((candidate) => candidate.groupKey == entry.groupKey)
            .toList()
          ..sort(compareScheduleEntries);
    final conflicts =
        snapshot.entries
            .where(
              (candidate) =>
                  candidate.id != entry.id &&
                  entry.conflictsWith(candidate, week: week),
            )
            .toList()
          ..sort(compareScheduleEntries);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 24, right: 8, top: 8, bottom: 8),
          child: Row(
            children: [
              Expanded(child: Text('课程详情', style: theme.textTheme.titleMedium)),
              IconButton(
                tooltip: '关闭课程详情',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            key: const ValueKey('schedule-course-details-scroll'),
            padding: EdgeInsets.fromLTRB(
              24,
              0,
              24,
              24 + MediaQuery.paddingOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: SelectableText(
                    entry.name,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _DetailBadge(
                      label: entry.origin == ScheduleEntryOrigin.local
                          ? '本地课程'
                          : '教务导入',
                      color: accent,
                    ),
                    if (entry.kind == ScheduleEntryKind.practice)
                      _DetailBadge(label: '实践安排', color: accent),
                    if (entry.metadata['schoolArrangementChanged'] == 'true')
                      _DetailBadge(
                        label: '学校原安排已变更，请核对本地调整',
                        color: colors.error,
                      ),
                    if (!entry.isPlaced)
                      _DetailBadge(
                        label: '时间待安排',
                        color: colors.onSurfaceVariant,
                      ),
                    if (entry.weeks.isNotEmpty)
                      _DetailBadge(
                        label: entry.occursInWeek(week)
                            ? '第 $week 周有安排'
                            : '第 $week 周不授课',
                        color: colors.onSurfaceVariant,
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                _DetailField(label: '授课教师', value: entry.teacher ?? '未提供'),
                _DetailField(label: '校区', value: entry.campus ?? '未提供'),
                _DetailField(label: '上课地点', value: entry.location ?? '地点待安排'),
                if (entry.courseCode case final code?)
                  _DetailField(label: '课程代码', value: code),
                _DetailField(
                  label: '教学班',
                  value: entry.metadata['jxbmc'] ?? '未提供教学班名称',
                ),
                for (final field in _metadataLabels.entries)
                  if (entry.metadata[field.key] case final value?)
                    _DetailField(label: field.value, value: value),
                _DetailField(label: '周次', value: entry.scheduleWeeksText),
                _DetailField(
                  label: '上课时间',
                  value:
                      '${scheduleWeekdayText(entry.weekday)} · ${entry.schedulePeriodsText}',
                ),
                _DetailField(
                  label: '作息时间',
                  value: scheduleClockRange(entry, snapshot),
                ),
                if (arrangements.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _SectionTitle('全部上课安排（${arrangements.length}）'),
                  const SizedBox(height: 8),
                  for (final arrangement in arrangements)
                    _ArrangementCard(
                      entry: arrangement,
                      snapshot: snapshot,
                      selected: arrangement.id == entry.id,
                    ),
                ],
                if (conflicts.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SectionTitle('第 $week 周的冲突课程（${conflicts.length}）'),
                  const SizedBox(height: 8),
                  for (final conflict in conflicts)
                    _ArrangementCard(
                      entry: conflict,
                      snapshot: snapshot,
                      showName: true,
                    ),
                ],
                if (canEdit || canDelete) ...[
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (canEdit)
                        FilledButton.tonalIcon(
                          onPressed: () =>
                              Navigator.of(context).pop(_DetailAction.edit),
                          icon: const Icon(Icons.edit_outlined),
                          label: Text(
                            entry.origin == ScheduleEntryOrigin.local
                                ? '编辑课程'
                                : '本地调整',
                          ),
                        ),
                      if (canDelete)
                        OutlinedButton.icon(
                          onPressed: () =>
                              Navigator.of(context).pop(_DetailAction.delete),
                          icon: Icon(
                            entry.origin == ScheduleEntryOrigin.local
                                ? Icons.delete_outline_rounded
                                : Icons.visibility_off_outlined,
                          ),
                          label: Text(
                            entry.origin == ScheduleEntryOrigin.local
                                ? '删除课程'
                                : '隐藏此安排',
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

const _metadataLabels = {
  'xf': '学分',
  'kcxzmc': '课程性质',
  'kclbmc': '课程类别',
  'khfsmc': '考核方式',
  'ksfsmc': '考试方式',
  'zxs': '总学时',
  'skfsmc': '教学方式',
  'kkbmmc': '开课单位',
  'bz': '备注',
  'sjkcgs': '学校实践安排说明',
  'qtkcgs': '学校其他安排说明',
  'jxhjkcgs': '学校教学环节说明',
  'sksj': '学校上课时间说明',
  'xsskbz': '上课备注',
};

class _DetailField extends StatelessWidget {
  const _DetailField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        SelectableText(value, style: Theme.of(context).textTheme.bodyLarge),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _DetailBadge extends StatelessWidget {
  const _DetailBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Color.alphaBlend(
        color.withValues(alpha: 0.1),
        Theme.of(context).colorScheme.surface,
      ),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text(label, style: Theme.of(context).textTheme.labelLarge),
    ),
  );
}

class _ArrangementCard extends StatelessWidget {
  const _ArrangementCard({
    required this.entry,
    required this.snapshot,
    this.selected = false,
    this.showName = false,
  });

  final ScheduleEntry entry;
  final ScheduleSnapshot snapshot;
  final bool selected;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: selected
              ? Border.all(color: theme.colorScheme.primary)
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showName) ...[
                SelectableText(entry.name, style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
              ],
              if (selected) ...[
                Text('当前查看的安排', style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
              ],
              SelectableText(
                '${scheduleWeekdayText(entry.weekday)} · ${entry.schedulePeriodsText}',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 4),
              SelectableText(entry.scheduleWeeksText),
              SelectableText(entry.schedulePlaceText),
              if (entry.teacher case final teacher?)
                SelectableText('教师：$teacher'),
              const SizedBox(height: 4),
              SelectableText(scheduleClockRange(entry, snapshot)),
            ],
          ),
        ),
      ),
    );
  }
}

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

PeriodTime? schedulePeriodTime(
  ScheduleSnapshot snapshot,
  int number, {
  String? campus,
}) {
  final periods = snapshot.periodTimes
      .where((period) => period.number == number)
      .toList();
  var candidates = periods;
  if (campus?.trim().isNotEmpty ?? false) {
    final matching = periods
        .where((period) => period.campus?.trim() == campus!.trim())
        .toList();
    candidates = matching.isNotEmpty
        ? matching
        : periods
              .where((period) => period.campus?.trim().isEmpty ?? true)
              .toList();
  }
  if (candidates.isEmpty) return null;
  final first = candidates.first;
  return candidates.every(
        (period) =>
            period.startMinutes == first.startMinutes &&
            period.endMinutes == first.endMinutes,
      )
      ? first
      : null;
}

String scheduleClockRange(ScheduleEntry entry, ScheduleSnapshot snapshot) {
  if (entry.startPeriod == null) return '时间待安排';
  final periods = [
    for (var number = entry.startPeriod!; number <= entry.endPeriod!; number++)
      (
        number: number,
        time: schedulePeriodTime(snapshot, number, campus: entry.campus),
      ),
  ];
  if (periods.every((period) => period.time == null)) {
    final hasTimes = snapshot.periodTimes.any(
      (period) =>
          period.number >= entry.startPeriod! &&
          period.number <= entry.endPeriod!,
    );
    return hasTimes ? '校区作息尚未明确，当前按节次显示' : '作息时间未设置，当前按节次显示';
  }
  return periods
      .map((period) {
        final time = period.time;
        return time == null
            ? '第 ${period.number} 节：作息时间未设置'
            : '第 ${period.number} 节：${scheduleClockText(time.startMinutes)}–${scheduleClockText(time.endMinutes)}';
      })
      .join('\n');
}

int compareScheduleEntries(ScheduleEntry left, ScheduleEntry right) {
  final day = (left.weekday ?? 8).compareTo(right.weekday ?? 8);
  if (day != 0) return day;
  final period = (left.startPeriod ?? 0).compareTo(right.startPeriod ?? 0);
  if (period != 0) return period;
  return left.name.compareTo(right.name);
}
