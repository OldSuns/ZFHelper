import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:zf_core/zf_core.dart';

import '../../../../data/repositories/schedule_repository.dart';
import '../../../core/app_theme.dart';
import '../../../core/empty_state_card.dart';
import '../../../core/feature_page.dart';
import '../view_models/timetable_view_model.dart';
import 'course_detail_sheet.dart';
import 'course_editor_page.dart';
import 'course_search_sheet.dart';
import 'schedule_calendar_page.dart';
import 'schedule_picker_sheets.dart';
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

enum _ScheduleAction {
  calendar,
  add,
  agenda,
  restore,
  accounts,
  schoolTerm,
  info,
}

class _TimetablePageState extends State<TimetablePage> {
  TimetableViewModel get model => widget.viewModel;

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _refresh({bool useSchoolDefault = false}) async {
    final saved = await model.refresh(useSchoolDefault: useSchoolDefault);
    if (!mounted) return;
    if (!saved) {
      if (model.data.failure?.kind == ScheduleFailureKind.termSelection) {
        await _chooseTerm(importAfterSelection: true);
      }
      return;
    }
    if (model.schedule == null ||
        (useSchoolDefault && model.account?.catalog?.selectedTerm == null)) {
      _message('学校没有指定默认学期，请选择学期后导入');
      await _chooseTerm(importAfterSelection: true);
    } else {
      _message(
        model.schedule!.importWarnings.isEmpty
            ? '课表已保存在本机，下次主动更新前一直可用'
            : '课程已保存在本机；作息导入有提示，请查看导入信息',
      );
    }
  }

  Future<void> _chooseTerm({bool importAfterSelection = false}) async {
    final account = model.account;
    if (account == null) return;
    final term = await showScheduleTermPicker(
      context,
      account: account,
      forImport: importAfterSelection,
    );
    if (!mounted || term == null) return;
    if (model.account?.account.scope != account.account.scope) {
      _message('账号已切换，请重新选择该账号的学期');
      return;
    }
    final selected = await model.selectTerm(term);
    if (selected &&
        importAfterSelection &&
        mounted &&
        model.account?.account.scope == account.account.scope &&
        model.selectedTerm == term) {
      await _refresh();
    }
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

  Future<void> _calendar() async {
    final snapshot = model.imported;
    final target = model.editTarget;
    if (snapshot == null || target == null) return;
    final value = await Navigator.of(context).push<ScheduleSettings>(
      MaterialPageRoute(
        builder: (context) => ScheduleCalendarPage(
          snapshot: snapshot,
          settings: model.settings,
          today: model.today,
          onSave: (value) async =>
              await model.saveSettings(value, target: target)
              ? null
              : model.data.failure?.message ?? '保存未完成，请重试',
        ),
      ),
    );
    if (!mounted || value == null) return;
    _message('校历与作息已保存');
  }

  Future<void> _edit({
    ScheduleEntry? entry,
    ScheduleTarget? target,
    ScheduleSnapshot? snapshot,
  }) async {
    final destination = target ?? model.editTarget;
    final original = snapshot ?? model.schedule;
    if (destination == null || original == null) return;
    final value = await Navigator.of(context).push<ScheduleEntry>(
      MaterialPageRoute(
        builder: (context) => CourseEditorPage(
          entry: entry,
          initialWeek: model.selectedWeek,
          visibleWeekCount: model.weekCount,
          periodCount: original.maxPeriod,
          onSave: (value) async =>
              await model.saveLocalEntry(
                value,
                target: destination,
                replacing: entry,
              )
              ? null
              : model.data.failure?.message ?? '保存未完成，请重试',
        ),
      ),
    );
    if (!mounted || value == null) return;
    _message('课程已保存到本机');
  }

  Future<void> _details(ScheduleEntry entry) async {
    final snapshot = model.schedule;
    final target = model.editTarget;
    if (snapshot == null || target == null) return;
    await showScheduleCourseDetails(
      context,
      entry: entry,
      snapshot: snapshot,
      week: model.selectedWeek,
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
    await _details(current);
  }

  Future<void> _importInfo() async {
    final snapshot = model.imported;
    if (snapshot == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('课表导入信息'),
        scrollable: true,
        content: SelectableText(
          [
            snapshot.term.label,
            '来源：${snapshot.sourceLabel ?? '教务系统'}',
            '更新时间：${_savedAt(snapshot.fetchedAt)}',
            '${snapshot.entries.length} 条学校安排 · ${snapshot.periodTimes.length} 项学校作息',
            '课表已保存在本机，只有主动导入或更新时才重新获取。',
            ...snapshot.importWarnings,
            if (snapshot.calendar.sourceLabel != null)
              '校历来源：${snapshot.calendar.sourceLabel}',
          ].join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
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
      _message(imported ? '已隐藏，可在课表菜单中恢复学校安排' : '本地课程已删除');
    }
  }

  Future<void> _accounts() async {
    final accounts = model.data.library.accounts;
    final action = await showModalBottomSheet<({AccountScope scope, bool remove})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .75,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                '本机保存的课表',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            for (final account in accounts)
              ListTile(
                title: Text(
                  '${account.account.schoolName} · ${account.account.accountName}',
                ),
                subtitle: Text(
                  '${account.account.loginName} · ${account.schedules.length} 个学期',
                ),
                selected: account.account.scope == model.account?.account.scope,
                onTap: () =>
                    Navigator.of(context)
                        .pop((scope: account.account.scope, remove: false)),
                trailing: IconButton(
                  tooltip: '清除此账号的课表',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () =>
                      Navigator.of(context)
                          .pop((scope: account.account.scope, remove: true)),
                ),
              ),
            if (accounts.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('还没有保存在本机的课表'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (!action.remove) {
      await model.selectAccount(action.scope);
      return;
    }
    final record = accounts.firstWhere(
      (item) => item.account.scope == action.scope,
    );
    if (!await _confirm(
          title: '清除此账号的本机课表？',
          message:
              '${record.account.schoolName} · ${record.account.accountName} 的所有已保存学期、本地课程和校历校正将被清除。学校数据不受影响。',
          action: '清除课表',
        ) ||
        !mounted) {
      return;
    }
    if (await model.removeSavedAccount(action.scope)) _message('此账号的本机课表已清除');
  }

  Future<void> _action(_ScheduleAction action) async {
    switch (action) {
      case _ScheduleAction.calendar:
        await _calendar();
      case _ScheduleAction.add:
        await _edit();
      case _ScheduleAction.agenda:
        await model.toggleAgenda();
      case _ScheduleAction.accounts:
        await _accounts();
      case _ScheduleAction.schoolTerm:
        await _refresh(useSchoolDefault: true);
      case _ScheduleAction.info:
        await _importInfo();
      case _ScheduleAction.restore:
        final target = model.editTarget;
        if (target != null &&
            await _confirm(
              title: '恢复学校上课安排？',
              message: '取消对学校安排的隐藏和本地调整，保留另外添加的本地课程。',
              action: '恢复',
            ) &&
            mounted &&
            await model.restoreHiddenEntries(target: target)) {
          _message('学校上课安排已恢复');
        }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): model.previousWeek,
        const SingleActivator(LogicalKeyboardKey.arrowRight): model.nextWeek,
        const SingleActivator(LogicalKeyboardKey.home): () =>
            unawaited(model.returnToCurrentWeek()),
      },
      child: Focus(
        autofocus: true,
        child: model.hasSchedule ? _schedule() : _unimported(),
      ),
    ),
  );

  Widget _unimported() => FeaturePage(
    title: '课表',
    schoolName: model.account?.account.schoolName ?? widget.schoolName,
    onOpenSettings: widget.onOpenSettings,
    children: [
      if (model.data.loading || model.data.refreshing)
        const LinearProgressIndicator(),
      if (model.account != null) _termButton(),
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
      if (model.data.failure != null) _failure(),
      EmptyStateCard(
        icon: Icons.calendar_month_outlined,
        title: '课表还没有同步',
        message: model.canRefresh
            ? '导入整个学期后，可离线查看。仅在你主动更新时重新获取学校课表。'
            : '连接教务账号后，在这里查看每周课程、上课时间与地点。',
        actionLabel: model.canRefresh ? '导入课表' : '账号与设置',
        onAction: model.canRefresh
            ? (model.data.refreshing ? null : _refresh)
            : widget.onOpenSettings,
      ),
      if (model.data.library.accounts.isNotEmpty)
        TextButton(onPressed: _accounts, child: const Text('本机保存的课表')),
      const SizedBox(height: 16),
      Text(
        '当前显示日历日期，教学周将根据学校学期安排确定。',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ],
  );

  Widget _termButton() => TextButton.icon(
    onPressed: model.account == null || model.data.loading ? null : _chooseTerm,
    icon: const Icon(Icons.expand_more, size: 20),
    label: Text(
      model.selectedTerm?.label ?? '选择学期',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
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
            if (failure.kind == ScheduleFailureKind.storage &&
                !model.hasSchedule)
              TextButton(
                onPressed: model.retryLocalLoad,
                child: const Text('重试读取'),
              ),
            if (failure.kind == ScheduleFailureKind.termSelection)
              TextButton(
                onPressed: () => _chooseTerm(importAfterSelection: true),
                child: const Text('手动选择'),
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
        constraints: const BoxConstraints(maxWidth: 1440),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 420;
            final theme = Theme.of(context);
            final snapshot = model.schedule!;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '课表',
                              style: theme.textTheme.headlineSmall,
                              maxLines: 1,
                            ),
                            if (!compact)
                              Text(
                                model.account!.account.schoolName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '查找课程',
                        onPressed: _search,
                        icon: const Icon(Icons.search),
                      ),
                      IconButton(
                        tooltip: '更新课表',
                        onPressed: model.data.refreshing
                            ? null
                            : model.canRefresh
                            ? _refresh
                            : widget.onOpenSettings,
                        icon: const Icon(Icons.sync),
                      ),
                      PopupMenuButton<_ScheduleAction>(
                        tooltip: '课表菜单',
                        onSelected: _action,
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: _ScheduleAction.add,
                            child: Text('添加本地课程'),
                          ),
                          const PopupMenuItem(
                            value: _ScheduleAction.calendar,
                            child: Text('校历与作息'),
                          ),
                          if (model.canRefresh)
                            PopupMenuItem(
                              value: _ScheduleAction.schoolTerm,
                              enabled: !model.data.refreshing,
                              child: const Text('导入教务当前学期'),
                            ),
                          PopupMenuItem(
                            value: _ScheduleAction.agenda,
                            child: Text(model.agenda ? '切换为周网格' : '切换为按天列表'),
                          ),
                          if (model.settings.hiddenEntryIds.isNotEmpty)
                            const PopupMenuItem(
                              value: _ScheduleAction.restore,
                              child: Text('恢复学校安排'),
                            ),
                          const PopupMenuItem(
                            value: _ScheduleAction.accounts,
                            child: Text('本机保存的课表'),
                          ),
                          const PopupMenuItem(
                            value: _ScheduleAction.info,
                            child: Text('导入信息'),
                          ),
                        ],
                      ),
                      IconButton(
                        tooltip: '账号与设置',
                        onPressed: widget.onOpenSettings,
                        icon: const Icon(Icons.person_outline),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _termButton(),
                        ),
                      ),
                      TextButton(
                        onPressed: model.isCurrentWeek
                            ? null
                            : model.currentPosition.status ==
                                  TeachingWeekStatus.unknown
                            ? _calendar
                            : model.returnToCurrentWeek,
                        child: Text(
                          model.currentPosition.status ==
                                  TeachingWeekStatus.unknown
                              ? '设置教学周'
                              : '回到本周',
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: '上一周',
                      onPressed: model.canPreviousWeek
                          ? model.previousWeek
                          : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: _chooseWeek,
                        child: Column(
                          children: [
                            Text(
                              '第${model.selectedWeek}周',
                              style: theme.textTheme.titleMedium,
                            ),
                            if (!compact)
                              Text(
                                model.rangeLabel,
                                key: const ValueKey('timetable-week-range'),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall,
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
                ),
                if (model.data.refreshing)
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
                  child: _TeachingWeeks(
                    key: ValueKey(model.editTarget),
                    snapshot: snapshot,
                    selectedWeek: model.selectedWeek,
                    weekCount: model.weekCount,
                    today: model.today,
                    agenda: model.agenda,
                    onWeek: model.showTeachingWeek,
                    onCourse: _details,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  static String _savedAt(DateTime timestamp) {
    final date = timestamp.toLocal();
    return '${date.year}/${date.month}/${date.day} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
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
