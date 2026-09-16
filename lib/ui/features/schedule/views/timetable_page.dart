import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:zf_core/zf_core.dart';

import '../../../../data/repositories/schedule_repository.dart';
import '../../../core/app_theme.dart';
import '../../../core/empty_state_card.dart';
import '../view_models/timetable_view_model.dart';
import 'agenda_schedule_view.dart';
import 'course_detail_sheet.dart';
import 'course_editor_page.dart';
import 'course_search_sheet.dart';
import 'schedule_picker_sheets.dart';
import 'schedule_event_editor.dart';
import 'timetable_grid.dart';

class TimetablePage extends StatefulWidget {
  const TimetablePage({
    required this.viewModel,
    required this.schoolName,
    required this.isSignedIn,
    required this.onOpenSettings,
    super.key,
  });

  final TimetableViewModel viewModel;
  final String schoolName;
  final bool isSignedIn;
  final VoidCallback onOpenSettings;

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  TimetableViewModel get model => widget.viewModel;

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _chooseWeek() async {
    final snapshot = model.schedule;
    final target = model.editTarget;
    if (snapshot == null) return;
    final week = await showScheduleWeekPicker(
      context,
      snapshot: snapshot,
      selectedWeek: model.selectedWeek,
      weekCount: model.weekCount,
      currentWeek: model.currentPosition.week,
    );
    if (!mounted || week == null || target != model.editTarget) return;
    final limit = model.schedule?.navigationWeekLimit;
    if (limit != null && week > limit) {
      _message('课表范围已更新，请重新选择教学周');
      return;
    }
    model.showTeachingWeek(week);
  }

  Future<void> _edit({
    required ScheduleEntry entry,
    required ScheduleTarget target,
    required ScheduleSnapshot snapshot,
  }) async {
    final saved = await showScheduleCourseEditor(
      context,
      model,
      entry: entry,
      target: target,
      snapshot: snapshot,
    );
    if (!mounted || !saved) return;
    _message('课程已保存到本机');
  }

  Future<void> _details(ScheduleEntry entry, {int? week}) async {
    final snapshot = model.schedule;
    final target = model.editTarget;
    if (snapshot == null || target == null) return;
    await showScheduleCourseDetails(
      context,
      entry: entry,
      snapshot: snapshot,
      week: week ?? model.selectedWeek,
      onEdit: () =>
          unawaited(_edit(entry: entry, target: target, snapshot: snapshot)),
      onDelete: () => unawaited(_removeEntry(entry, target)),
    );
  }

  Future<void> _search() async {
    final snapshot = model.schedule;
    final target = model.editTarget;
    if (snapshot == null) return;
    final entry = await showScheduleCourseSearch(context, snapshot: snapshot);
    if (!mounted || entry == null || model.editTarget != target) return;
    final current = model.schedule!.entries
        .where((item) => item.id == entry.id)
        .firstOrNull;
    if (current == null) {
      _message('课表已更新，请重新查找这门课程');
      return;
    }
    if (current.weeks.isNotEmpty && !current.occursInWeek(model.selectedWeek)) {
      final weeks = current.weeks.toList()..sort();
      model.showTeachingWeek(
        weeks.where((week) => week >= model.selectedWeek).firstOrNull ??
            weeks.first,
      );
    }
    model.showSection(ScheduleSection.timetable);
    await _details(current);
  }

  void _lessonDetails(ScheduleLesson lesson) =>
      unawaited(_details(lesson.entry, week: lesson.week));

  Future<void> _editEvent([ScheduleEvent? event]) async {
    final result = await showScheduleEventEditor(
      context,
      model,
      initialDate: event?.date ?? model.agendaDate,
      event: event,
    );
    if (mounted && result != null) {
      _message(result == ScheduleEventEditResult.saved ? '日程已保存到本机' : '日程已删除');
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _removeEntry(ScheduleEntry entry, ScheduleTarget target) async {
    final imported = entry.origin == ScheduleEntryOrigin.imported;
    if (!await _confirm(
          title: imported ? '隐藏这条上课安排？' : '删除本地课程？',
          message: imported
              ? '只从本机课表隐藏「${entry.name}」的这条安排，学校选课记录不受影响。'
              : '删除「${entry.name}」的本地安排。若它是对导入课程的调整，将恢复学校原安排。',
          action: imported ? '隐藏' : '删除',
        ) ||
        !mounted) {
      return;
    }
    if (await model.removeEntry(entry, target: target)) {
      _message(imported ? '已隐藏，可在“设置 → 课表”中恢复学校安排' : '本地课程已删除');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) => CallbackShortcuts(
      bindings: {
        if (model.section == ScheduleSection.timetable) ...{
          const SingleActivator(LogicalKeyboardKey.arrowLeft):
              model.previousWeek,
          const SingleActivator(LogicalKeyboardKey.arrowRight): model.nextWeek,
          const SingleActivator(LogicalKeyboardKey.home): () =>
              unawaited(model.returnToCurrentWeek()),
        },
      },
      child: Focus(autofocus: true, child: _schedule()),
    ),
  );

  Widget _unimported() => ListView(
    padding: const EdgeInsets.all(AppLayout.pagePadding),
    children: [
      _WeekHeader(viewModel: model),
      const SizedBox(height: 16),
      _WeekDays(viewModel: model),
      const SizedBox(height: AppLayout.sectionGap),
      Row(
        children: [
          Icon(
            widget.isSignedIn ? Icons.link_rounded : Icons.link_off_rounded,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.isSignedIn ? '已连接教务账号' : '未连接教务账号',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      EmptyStateCard(
        icon: Icons.calendar_month_outlined,
        title: '课表还没有同步',
        message: model.canRefresh
            ? '在“设置 → 课表”中导入整个学期后，可离线查看今日课程与每周课表。'
            : '在设置中连接教务账号并导入课表，即可查看每周课程、上课时间与地点。',
        actionLabel: '前往设置',
        onAction: widget.onOpenSettings,
      ),
      const SizedBox(height: 16),
      Text(
        '当前显示日历日期，导入后请在设置中填写教学周。',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ],
  );

  Widget _termButton() => TextButton.icon(
    onPressed: model.account == null || model.data.loading
        ? null
        : () => selectScheduleTerm(context, model),
    icon: const Icon(Icons.expand_more, size: 20),
    label: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          model.selectedTerm?.label ?? '课表与日程',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          [
            model.account?.account.schoolName ?? widget.schoolName,
            if (model.account != null) model.account!.account.accountName,
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );

  Widget _failure() {
    final failure = model.data.failure!;
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Row(
          children: [
            Expanded(
              child: Semantics(liveRegion: true, child: Text(failure.message)),
            ),
            if (failure.kind == ScheduleFailureKind.storage)
              TextButton(
                onPressed: model.data.loading ? null : model.retryLocalLoad,
                child: const Text('重试读取'),
              ),
            if (model.hasSchedule &&
                failure.kind == ScheduleFailureKind.termSelection)
              TextButton(
                onPressed: widget.onOpenSettings,
                child: const Text('前往设置'),
              ),
            IconButton(
              tooltip: '关闭课表错误提示',
              onPressed: model.dismissFailure,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }

  Widget _schedule() => SafeArea(
    bottom: false,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppLayout.workspaceMaxWidth,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 420;
            final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final wide =
                constraints.maxWidth / textScale >= AppLayout.workspaceMinWidth;
            final theme = Theme.of(context);
            return Column(
              children: [
                Padding(
                  padding: wide
                      ? const EdgeInsets.fromLTRB(24, 12, 24, 12)
                      : const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _termButton(),
                        ),
                      ),
                      if (wide) ...[
                        SizedBox(width: 240, child: _sectionTabs()),
                        const SizedBox(width: 16),
                      ],
                      IconButton(
                        tooltip: '查找课程',
                        onPressed: model.hasSchedule ? _search : null,
                        icon: const Icon(Icons.search),
                      ),
                    ],
                  ),
                ),
                if (!wide)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: _sectionTabs(),
                  ),
                if (model.data.loading || model.data.refreshing)
                  const LinearProgressIndicator(minHeight: 2),
                if (model.data.failure != null)
                  Flexible(
                    flex: 0,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: constraints.maxHeight * .22,
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(8),
                        child: _failure(),
                      ),
                    ),
                  ),
                Expanded(
                  child: switch (model.section) {
                    ScheduleSection.agenda => AgendaScheduleView(
                      model: model,
                      onCourse: _lessonDetails,
                      onAdd: () => unawaited(_editEvent()),
                      onEvent: _editEvent,
                      onOpenSettings: widget.onOpenSettings,
                    ),
                    ScheduleSection.timetable =>
                      model.hasSchedule
                          ? _weekContent(
                              wide: wide,
                              compact: compact,
                              theme: theme,
                            )
                          : _unimported(),
                  },
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  Widget _sectionTabs() {
    final colors = Theme.of(context).colorScheme;
    final showIcons = MediaQuery.textScalerOf(context).scale(14) / 14 < 1.5;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            for (final section in ScheduleSection.values)
              Expanded(
                child: Semantics(
                  selected: model.section == section,
                  child: TextButton.icon(
                    key: ValueKey('schedule-section-${section.name}'),
                    onPressed: () => model.showSection(section),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      backgroundColor: model.section == section
                          ? colors.primaryContainer
                          : Colors.transparent,
                      foregroundColor: model.section == section
                          ? colors.onPrimaryContainer
                          : colors.onSurfaceVariant,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: showIcons
                        ? Icon(switch (section) {
                            ScheduleSection.timetable =>
                              Icons.view_week_outlined,
                            ScheduleSection.agenda => Icons.event_note_outlined,
                          }, size: 18)
                        : null,
                    label: Text(switch (section) {
                      ScheduleSection.timetable => '课表',
                      ScheduleSection.agenda => '日程',
                    }),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _weekContent({
    required bool wide,
    required bool compact,
    required ThemeData theme,
  }) => Column(
    children: [
      Padding(
        padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 8),
        child: Row(
          children: [
            if (wide) ...[
              const Spacer(),
              SizedBox(width: 320, child: _weekNavigation(compact: compact)),
            ] else
              Expanded(child: _weekNavigation(compact: compact)),
            if (model.currentPosition.status != TeachingWeekStatus.unknown)
              _currentWeekButton(compact: !wide),
          ],
        ),
      ),
      Expanded(
        child: Padding(
          padding: wide
              ? const EdgeInsets.fromLTRB(24, 8, 24, 24)
              : EdgeInsets.zero,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(wide ? 16 : 0),
              border: wide
                  ? Border.all(color: theme.colorScheme.outlineVariant)
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(wide ? 16 : 0),
              child: _TeachingWeeks(
                key: ValueKey(model.editTarget),
                snapshot: model.schedule!,
                selectedWeek: model.selectedWeek,
                weekCount: model.weekCount,
                today: model.today,
                agenda: model.agenda,
                onWeek: model.showTeachingWeek,
                onCourse: _details,
              ),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _currentWeekButton({bool compact = false}) => compact
      ? IconButton(
          tooltip: '回到本周',
          onPressed: model.isCurrentWeek ? null : model.returnToCurrentWeek,
          icon: const Icon(Icons.today_outlined),
        )
      : TextButton(
          onPressed: model.isCurrentWeek ? null : model.returnToCurrentWeek,
          child: const Text('回到本周'),
        );

  Widget _weekNavigation({required bool compact}) => Row(
    children: [
      IconButton(
        tooltip: '上一周',
        onPressed: model.canPreviousWeek ? model.previousWeek : null,
        icon: const Icon(Icons.chevron_left),
      ),
      Expanded(
        child: TextButton(
          onPressed: _chooseWeek,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      '第${model.selectedWeek}周',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const Icon(Icons.expand_more, size: 18),
                ],
              ),
              if (!compact)
                Text(
                  model.rangeLabel,
                  key: const ValueKey('timetable-week-range'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ),
      IconButton(
        tooltip: '下一周',
        onPressed: model.canNextWeek ? model.nextWeek : null,
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );
}

class _TeachingWeeks extends StatefulWidget {
  const _TeachingWeeks({
    super.key,
    required this.snapshot,
    required this.selectedWeek,
    required this.weekCount,
    required this.today,
    required this.agenda,
    required this.onWeek,
    required this.onCourse,
  });
  final ScheduleSnapshot snapshot;
  final int selectedWeek;
  final int weekCount;
  final DateTime today;
  final bool agenda;
  final ValueChanged<int> onWeek;
  final ValueChanged<ScheduleEntry> onCourse;

  @override
  State<_TeachingWeeks> createState() => _TeachingWeeksState();
}

class _TeachingWeeksState extends State<_TeachingWeeks> {
  late final PageController _pages;
  late int _reportedPage;
  double _verticalOffset = 0;
  int _navigationTicket = 0;

  @override
  void initState() {
    super.initState();
    _reportedPage = widget.selectedWeek - 1;
    _pages = PageController(initialPage: _reportedPage);
  }

  @override
  void didUpdateWidget(_TeachingWeeks oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedWeek - 1 == _reportedPage) return;
    final ticket = ++_navigationTicket;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ticket != _navigationTicket || !_pages.hasClients) return;
      _reportedPage = widget.selectedWeek - 1;
      _pages.jumpToPage(_reportedPage);
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
    behavior: ScrollConfiguration.of(context).copyWith(
      dragDevices: {
        ...ScrollConfiguration.of(context).dragDevices,
        PointerDeviceKind.mouse,
      },
    ),
    child: PageView.builder(
      key: const ValueKey('timetable-week-pages'),
      controller: _pages,
      itemCount: widget.weekCount,
      allowImplicitScrolling: true,
      onPageChanged: (index) {
        _reportedPage = index;
        widget.onWeek(index + 1);
      },
      itemBuilder: (context, index) => TimetableGrid(
        key: ValueKey('teaching-week-${index + 1}'),
        snapshot: widget.snapshot,
        week: index + 1,
        today: widget.today,
        onCourseTap: widget.onCourse,
        agenda: widget.agenda,
        active: index + 1 == widget.selectedWeek,
        scrollOffset: _verticalOffset,
        onScroll: (offset) => _verticalOffset = offset,
      ),
    ),
  );
}

class _WeekHeader extends StatelessWidget {
  const _WeekHeader({required this.viewModel});

  final TimetableViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                viewModel.yearLabel,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: viewModel.isCurrentWeek
                  ? null
                  : viewModel.returnToCurrentWeek,
              icon: const Icon(Icons.today_outlined, size: 18),
              label: const Text('回到本周'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            IconButton.outlined(
              tooltip: '上一周',
              onPressed: viewModel.previousWeek,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  viewModel.rangeLabel,
                  key: const ValueKey('timetable-week-range'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            IconButton.outlined(
              tooltip: '下一周',
              onPressed: viewModel.nextWeek,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ],
    );
  }
}

class _WeekDays extends StatelessWidget {
  const _WeekDays({required this.viewModel});

  static const weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];
  final TimetableViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final day in viewModel.week.days)
              Expanded(
                child: Semantics(
                  container: true,
                  label:
                      '${day.month}月${day.day}日，星期'
                      '${weekdayLabels[day.weekday - DateTime.monday]}'
                      '${viewModel.isToday(day) ? '，今天' : ''}',
                  excludeSemantics: true,
                  child: Column(
                    children: [
                      Text(
                        weekdayLabels[day.weekday - DateTime.monday],
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: viewModel.isToday(day) ? colors.primary : null,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          '${day.day}',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: viewModel.isToday(day)
                                ? colors.onPrimary
                                : colors.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
