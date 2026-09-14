import 'package:flutter/material.dart';
import 'package:zf_core/zf_core.dart';

import '../../../../data/repositories/course_repository.dart';
import '../../../core/adaptive_sheet.dart';
import '../../../core/app_theme.dart';
import '../view_models/courses_view_model.dart';
import 'course_details_sheet.dart';
import 'course_list_tile.dart';
import 'selection_operation_card.dart';

class CoursesPage extends StatefulWidget {
  const CoursesPage({
    required this.viewModel,
    required this.schoolName,
    required this.onOpenSettings,
    super.key,
  });

  final CoursesViewModel viewModel;
  final String schoolName;
  final VoidCallback onOpenSettings;

  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

enum _CourseAction { accounts, information, clearCache, clearHistory, settings }

final class _CourseDetailRequest {
  _CourseDetailRequest({
    required this.scope,
    required this.course,
    required this.future,
  });

  final AccountScope scope;
  final CourseOffering course;
  Future<CourseDetails?> future;
}

typedef _SelectedCoursePreview = ({
  AccountScope scope,
  String? roundKey,
  String accountLabel,
  String termLabel,
  SelectedCourse course,
});

class _CoursesPageState extends State<CoursesPage> {
  final _scroll = ScrollController();
  final _previewScroll = ScrollController();
  final _detailsStorage = PageStorageBucket();
  final _pendingOperations = <String>{};
  late final TextEditingController _search;
  _CourseDetailRequest? _detailRequest;
  _SelectedCoursePreview? _selectedPreview;
  bool _detailsInModal = false;

  CoursesViewModel get model => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: model.query);
    model.addListener(_syncView);
  }

  @override
  void didUpdateWidget(covariant CoursesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel == model) return;
    oldWidget.viewModel.removeListener(_syncView);
    _detailRequest = null;
    _selectedPreview = null;
    model.addListener(_syncView);
    _syncView();
  }

  void _syncView() {
    if (_search.text != model.query) {
      _search.value = TextEditingValue(
        text: model.query,
        selection: TextSelection.collapsed(offset: model.query.length),
      );
    }
    final account = model.account?.account;
    final scope = account?.scope;
    final roundKey = model.round?.key;
    final request = _detailRequest;
    final preview = _selectedPreview;
    final clearRequest =
        request != null &&
        (request.scope != scope ||
            request.course.roundKey != roundKey ||
            model.catalog?.courses.any(
                  (course) => course.key == request.course.key,
                ) !=
                true);
    final latestSelected = preview == null
        ? null
        : model.catalog?.selectedCourses
              .where((course) => course.key == preview.course.key)
              .firstOrNull;
    final clearPreview =
        preview != null &&
        (preview.scope != scope ||
            preview.roundKey != roundKey ||
            latestSelected == null);
    final updatePreview =
        preview != null &&
        latestSelected != null &&
        latestSelected != preview.course;
    if (clearRequest || clearPreview || updatePreview) {
      setState(() {
        if (clearRequest) _detailRequest = null;
        if (clearPreview) {
          _selectedPreview = null;
        } else if (updatePreview && account != null) {
          _selectedPreview = (
            scope: account.scope,
            roundKey: roundKey,
            accountLabel: '${account.schoolName} · ${account.accountName}',
            termLabel:
                (latestSelected.term ?? model.round?.term)?.label ?? '学校未标注',
            course: latestSelected,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    model.removeListener(_syncView);
    _search.dispose();
    _scroll.dispose();
    _previewScroll.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _showTab(CoursePageTab tab) {
    model.setTab(tab);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _refresh() async {
    final scope = model.account?.account.scope;
    final refreshed = await model.refresh();
    if (!mounted || !refreshed || model.account?.account.scope != scope) return;
    _message(model.rounds.isEmpty ? '学校当前没有开放的选课轮次' : '课程与已选记录已更新并保存在本机');
  }

  Future<void> _chooseAccount() async {
    final accounts = model.data.library.accounts;
    final selected = model.account?.account.scope;
    final scope = await showAdaptiveSheet<AccountScope>(
      context: context,
      builder: (context) => _ChoiceSheet(
        title: '本机保存的选课账号',
        children: [
          for (final account in accounts)
            ListTile(
              title: Text(account.account.schoolName),
              subtitle: Text(
                '${account.account.accountName} · '
                '${account.account.loginName}\n'
                '${account.catalogs.length} 个已保存轮次',
              ),
              selected: selected == account.account.scope,
              trailing: selected == account.account.scope
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () => Navigator.of(context).pop(account.account.scope),
            ),
        ],
      ),
    );
    if (!mounted || scope == null) return;
    if (await model.selectAccount(scope) && mounted && _scroll.hasClients) {
      _scroll.jumpTo(0);
    }
  }

  Future<void> _chooseRound() async {
    final scope = model.account?.account.scope;
    final rounds = model.rounds;
    final selected = model.round?.key;
    final key = await showAdaptiveSheet<String>(
      context: context,
      builder: (context) => _ChoiceSheet(
        title: '选择学校开放的轮次',
        children: [
          for (final round in rounds)
            ListTile(
              title: Text(round.label),
              subtitle: round.term == null ? null : Text(round.term!.label),
              selected: selected == round.key,
              trailing: selected == round.key
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () => Navigator.of(context).pop(round.key),
            ),
        ],
      ),
    );
    if (!mounted || key == null) return;
    if (model.account?.account.scope != scope) {
      _message('账号已切换，请重新选择轮次');
      return;
    }
    if (await model.selectRound(key) && mounted && _scroll.hasClients) {
      _scroll.jumpTo(0);
    }
  }

  Future<void> _openCourse(CourseOffering course, {bool inline = false}) async {
    final scope = model.account?.account.scope;
    if (scope == null) return;
    var request = _detailRequest;
    if (request == null ||
        request.scope != scope ||
        request.course.key != course.key) {
      request = _CourseDetailRequest(
        scope: scope,
        course: course,
        future: model.sections(course),
      );
      setState(() => _detailRequest = request);
    }
    if (inline) return;
    final opened = request;
    setState(() => _detailsInModal = true);
    final started = await showAdaptiveSheet<bool>(
      context: context,
      builder: (context) => PageStorage(
        bucket: _detailsStorage,
        child: CourseDetailsSheet(
          key: PageStorageKey((opened.scope, opened.course.key)),
          viewModel: model,
          requestedCourse: opened.course,
          requestScope: opened.scope,
          initialFuture: opened.future,
          onReload: () => opened.future = model.sections(opened.course),
          onOpenSettings: () {
            Navigator.of(context).pop();
            widget.onOpenSettings();
          },
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _detailsInModal = false);
    if (started == true) _showTab(CoursePageTab.operations);
  }

  Future<void> _showSelected(
    SelectedCourse course, {
    bool inline = false,
  }) async {
    final account = model.account?.account;
    if (account == null) return;
    final term = course.term ?? model.round?.term;
    final preview = (
      scope: account.scope,
      roundKey: model.round?.key,
      accountLabel: '${account.schoolName} · ${account.accountName}',
      termLabel: term?.label ?? '学校未标注',
      course: course,
    );
    if (_selectedPreview?.course.key != course.key &&
        _previewScroll.hasClients) {
      _previewScroll.jumpTo(0);
    }
    setState(() => _selectedPreview = preview);
    if (inline) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(course.name),
        scrollable: true,
        content: _selectedInformation(preview),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _operate(String id, Future<bool> Function() action) async {
    if (_pendingOperations.contains(id)) return;
    setState(() => _pendingOperations.add(id));
    try {
      await action();
    } finally {
      if (mounted) setState(() => _pendingOperations.remove(id));
    }
  }

  Future<void> _resume(SelectionOperation operation) async {
    final target = operation.target;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('继续选课？'),
        scrollable: true,
        content: Text(
          '${target.schoolName} · ${target.accountName}\n'
          '${target.name}\n${target.round.label}\n\n'
          '继续前会先核对学校已选记录。'
          '${operation.mode == SelectionMode.watch ? '\n本次将重新捡漏 ${operation.duration.inMinutes} 分钟，检查间隔 ${operation.interval.inSeconds} 秒。' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('继续执行'),
          ),
        ],
      ),
    );
    if (mounted && confirmed == true) {
      await _operate(operation.id, () => model.resume(operation.id));
    }
  }

  Future<void> _showInformation() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('选课数据与运行说明'),
      scrollable: true,
      content: SelectableText(
        [
          if (model.account case final account?) ...[
            '${account.account.schoolName} · ${account.account.accountName}',
            if (account.roundsFetchedAt case final updated?)
              '轮次更新：${courseDateTime(updated, seconds: true)}',
          ],
          if (model.catalog case final catalog?) ...[
            '课程更新：${courseDateTime(catalog.fetchedAt, seconds: true)}\n'
                '${catalog.courses.length} 门课程',
            if (catalog.selectedFetchedAt case final updated?)
              '已选更新：${courseDateTime(updated, seconds: true)}\n'
                  '${catalog.selectedCourses.length} 条已选记录',
          ],
          '课程与已选记录按学校、账号和轮次保存在本机。查看已保存的轮次不会自动更新；点击更新后读取学校的最新数据。',
          '搜索与筛选只作用于当前轮次已保存的完整列表。余量来自上次查询，实际选课前会重新读取。',
          '立即选课只执行一次；持续捡漏由你手动启动，到期或点击停止后结束。学校明确确认的已选记录才会标记为选课成功。',
          '所有账号的运行进度统一显示在操作记录中。关闭软件后重新打开，暂停的操作需手动继续，结果待核实的操作需先核实。',
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

  Future<void> _clearCache() async {
    final account = model.account;
    if (account == null) return;
    final confirmed = await _confirm(
      '清除本机选课数据？',
      '将清除 ${account.account.schoolName} · ${account.account.accountName} '
          '在本机保存的轮次、可选课程与已选记录，之后需要重新查询。'
          '操作记录会保留，学校的选课结果不会改变。',
      '清除本机数据',
    );
    if (!mounted || !confirmed) return;
    if (model.account?.account.scope != account.account.scope) {
      _message('账号已切换，请重新确认要清除的数据');
      return;
    }
    if (await model.clearCurrentCache()) _message('本机选课数据已清除');
  }

  Future<void> _clearHistory() async {
    final confirmed = await _confirm(
      '清除已结束的操作记录？',
      '将清除所有账号已结束的操作记录。正在运行、已暂停及结果待核实的记录会保留。',
      '清除已结束记录',
    );
    if (mounted && confirmed && await model.clearHistory()) {
      _message('已结束的操作记录已清除');
    }
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          scrollable: true,
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

  Future<void> _action(_CourseAction action) async {
    switch (action) {
      case _CourseAction.accounts:
        await _chooseAccount();
      case _CourseAction.information:
        await _showInformation();
      case _CourseAction.clearCache:
        await _clearCache();
      case _CourseAction.clearHistory:
        await _clearHistory();
      case _CourseAction.settings:
        widget.onOpenSettings();
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const minimumPaneHeight = 240.0;
      final scaler = MediaQuery.textScalerOf(context);
      final minimumPaneWidth =
          AppLayout.workspacePadding * 2 +
          AppLayout.paneGap +
          AppLayout.detailPaneWidth +
          scaler.scale(AppLayout.detailPaneWidth);
      final showDetails =
          constraints.maxWidth >= AppLayout.workspaceMinWidth &&
          constraints.maxWidth >= minimumPaneWidth &&
          constraints.maxHeight >= scaler.scale(minimumPaneHeight);
      return ListenableBuilder(
        listenable: model,
        builder: (context, _) => SafeArea(
          bottom: false,
          child: constraints.maxWidth >= AppLayout.workspaceListMinWidth
              ? _workspace(showDetails: showDetails)
              : _mobileLayout(),
        ),
      );
    },
  );

  Widget _mobileLayout() {
    final content = CustomScrollView(
      key: const PageStorageKey('courses-list'),
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(child: _header()),
        if (model.data.refreshing)
          const SliverToBoxAdapter(
            child: LinearProgressIndicator(
              minHeight: 2,
              semanticsLabel: '正在更新课程与已选记录',
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.list(
            children: [
              if (model.data.failure != null) _failure(),
              _tabs(),
              if (model.tab != CoursePageTab.operations) ...[
                if (model.activeCount > 0 || model.uncertainCount > 0)
                  _operationNotice(),
                if (model.rounds.isNotEmpty) _roundSelector(),
                if (model.catalog != null) ...[
                  const SizedBox(height: 8),
                  _searchBar(),
                  _listSummary(),
                ],
              ] else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '所有账号的操作记录',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: _records(),
        ),
        SliverToBoxAdapter(
          child: SizedBox(height: 16 + MediaQuery.paddingOf(context).bottom),
        ),
      ],
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppLayout.contentMaxWidth),
        child: Scrollbar(
          controller: _scroll,
          child: model.canRefresh && model.tab != CoursePageTab.operations
              ? RefreshIndicator(onRefresh: _refresh, child: content)
              : content,
        ),
      ),
    );
  }

  Widget _workspace({required bool showDetails}) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: AppLayout.workspaceMaxWidth),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppLayout.workspacePadding,
          8,
          AppLayout.workspacePadding,
          AppLayout.workspacePadding,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * .5,
                ),
                child: SingleChildScrollView(
                  primary: false,
                  child: _workspaceToolbar(),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: !showDetails || model.tab == CoursePageTab.operations
                    ? _workspaceList(inlineDetails: false)
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _workspaceList(inlineDetails: true)),
                          const SizedBox(width: AppLayout.paneGap),
                          SizedBox(
                            width: AppLayout.detailPaneWidth,
                            child: _panel(child: _detailPane()),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _workspaceToolbar() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _header(workspace: true),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _tabs()),
          if (model.activeCount > 0 || model.uncertainCount > 0)
            Flexible(
              child: TextButton.icon(
                onPressed: () => _showTab(CoursePageTab.operations),
                icon: Icon(
                  model.uncertainCount > 0
                      ? Icons.info_outline_rounded
                      : Icons.autorenew_rounded,
                ),
                label: Text(
                  [
                    if (model.activeCount > 0) '${model.activeCount} 项运行中',
                    if (model.uncertainCount > 0)
                      '${model.uncertainCount} 项待核实',
                  ].join(' · '),
                ),
              ),
            ),
        ],
      ),
      if (model.tab != CoursePageTab.operations && model.rounds.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Flexible(flex: 2, child: _roundSelector(compact: true)),
              if (model.catalog != null) ...[
                const SizedBox(width: 16),
                Expanded(flex: 3, child: _searchBar()),
              ],
            ],
          ),
        ),
      if (model.data.refreshing)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: LinearProgressIndicator(
            minHeight: 2,
            semanticsLabel: '正在更新课程与已选记录',
          ),
        ),
      if (model.data.failure != null)
        Padding(padding: const EdgeInsets.only(top: 8), child: _failure()),
    ],
  );

  Widget _workspaceList({required bool inlineDetails}) => _panel(
    child: Scrollbar(
      controller: _scroll,
      thumbVisibility: true,
      child: CustomScrollView(
        key: const PageStorageKey('courses-list'),
        controller: _scroll,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: model.tab == CoursePageTab.operations
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        '所有账号 · ${model.operations.length} 条操作记录',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    )
                  : model.catalog == null
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        model.tab == CoursePageTab.available ? '可选课程' : '已选课程',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    )
                  : _listSummary(),
            ),
          ),
          const SliverToBoxAdapter(child: Divider(height: 1)),
          SliverPadding(
            padding: const EdgeInsets.all(8),
            sliver: _records(workspace: true, inlineDetails: inlineDetails),
          ),
        ],
      ),
    ),
  );

  Widget _panel({required Widget child}) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );

  Widget _detailPane() {
    if (model.tab == CoursePageTab.selected) {
      final preview = _selectedPreview;
      if (preview == null) {
        return _detailPlaceholder('选择一门已选课程', '在这里查看课程时间、教师和教学班信息。');
      }
      return Scrollbar(
        controller: _previewScroll,
        thumbVisibility: true,
        child: SingleChildScrollView(
          key: PageStorageKey((preview.scope, preview.course.key)),
          controller: _previewScroll,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        preview.course.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: '收起已选课程详情',
                      onPressed: () => setState(() => _selectedPreview = null),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(20),
                child: _selectedInformation(preview),
              ),
            ],
          ),
        ),
      );
    }
    final request = _detailRequest;
    if (request == null) {
      return _detailPlaceholder('选择课程，查看教学班', '从左侧选择课程，在这里确认教学班并启动选课或捡漏。');
    }
    if (_detailsInModal) {
      return _detailPlaceholder(request.course.name, '教学班详情已在弹层中打开。');
    }
    return PageStorage(
      bucket: _detailsStorage,
      child: CourseDetailsSheet(
        key: PageStorageKey((request.scope, request.course.key)),
        viewModel: model,
        requestedCourse: request.course,
        requestScope: request.scope,
        initialFuture: request.future,
        embedded: true,
        onReload: () => request.future = model.sections(request.course),
        onClose: () => setState(() => _detailRequest = null),
        onStarted: () {
          if (mounted) _showTab(CoursePageTab.operations);
        },
        onOpenSettings: widget.onOpenSettings,
      ),
    );
  }

  Widget _detailPlaceholder(String title, String message) => Center(
    child: SingleChildScrollView(
      primary: false,
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.touch_app_outlined,
            size: 32,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );

  Widget _selectedInformation(_SelectedCoursePreview preview) {
    final course = preview.course;
    return SelectableText(
      [
        preview.accountLabel,
        '课程编号：${course.courseId}',
        '教学班编号：${course.sectionId}',
        '学期：${preview.termLabel}',
        '教师：${course.teacher ?? '学校未提供'}',
        '时间：${course.time ?? '学校未提供'}',
        '地点：${course.location ?? '学校未提供'}',
        '来自最近一次读取的学校已选记录。',
      ].join('\n\n'),
    );
  }

  Widget _header({bool workspace = false}) {
    final account = model.account?.account;
    final label = account == null
        ? (widget.schoolName.isEmpty ? '请先配置学校并登录' : widget.schoolName)
        : '${account.schoolName} · ${account.accountName}';
    return Padding(
      padding: workspace
          ? const EdgeInsets.only(bottom: 8)
          : const EdgeInsets.fromLTRB(20, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('选课', style: Theme.of(context).textTheme.headlineSmall),
                Tooltip(
                  message: account == null
                      ? label
                      : '$label · ${account.loginName}',
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: model.canRefresh ? '更新课程与已选记录' : '登录后更新课程',
            onPressed: model.busy
                ? null
                : model.canRefresh
                ? _refresh
                : widget.onOpenSettings,
            icon: const Icon(Icons.sync_rounded),
          ),
          PopupMenuButton<_CourseAction>(
            tooltip: '选课菜单',
            onSelected: _action,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _CourseAction.accounts,
                enabled:
                    !model.data.loading &&
                    model.data.library.accounts.isNotEmpty,
                child: const Text('本机保存的账号'),
              ),
              const PopupMenuItem(
                value: _CourseAction.information,
                child: Text('更新时间与运行说明'),
              ),
              PopupMenuItem(
                value: _CourseAction.clearCache,
                enabled: !model.busy && model.account?.roundsFetchedAt != null,
                child: const Text('清除本机选课数据'),
              ),
              PopupMenuItem(
                value: _CourseAction.clearHistory,
                enabled: model.data.operations.isNotEmpty,
                child: const Text('清除已结束的操作记录'),
              ),
              const PopupMenuItem(
                value: _CourseAction.settings,
                child: Text('学校与登录设置'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tabs() => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      for (final tab in CoursePageTab.values)
        ChoiceChip(
          label: Text(switch (tab) {
            CoursePageTab.available => '可选课程',
            CoursePageTab.selected => '已选课程',
            CoursePageTab.operations => '操作记录',
          }),
          selected: model.tab == tab,
          onSelected: (_) => _showTab(tab),
        ),
    ],
  );

  Widget _operationNotice() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        dense: true,
        title: Text(
          [
            if (model.activeCount > 0) '${model.activeCount} 项正在运行',
            if (model.uncertainCount > 0) '${model.uncertainCount} 项结果待核实',
          ].join(' · '),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _showTab(CoursePageTab.operations),
      ),
    ),
  );

  Widget _roundSelector({bool compact = false}) => Padding(
    padding: EdgeInsets.only(top: compact ? 0 : 4),
    child: OutlinedButton(
      onPressed: model.busy ? null : _chooseRound,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                [
                  model.round?.label ?? '选择选课轮次',
                  if (model.round?.term case final term?) term.label,
                ].join(compact ? ' · ' : '\n'),
                maxLines: compact ? 1 : null,
                overflow: compact ? TextOverflow.ellipsis : null,
                textAlign: TextAlign.start,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.expand_more_rounded),
          ],
        ),
      ),
    ),
  );

  Widget _searchBar() => LayoutBuilder(
    builder: (context, constraints) {
      final search = TextField(
        controller: _search,
        onChanged: model.setQuery,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          labelText: '搜索当前轮次',
          hintText: '课程、代码、教师或地点',
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          suffixIcon: model.query.isEmpty
              ? null
              : IconButton(
                  tooltip: '清空课程搜索',
                  onPressed: () => model.setQuery(''),
                  icon: const Icon(Icons.close_rounded),
                ),
        ),
      );
      if (model.tab == CoursePageTab.selected) return search;
      final options = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopupMenuButton<CourseSort>(
            tooltip: '排序：${_sortLabel(model.sort)}',
            onSelected: model.setSort,
            icon: const Icon(Icons.sort_rounded),
            itemBuilder: (context) => [
              for (final sort in CourseSort.values)
                CheckedPopupMenuItem(
                  value: sort,
                  checked: model.sort == sort,
                  child: Text(_sortLabel(sort)),
                ),
            ],
          ),
          PopupMenuButton<CourseFilter>(
            tooltip: '筛选：${_filterLabel(model.filter)}',
            onSelected: model.setFilter,
            icon: Icon(
              model.filter == CourseFilter.all
                  ? Icons.filter_alt_outlined
                  : Icons.filter_alt_rounded,
            ),
            itemBuilder: (context) => [
              for (final filter in CourseFilter.values)
                CheckedPopupMenuItem(
                  value: filter,
                  checked: model.filter == filter,
                  child: Text(_filterLabel(filter)),
                ),
            ],
          ),
        ],
      );
      if (constraints.maxWidth < MediaQuery.textScalerOf(context).scale(260)) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            search,
            Align(alignment: Alignment.centerRight, child: options),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: search),
          options,
        ],
      );
    },
  );

  Widget _listSummary() {
    final available = model.tab == CoursePageTab.available;
    final count = available
        ? model.visibleCourses.length
        : model.selectedCourses.length;
    final total = available
        ? model.catalog!.courses.length
        : model.catalog!.selectedCourses.length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '$count / $total ${available ? '门课程' : '条已选记录'}'
            '${model.canRefresh ? '' : ' · 本机缓存'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (available && model.filter != CourseFilter.all)
            InputChip(
              label: Text(_filterLabel(model.filter)),
              onDeleted: () => model.setFilter(CourseFilter.all),
              deleteButtonTooltipMessage: '清除课程筛选',
            ),
        ],
      ),
    );
  }

  Widget _failure() => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  model.data.failure!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: '关闭选课错误提示',
              onPressed: model.dismissFailure,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _records({bool workspace = false, bool inlineDetails = false}) {
    if (model.tab == CoursePageTab.operations) {
      final operations = model.operations;
      if (operations.isEmpty) return SliverToBoxAdapter(child: _emptyState());
      return SliverList.builder(
        itemCount: operations.length,
        itemBuilder: (context, index) {
          final operation = operations[index];
          return SelectionOperationCard(
            key: ValueKey(operation.id),
            operation: operation,
            compact: workspace,
            busy: _pendingOperations.contains(operation.id),
            canQuery: model.canQuery(operation.target.scope),
            onStop: () =>
                _operate(operation.id, () => model.stop(operation.id)),
            onResume: () => _resume(operation),
            onVerify: () =>
                _operate(operation.id, () => model.verify(operation.id)),
            onOpenSettings: widget.onOpenSettings,
          );
        },
      );
    }
    if (model.tab == CoursePageTab.selected) {
      final courses = model.selectedCourses;
      if (courses.isEmpty) return SliverToBoxAdapter(child: _emptyState());
      return SliverList.separated(
        itemCount: courses.length,
        itemBuilder: (context, index) {
          final course = courses[index];
          return ListTile(
            key: ValueKey(course.key),
            selected: workspace && _selectedPreview?.course.key == course.key,
            selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 4,
            ),
            title: Text(course.name),
            subtitle: Text(
              [
                course.courseId,
                if (course.teacher != null) course.teacher!,
                if (course.time != null) course.time!,
              ].join(' · '),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showSelected(course, inline: inlineDetails),
          );
        },
        separatorBuilder: (context, _) => const Divider(height: 1),
      );
    }
    final courses = model.visibleCourses;
    if (courses.isEmpty) return SliverToBoxAdapter(child: _emptyState());
    return SliverList.separated(
      itemCount: courses.length,
      itemBuilder: (context, index) {
        final course = courses[index];
        return CourseListTile(
          key: ValueKey(course.key),
          course: course,
          isSelected: model.isSelected(course),
          isHighlighted: workspace && _detailRequest?.course.key == course.key,
          compact: workspace,
          onTap: () => _openCourse(course, inline: inlineDetails),
        );
      },
      separatorBuilder: (context, _) => const Divider(height: 1),
    );
  }

  Widget _emptyState() {
    if (model.data.loading ||
        (model.data.refreshing &&
            model.catalog == null &&
            model.tab != CoursePageTab.operations)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(model.data.loading ? '正在读取本机选课数据…' : '正在查询学校课程…'),
          ],
        ),
      );
    }
    if (!model.data.initialized) {
      return _EmptyCourses(
        icon: Icons.storage_rounded,
        title: '本机选课数据尚未读取完成',
        message: '请重新读取，已保存的数据会保留。',
        actionLabel: '重新读取',
        onAction: model.initialize,
      );
    }
    if (model.tab == CoursePageTab.operations) {
      return _EmptyCourses(
        icon: Icons.playlist_add_check_rounded,
        title: '还没有选课操作',
        message: '选择课程和具体教学班，手动启动立即选课或持续捡漏。',
        actionLabel: '查看可选课程',
        onAction: () => _showTab(CoursePageTab.available),
      );
    }
    final catalog = model.catalog;
    final total = model.tab == CoursePageTab.available
        ? catalog?.courses.length
        : catalog?.selectedCourses.length;
    if (total != null && total > 0) {
      return _EmptyCourses(
        icon: Icons.search_off_rounded,
        title: '没有符合条件的课程',
        message: '可以调整搜索内容或筛选条件。',
        actionLabel: '清空搜索与筛选',
        onAction: model.clearFilters,
      );
    }
    if (catalog != null) {
      if (model.tab == CoursePageTab.selected &&
          catalog.selectedFetchedAt == null) {
        return _EmptyCourses(
          icon: Icons.playlist_add_check_rounded,
          title: '还没有保存的已选记录',
          message: '更新课程时会同时读取该学期的学校已选记录。',
          actionLabel: model.canRefresh ? '查询已选记录' : '登录后查询',
          onAction: model.busy
              ? null
              : model.canRefresh
              ? _refresh
              : widget.onOpenSettings,
        );
      }
      return _EmptyCourses(
        icon: Icons.menu_book_outlined,
        title: model.tab == CoursePageTab.selected ? '学校暂无已选记录' : '此轮次暂无可选课程',
        message: model.tab == CoursePageTab.selected
            ? '本次查询没有返回该学期的已选课程。'
            : '本次查询没有返回课程，学校开放范围可能会变化。',
        actionLabel: model.canRefresh ? '更新课程' : '登录后更新',
        onAction: model.busy
            ? null
            : model.canRefresh
            ? _refresh
            : widget.onOpenSettings,
      );
    }
    final queried = model.account?.roundsFetchedAt != null;
    return _EmptyCourses(
      icon: Icons.school_outlined,
      title: model.account == null
          ? '登录后查询课程'
          : queried && model.rounds.isEmpty
          ? '学校当前未开放选课轮次'
          : model.round == null
          ? '还没有保存的课程'
          : '此轮次还没有保存的课程',
      message: model.canRefresh
          ? '查询学校当前开放的选课轮次和课程，成功后保存在本机。'
          : '请先登录此学校的教务账号。已保存的课程可以离线查看。',
      actionLabel: model.canRefresh ? '查询课程' : '前往登录',
      onAction: model.canRefresh ? _refresh : widget.onOpenSettings,
    );
  }
}

class _ChoiceSheet extends StatelessWidget {
  const _ChoiceSheet({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .8,
    ),
    child: ListView(
      shrinkWrap: true,
      padding: EdgeInsets.fromLTRB(
        8,
        0,
        8,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: '关闭选择',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        ...children,
      ],
    ),
  );
}

class _EmptyCourses extends StatelessWidget {
  const _EmptyCourses({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 32),
    child: Column(
      children: [
        Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(message, textAlign: TextAlign.center),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    ),
  );
}

String _sortLabel(CourseSort sort) => switch (sort) {
  CourseSort.schoolOrder => '学校顺序',
  CourseSort.name => '课程名称',
  CourseSort.available => '余量从多到少',
};

String _filterLabel(CourseFilter filter) => switch (filter) {
  CourseFilter.all => '全部课程',
  CourseFilter.available => '有余量',
  CourseFilter.unknownCapacity => '余量未知',
};
