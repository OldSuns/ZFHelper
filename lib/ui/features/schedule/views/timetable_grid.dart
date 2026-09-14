import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:zf_core/zf_core.dart';

import '../../../core/app_theme.dart';
import 'course_detail_sheet.dart';

const _minimumGridWidth = 360.0;
const _maximumGridTextScale = 1.45;
const _periodAxisWidth = 36.0;
const _periodRowExtent = 76.0;

class TimetableGrid extends StatefulWidget {
  const TimetableGrid({
    required this.snapshot,
    required this.week,
    required this.today,
    required this.onCourseTap,
    this.scrollOffset = 0,
    this.onScroll,
    this.active = true,
    this.agenda = false,
    super.key,
  }) : assert(week > 0),
       assert(scrollOffset >= 0);

  final ScheduleSnapshot snapshot;
  final int week;
  final DateTime today;
  final ValueChanged<ScheduleEntry> onCourseTap;
  final double scrollOffset;
  final ValueChanged<double>? onScroll;
  final bool active;
  final bool agenda;

  @override
  State<TimetableGrid> createState() => _TimetableGridState();
}

class _TimetableGridState extends State<TimetableGrid> {
  late final ScrollController _scrollController;
  bool _restoringOffset = false;
  int _restoreTicket = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(
      initialScrollOffset: widget.scrollOffset,
      keepScrollOffset: false,
    )..addListener(_reportScroll);
    _scheduleOffsetRestore();
  }

  @override
  void didUpdateWidget(TimetableGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active &&
        (!oldWidget.active ||
            widget.scrollOffset != oldWidget.scrollOffset ||
            widget.agenda != oldWidget.agenda ||
            widget.snapshot != oldWidget.snapshot)) {
      _scheduleOffsetRestore();
    }
  }

  void _scheduleOffsetRestore() {
    final ticket = ++_restoreTicket;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          ticket != _restoreTicket ||
          !widget.active ||
          !_scrollController.hasClients) {
        return;
      }
      final position = _scrollController.position;
      final target = widget.scrollOffset
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if ((position.pixels - target).abs() < 0.5) return;
      _restoringOffset = true;
      _scrollController.jumpTo(target);
      _restoringOffset = false;
    });
  }

  void _reportScroll() {
    if (widget.active && !_restoringOffset && _scrollController.hasClients) {
      widget.onScroll?.call(_scrollController.offset);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final useAgenda =
          widget.agenda ||
          constraints.maxWidth < _minimumGridWidth ||
          textScale > _maximumGridTextScale;
      final dates = widget.snapshot.calendar.weekDates(widget.week);
      final placed =
          widget.snapshot.entries
              .where(
                (entry) => entry.isPlaced && entry.occursInWeek(widget.week),
              )
              .toList()
            ..sort(compareScheduleEntries);
      final pending =
          widget.snapshot.entries
              .where(
                (entry) =>
                    !entry.isPlaced &&
                    (entry.weeks.isEmpty || entry.occursInWeek(widget.week)),
              )
              .toList()
            ..sort(compareScheduleEntries);
      return Semantics(
        container: true,
        label: '第 ${widget.week} 周课表',
        child: Column(
          children: [
            if (!useAgenda) _WeekdayHeader(dates: dates, today: widget.today),
            Expanded(
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: constraints.maxWidth >= 600,
                child: CustomScrollView(
                  key: const ValueKey('timetable-vertical-scroll'),
                  controller: _scrollController,
                  primary: false,
                  physics: const ClampingScrollPhysics(),
                  slivers: [
                    if (placed.isEmpty)
                      SliverToBoxAdapter(
                        child: _EmptyWeek(
                          wholeTermEmpty: widget.snapshot.entries.isEmpty,
                          week: widget.week,
                          hasPending: pending.isNotEmpty,
                        ),
                      )
                    else if (useAgenda)
                      ..._agendaSlivers(placed, dates)
                    else
                      SliverToBoxAdapter(
                        child: _buildGrid(
                          context,
                          constraints.maxWidth,
                          placed,
                          dates,
                        ),
                      ),
                    if (pending.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: _SectionHeading('实践与待排安排（${pending.length}）'),
                      ),
                      SliverList.builder(
                        itemCount: pending.length,
                        itemBuilder: (context, index) => _AgendaCourseTile(
                          entry: pending[index],
                          pending: true,
                          onTap: () => widget.onCourseTap(pending[index]),
                        ),
                      ),
                    ],
                    const SliverToBoxAdapter(child: SizedBox(height: 20)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  List<Widget> _agendaSlivers(
    List<ScheduleEntry> entries,
    CalendarWeek? dates,
  ) {
    final slivers = <Widget>[];
    for (var day = DateTime.monday; day <= DateTime.sunday; day++) {
      final lessons = entries.where((entry) => entry.weekday == day).toList();
      final date = dates?.days[day - 1];
      final isToday = date != null && _sameDate(date, widget.today);
      if (lessons.isEmpty && !isToday) continue;
      slivers.add(
        SliverToBoxAdapter(
          child: _SectionHeading(
            [
              scheduleWeekdayText(day),
              if (date != null) '${date.month}月${date.day}日',
              if (isToday) '今天',
            ].join(' · '),
          ),
        ),
      );
      if (lessons.isEmpty) {
        slivers.add(
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text('今天没有排定课程'),
            ),
          ),
        );
        continue;
      }
      slivers.add(
        SliverList.builder(
          itemCount: lessons.length,
          itemBuilder: (context, index) {
            final entry = lessons[index];
            return _AgendaCourseTile(
              entry: entry,
              onTap: () => widget.onCourseTap(entry),
              current: _isCurrentLesson(entry),
              conflict: lessons.any(
                (other) =>
                    other.id != entry.id &&
                    entry.conflictsWith(other, week: widget.week),
              ),
            );
          },
        ),
      );
    }
    return slivers;
  }

  Widget _buildGrid(
    BuildContext context,
    double width,
    List<ScheduleEntry> placed,
    CalendarWeek? dates,
  ) {
    final colors = Theme.of(context).colorScheme;
    final dayWidth = (width - _periodAxisWidth) / DateTime.daysPerWeek;
    final todayIndex =
        dates?.days.indexWhere((day) => _sameDate(day, widget.today)) ?? -1;
    final maxPeriod = widget.snapshot.maxPeriod;
    final groups = _courseGroups(placed);
    final currentPeriod = todayIndex < 0 ? null : _currentPeriod();
    return RepaintBoundary(
      child: SizedBox(
        height: maxPeriod * _periodRowExtent,
        width: width,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _GridPainter(
                  periods: maxPeriod,
                  todayIndex: todayIndex,
                  lineColor: colors.outlineVariant,
                  todayColor: colors.primary.withValues(alpha: 0.045),
                ),
              ),
            ),
            for (var number = 1; number <= maxPeriod; number++)
              Positioned(
                left: 0,
                top: (number - 1) * _periodRowExtent,
                width: _periodAxisWidth,
                height: _periodRowExtent,
                child: _PeriodLabel(number: number, snapshot: widget.snapshot),
              ),
            for (final group in groups)
              Positioned(
                left: _periodAxisWidth + (group.weekday - 1) * dayWidth,
                top: (group.start - 1) * _periodRowExtent,
                width: dayWidth,
                height: (group.end - group.start + 1) * _periodRowExtent,
                child: group.entries.length == 1
                    ? _GridCourseCard(
                        key: ValueKey(
                          'schedule-course-${group.entries.single.id}',
                        ),
                        entry: group.entries.single,
                        current: _isCurrentLesson(group.entries.single),
                        onTap: () => widget.onCourseTap(group.entries.single),
                      )
                    : _ConflictCard(
                        entries: group.entries,
                        onTap: () => _showConflicts(group.entries),
                      ),
              ),
            if (currentPeriod != null)
              Positioned(
                left: _periodAxisWidth + todayIndex * dayWidth,
                top: _timePosition(currentPeriod),
                width: dayWidth,
                height: 6,
                child: Semantics(
                  label:
                      '当前时间 ${scheduleClockText(widget.today.hour * 60 + widget.today.minute)}',
                  child: IgnorePointer(
                    child: Row(
                      key: const ValueKey('schedule-current-time'),
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const SizedBox.square(dimension: 6),
                        ),
                        Expanded(
                          child: Container(height: 2, color: colors.primary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _isCurrentLesson(ScheduleEntry entry) {
    final dates = widget.snapshot.calendar.weekDates(widget.week);
    if (dates == null ||
        !dates.contains(widget.today) ||
        entry.weekday != widget.today.weekday) {
      return false;
    }
    final minutes = widget.today.hour * 60 + widget.today.minute;
    for (
      var number = entry.startPeriod!;
      number <= entry.endPeriod!;
      number++
    ) {
      final time = schedulePeriodTime(
        widget.snapshot,
        number,
        campus: entry.campus,
      );
      if (time != null &&
          minutes >= time.startMinutes &&
          minutes < time.endMinutes) {
        return true;
      }
    }
    return false;
  }

  PeriodTime? _currentPeriod() {
    final minutes = widget.today.hour * 60 + widget.today.minute;
    final matching = <PeriodTime>[];
    for (var number = 1; number <= widget.snapshot.maxPeriod; number++) {
      final time = schedulePeriodTime(widget.snapshot, number);
      if (time != null &&
          minutes >= time.startMinutes &&
          minutes < time.endMinutes) {
        matching.add(time);
      }
    }
    return matching.length == 1 ? matching.single : null;
  }

  double _timePosition(PeriodTime period) {
    final minutes = widget.today.hour * 60 + widget.today.minute;
    final progress =
        (minutes - period.startMinutes) /
        (period.endMinutes - period.startMinutes);
    return (period.number - 1 + progress) * _periodRowExtent;
  }

  Future<void> _showConflicts(List<ScheduleEntry> entries) async {
    final size = MediaQuery.sizeOf(context);
    Widget picker(BuildContext context) => ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 640, maxHeight: size.height * 0.8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '冲突课程（${entries.length}门）',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: '关闭冲突课程',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.only(
                bottom: 16 + MediaQuery.paddingOf(context).bottom,
              ),
              itemCount: entries.length,
              itemBuilder: (context, index) => _AgendaCourseTile(
                entry: entries[index],
                onTap: () => Navigator.of(context).pop(entries[index]),
              ),
            ),
          ),
        ],
      ),
    );
    final selected = size.width >= 600
        ? await showDialog<ScheduleEntry>(
            context: context,
            builder: (context) => Dialog(child: picker(context)),
          )
        : await showModalBottomSheet<ScheduleEntry>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            showDragHandle: true,
            builder: picker,
          );
    if (selected != null && mounted) widget.onCourseTap(selected);
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader({required this.dates, required this.today});

  final CalendarWeek? dates;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _periodAxisWidth,
            child: Text(
              '节次',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(fontSize: 12),
            ),
          ),
          for (var day = 1; day <= DateTime.daysPerWeek; day++)
            Expanded(
              child: _DayLabel(
                weekday: day,
                date: dates?.days[day - 1],
                today: today,
              ),
            ),
        ],
      ),
    );
  }
}

class _DayLabel extends StatelessWidget {
  const _DayLabel({
    required this.weekday,
    required this.date,
    required this.today,
  });

  final int weekday;
  final DateTime? date;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = date != null && _sameDate(date!, today);
    return Semantics(
      label:
          '${scheduleWeekdayText(weekday)}${date == null ? '' : '，${date!.month}月${date!.day}日'}${current ? '，今天' : ''}',
      header: true,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                current ? '今天' : scheduleWeekdayText(weekday),
                style: theme.textTheme.labelMedium?.copyWith(
                  fontSize: 12,
                  fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (date != null) ...[
                const SizedBox(height: 2),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: current
                        ? theme.colorScheme.primaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 2,
                    ),
                    child: Text(
                      '${date!.month}/${date!.day}',
                      key: ValueKey('schedule-date-$weekday'),
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontSize: 12,
                        fontWeight: current ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PeriodLabel extends StatelessWidget {
  const _PeriodLabel({required this.number, required this.snapshot});

  final int number;
  final ScheduleSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final time = schedulePeriodTime(snapshot, number);
    final hasOtherTimes = snapshot.periodTimes.any(
      (period) => period.number == number,
    );
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.labelSmall?.copyWith(
      fontSize: 12,
      height: 1.2,
    );
    return Semantics(
      label:
          '第 $number 节${time == null ? '' : '，${scheduleClockText(time.startMinutes)}至${scheduleClockText(time.endMinutes)}'}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$number', style: theme.textTheme.labelLarge),
              if (time != null) ...[
                const SizedBox(height: 3),
                Text(
                  scheduleClockText(time.startMinutes),
                  style: textStyle,
                  maxLines: 1,
                ),
                Text(
                  scheduleClockText(time.endMinutes),
                  style: textStyle,
                  maxLines: 1,
                ),
              ] else if (hasOtherTimes)
                Text('多套\n作息', style: textStyle, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridCourseCard extends StatelessWidget {
  const _GridCourseCard({
    required this.entry,
    required this.onTap,
    required this.current,
    super.key,
  });

  final ScheduleEntry entry;
  final VoidCallback onTap;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppTheme.courseAccent(theme.brightness, entry.groupKey);
    final description = [
      entry.name,
      scheduleWeekdayText(entry.weekday),
      entry.schedulePeriodsText,
      entry.schedulePlaceText,
      if (entry.teacher != null) '教师：${entry.teacher}',
      if (current) '正在上课',
    ].join('，');
    return Semantics(
      button: true,
      label: description,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Tooltip(
          message: description,
          child: _GridTileSurface(
            color: accent,
            emphasized: current,
            onTap: onTap,
            child: _CourseCardText(entry: entry, current: current),
          ),
        ),
      ),
    );
  }
}

class _CourseCardText extends StatelessWidget {
  const _CourseCardText({required this.entry, required this.current});

  final ScheduleEntry entry;
  final bool current;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final fontSize = constraints.maxWidth >= 100 ? 14.0 : 12.0;
      final style = Theme.of(context).textTheme.bodySmall?.copyWith(
        fontSize: fontSize,
        height: 1.2,
        color: Theme.of(context).colorScheme.onSurface,
      );
      final lineHeight = MediaQuery.textScalerOf(context).scale(fontSize) * 1.2;
      final currentHeight = current ? lineHeight + 4 : 0;
      final lines = math.max(
        1,
        ((constraints.maxHeight - currentHeight - 4) / lineHeight).floor(),
      );
      final titleLines = math.min(
        lines,
        lines >= 6
            ? 3
            : lines >= 3
            ? 2
            : 1,
      );
      final metadataLines = lines - titleLines;
      final showPlace = entry.location != null && metadataLines > 0;
      final showTeacher =
          entry.teacher != null && metadataLines > (showPlace ? 1 : 0);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (current) ...[
            Text(
              '上课',
              style: style?.copyWith(fontWeight: FontWeight.w700),
              maxLines: 1,
            ),
            const SizedBox(height: 4),
          ],
          Text(
            entry.name,
            maxLines: titleLines,
            overflow: TextOverflow.ellipsis,
            style: style?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (showPlace)
            Text(
              entry.location!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          if (showTeacher)
            Text(
              entry.teacher!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
        ],
      );
    },
  );
}

class _ConflictCard extends StatelessWidget {
  const _ConflictCard({required this.entries, required this.onTap});

  final List<ScheduleEntry> entries;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label:
        '${entries.length} 门课程时间冲突：${entries.map((entry) => entry.name).join('、')}，点击逐一查看',
    onTap: onTap,
    child: ExcludeSemantics(
      child: _GridTileSurface(
        color: Theme.of(context).colorScheme.error,
        emphasized: true,
        onTap: onTap,
        child: Center(
          child: Text(
            '冲突 · ${entries.length}门',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(fontSize: 12),
          ),
        ),
      ),
    ),
  );
}

class _GridTileSurface extends StatelessWidget {
  const _GridTileSurface({
    required this.color,
    required this.onTap,
    required this.child,
    this.emphasized = false,
  });

  final Color color;
  final VoidCallback onTap;
  final Widget child;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Ink(
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              color.withValues(alpha: 0.13),
              Theme.of(context).colorScheme.surface,
            ),
            border: Border.all(
              color: color.withValues(alpha: emphasized ? 0.9 : 0.45),
              width: emphasized ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: child,
        ),
      ),
    ),
  );
}

class _AgendaCourseTile extends StatelessWidget {
  const _AgendaCourseTile({
    required this.entry,
    required this.onTap,
    this.pending = false,
    this.current = false,
    this.conflict = false,
  });

  final ScheduleEntry entry;
  final VoidCallback onTap;
  final bool pending;
  final bool current;
  final bool conflict;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppTheme.courseAccent(theme.brightness, entry.groupKey);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Card(
        color: Color.alphaBlend(
          accent.withValues(alpha: 0.07),
          theme.colorScheme.surface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: conflict
                ? theme.colorScheme.error
                : theme.colorScheme.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          onTap: onTap,
          title: Text(entry.name, style: theme.textTheme.titleSmall),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              [
                if (current) '正在上课',
                if (conflict) '本周有冲突',
                if (pending) '时间待安排',
                if (!pending)
                  '${scheduleWeekdayText(entry.weekday)} · ${entry.schedulePeriodsText}',
                entry.scheduleWeeksText,
                entry.schedulePlaceText,
                if (entry.teacher != null) '教师：${entry.teacher}',
              ].join('\n'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    ),
  );
}

class _EmptyWeek extends StatelessWidget {
  const _EmptyWeek({
    required this.wholeTermEmpty,
    required this.week,
    required this.hasPending,
  });

  final bool wholeTermEmpty;
  final int week;
  final bool hasPending;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
    child: Column(
      children: [
        Icon(
          Icons.event_available_outlined,
          size: 36,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 16),
        Text(
          wholeTermEmpty ? '这个学期暂无课程' : '第 $week 周没有排定课程',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          wholeTermEmpty
              ? '已保存的课表中没有教学安排。'
              : hasPending
              ? '还有实践或待排安排，可在下方查看。'
              : '其他周的课程仍保留在本学期课表中。',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    ),
  );
}

class _CourseGroup {
  _CourseGroup(List<ScheduleEntry> entries)
    : entries = List.unmodifiable(entries);

  final List<ScheduleEntry> entries;
  int get weekday => entries.first.weekday!;
  int get start => entries.first.startPeriod!;
  int get end =>
      entries.fold(start, (end, entry) => math.max(end, entry.endPeriod!));
}

List<_CourseGroup> _courseGroups(List<ScheduleEntry> entries) {
  final groups = <_CourseGroup>[];
  for (var weekday = DateTime.monday; weekday <= DateTime.sunday; weekday++) {
    final day = entries.where((entry) => entry.weekday == weekday).toList()
      ..sort((left, right) => left.startPeriod!.compareTo(right.startPeriod!));
    var connected = <ScheduleEntry>[];
    var end = 0;
    for (final entry in day) {
      if (connected.isNotEmpty && entry.startPeriod! > end) {
        groups.add(_CourseGroup(connected));
        connected = [];
      }
      connected.add(entry);
      end = connected.length == 1
          ? entry.endPeriod!
          : math.max(end, entry.endPeriod!);
    }
    if (connected.isNotEmpty) groups.add(_CourseGroup(connected));
  }
  return groups;
}

class _GridPainter extends CustomPainter {
  const _GridPainter({
    required this.periods,
    required this.todayIndex,
    required this.lineColor,
    required this.todayColor,
  });

  final int periods;
  final int todayIndex;
  final Color lineColor;
  final Color todayColor;

  @override
  void paint(Canvas canvas, Size size) {
    final dayWidth = (size.width - _periodAxisWidth) / DateTime.daysPerWeek;
    if (todayIndex >= 0) {
      canvas.drawRect(
        Rect.fromLTWH(
          _periodAxisWidth + todayIndex * dayWidth,
          0,
          dayWidth,
          size.height,
        ),
        Paint()..color = todayColor,
      );
    }
    final line = Paint()
      ..color = lineColor
      ..strokeWidth = 0.7;
    for (var day = 0; day <= DateTime.daysPerWeek; day++) {
      final x = _periodAxisWidth + day * dayWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (var period = 0; period <= periods; period++) {
      final y = period * _periodRowExtent;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) =>
      periods != oldDelegate.periods ||
      todayIndex != oldDelegate.todayIndex ||
      lineColor != oldDelegate.lineColor ||
      todayColor != oldDelegate.todayColor;
}

bool _sameDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;
