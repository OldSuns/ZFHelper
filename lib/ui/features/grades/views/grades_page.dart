import 'package:flutter/material.dart';
import 'package:zf_core/zf_core.dart';

import '../../../../data/repositories/grade_repository.dart';
import '../../../core/adaptive_sheet.dart';
import '../../../core/app_theme.dart';
import '../view_models/grades_view_model.dart';
import 'grade_detail_sheet.dart';
import 'grade_record_table.dart';
import 'grade_record_tile.dart';

class GradesPage extends StatefulWidget {
  const GradesPage({
    required this.viewModel,
    required this.schoolName,
    required this.onOpenSettings,
    super.key,
  });

  final GradesViewModel viewModel;
  final String schoolName;
  final VoidCallback onOpenSettings;

  @override
  State<GradesPage> createState() => _GradesPageState();
}

enum _GradeAction { accounts, information, clear }

class _GradesPageState extends State<GradesPage> {
  static const _workspaceMinHeight = 440.0;

  final _scroll = ScrollController();
  late final TextEditingController _search;
  String? _selectedRecordId;
  AccountScope? _selectedScope;

  GradesViewModel get model => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: model.query);
    model.addListener(_syncPageState);
  }

  @override
  void didUpdateWidget(covariant GradesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel == model) return;
    oldWidget.viewModel.removeListener(_syncPageState);
    model.addListener(_syncPageState);
    _clearSelection();
    _syncPageState();
  }

  void _syncPageState() {
    if (_resolveRecord(_selectedScope, _selectedRecordId) == null) {
      _clearSelection();
    }
    if (_search.text == model.query) return;
    _search.value = TextEditingValue(
      text: model.query,
      selection: TextSelection.collapsed(offset: model.query.length),
    );
  }

  GradeRecord? _resolveRecord(
    AccountScope? scope,
    String? id, [
    List<GradeRecord>? records,
  ]) {
    if (scope == null || scope != model.account?.account.scope || id == null) {
      return null;
    }
    for (final record in records ?? model.visibleRecords) {
      if (record.id == id) return record;
    }
    return null;
  }

  void _clearSelection() {
    _selectedRecordId = null;
    _selectedScope = null;
  }

  Future<void> _openRecord(
    AccountScope? scope,
    String id, {
    bool inline = false,
  }) async {
    if (_resolveRecord(scope, id) == null) return;
    setState(() {
      _selectedRecordId = id;
      _selectedScope = scope;
    });
    if (inline) return;
    final viewModel = model;
    await showGradeDetails(
      context,
      listenable: viewModel,
      resolveRecord: () => mounted && identical(model, viewModel)
          ? _resolveRecord(_selectedScope, _selectedRecordId)
          : null,
    );
  }

  @override
  void dispose() {
    model.removeListener(_syncPageState);
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _refresh() async {
    final scope = model.account?.account.scope;
    final updated = await model.refresh();
    if (!mounted || model.account?.account.scope != scope || !updated) return;
    _message('成绩已更新');
  }

  Future<void> _chooseTerm() async {
    final scope = model.account?.account.scope;
    final terms = model.terms;
    final result = await showAdaptiveSheet<({String? key})>(
      context: context,
      builder: (context) => _ChoiceSheet(
        title: '选择学期',
        children: [
          _choice(
            label: '全部学期',
            selected: model.selectedTermKey == null,
            onTap: () => Navigator.of(context).pop((key: null)),
          ),
          for (final term in terms)
            _choice(
              label: term.label,
              selected: model.selectedTermKey == term.key,
              onTap: () => Navigator.of(context).pop((key: term.key)),
            ),
          if (model.hasUnassignedTerms)
            _choice(
              label: '学校未标注学期',
              selected: model.selectedTermKey == unassignedGradeTermKey,
              onTap: () =>
                  Navigator.of(context).pop((key: unassignedGradeTermKey)),
            ),
        ],
      ),
    );
    if (!mounted || result == null) return;
    if (model.account?.account.scope != scope) {
      _message('账号已切换，请重新选择学期');
      return;
    }
    if (await model.selectTerm(result.key) && mounted && _scroll.hasClients) {
      _scroll.jumpTo(0);
    }
  }

  Future<void> _chooseAccount() async {
    final accounts = model.data.library.accounts;
    final scope = await showAdaptiveSheet<AccountScope>(
      context: context,
      builder: (context) => _ChoiceSheet(
        title: '本机保存的成绩',
        children: [
          for (final account in accounts)
            ListTile(
              title: Text(account.account.schoolName),
              subtitle: Text(
                '${account.account.accountName} · ${account.account.loginName}\n'
                '${account.snapshot == null ? '尚未查询' : '${account.snapshot!.records.length} 条成绩记录'}',
              ),
              isThreeLine: true,
              selected: model.account?.account.scope == account.account.scope,
              trailing: model.account?.account.scope == account.account.scope
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

  Future<void> _showInformation() => showDialog<void>(
    context: context,
    builder: (context) {
      final snapshot = model.snapshot;
      final summary = model.summary;
      return AlertDialog(
        title: const Text('成绩与统计说明'),
        scrollable: true,
        content: SelectableText(
          [
            if (model.account case final account?)
              '${account.account.schoolName}\n'
                  '${account.account.accountName} · ${account.account.loginName}',
            if (snapshot != null)
              '来源：${snapshot.sourceLabel}\n'
                  '更新时间：${_savedAt(snapshot.fetchedAt)}\n'
                  '已保存 ${snapshot.records.length} 条成绩记录，主动更新前一直可离线查看。',
            '统计范围：${model.termLabel}，${_filterLabel(model.filter)}'
                '${model.query.isEmpty ? '' : '，搜索“${model.query}”'}。',
            '记录学分：当前 ${summary.recordCount} 条记录中，'
                '${summary.creditsCount} 条提供了有效学分，'
                '合计 ${_number(summary.totalCredits)}。该合计不代表已获学分。',
            '参考加权绩点：学校绩点 × 学分的总和 ÷ 对应学分总和。'
                '本次有 ${summary.gradePointCount} 条记录参与，'
                '对应 ${_number(summary.gradePointCredits)} 学分。'
                '仅计入有效的学校绩点及正学分，缺少字段时不自行换算。',
            '文字成绩按学校原文展示；补考、重修保留为各自的成绩记录，'
                '不合并或替代原记录。参考统计不等同于学校官方累计绩点。',
            '“学校标记未通过”仅依据学校明确的通过状态，'
                '不统一按 60 分判定。',
          ].join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      );
    },
  );

  Future<void> _clearCache() async {
    final account = model.account;
    if (account == null || account.snapshot == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除本机成绩？'),
        content: Text(
          '将清除 ${account.account.schoolName} · '
          '${account.account.accountName} 在本机保存的成绩。'
          '之后需要登录此账号重新查询。学校的成绩记录不会改变。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清除本机成绩'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    if (model.account?.account.scope != account.account.scope) {
      _message('账号已切换，请重新确认要清除的成绩');
      return;
    }
    if (await model.clearCurrentCache()) _message('该账号的本机成绩已清除');
  }

  void _action(_GradeAction action) {
    switch (action) {
      case _GradeAction.accounts:
        _chooseAccount();
      case _GradeAction.information:
        _showInformation();
      case _GradeAction.clear:
        _clearCache();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) {
      final records = model.visibleRecords;
      return SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final textScale = (MediaQuery.textScalerOf(context).scale(14) / 14)
                .clamp(1.0, double.infinity);
            final availableWidth = constraints.maxWidth.clamp(
              0.0,
              AppLayout.workspaceMaxWidth,
            );
            final effectiveWidth = availableWidth / textScale;
            final useTable =
                effectiveWidth >= AppLayout.workspaceListMinWidth &&
                constraints.maxHeight >= _workspaceMinHeight * textScale;
            return useTable
                ? _workspace(
                    records,
                    showDetails: effectiveWidth >= AppLayout.workspaceMinWidth,
                  )
                : _mobileList(records);
          },
        ),
      );
    },
  );

  Widget _mobileList(List<GradeRecord> records) {
    final snapshot = model.snapshot;
    final scope = model.account?.account.scope;
    final content = CustomScrollView(
      controller: _scroll,
      key: const PageStorageKey('grades-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(child: _header()),
        if (model.data.refreshing)
          const SliverToBoxAdapter(
            child: LinearProgressIndicator(
              minHeight: 2,
              semanticsLabel: '正在更新成绩',
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.list(
            children: [
              if (model.data.failure != null) _failure(),
              if (snapshot != null) ...[
                _termBar(),
                if (snapshot.records.isNotEmpty) ...[
                  _searchBar(),
                  if (model.filter != GradeFilter.all)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _filterChip(),
                    ),
                  const SizedBox(height: 8),
                  _SummaryStrip(
                    summary: model.summary,
                    onTap: _showInformation,
                  ),
                  const SizedBox(height: 4),
                ],
              ],
              if (snapshot == null || records.isEmpty) _emptyState(),
            ],
          ),
        ),
        if (records.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.separated(
              itemCount: records.length,
              itemBuilder: (context, index) {
                final record = records[index];
                return GradeRecordTile(
                  key: ValueKey((scope, record.id)),
                  record: record,
                  showTerm: model.selectedTermKey == null,
                  onTap: () => _openRecord(scope, record.id),
                );
              },
              separatorBuilder: (context, _) => const Divider(height: 1),
            ),
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
          child: model.canRefresh
              ? RefreshIndicator(onRefresh: _refresh, child: content)
              : content,
        ),
      ),
    );
  }

  Widget _workspace(List<GradeRecord> records, {required bool showDetails}) {
    final scope = model.account?.account.scope;
    final selected = _resolveRecord(_selectedScope, _selectedRecordId, records);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppLayout.workspaceMaxWidth,
        ),
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
                  child: records.isEmpty
                      ? _panel(
                          child: Scrollbar(
                            controller: _scroll,
                            child: ListView(
                              controller: _scroll,
                              children: [_emptyState()],
                            ),
                          ),
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _panel(
                                child: GradeRecordTable(
                                  key: ValueKey(scope),
                                  records: records,
                                  selectedId: selected?.id,
                                  showTerm: model.selectedTermKey == null,
                                  sort: model.sort,
                                  onSort: model.setSort,
                                  onSelected: (record) => _openRecord(
                                    scope,
                                    record.id,
                                    inline: showDetails,
                                  ),
                                  controller: _scroll,
                                ),
                              ),
                            ),
                            if (showDetails) ...[
                              const SizedBox(width: AppLayout.paneGap),
                              SizedBox(
                                width: AppLayout.detailPaneWidth,
                                child: _panel(
                                  child: GradeDetailsPane(
                                    key: ValueKey((scope, selected?.id)),
                                    record: selected,
                                    onClose: selected == null
                                        ? null
                                        : () => setState(_clearSelection),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _workspaceToolbar() {
    final snapshot = model.snapshot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(workspace: true),
        if (model.data.refreshing)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(
              minHeight: 2,
              semanticsLabel: '正在更新成绩',
            ),
          ),
        if (model.data.failure != null) _failure(),
        if (snapshot != null)
          Row(
            children: [
              Flexible(flex: 2, child: _termBar()),
              if (snapshot.records.isNotEmpty) ...[
                const SizedBox(width: 16),
                Expanded(flex: 3, child: _searchBar()),
              ],
            ],
          ),
        if (snapshot != null && snapshot.records.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _SummaryStrip(
                  summary: model.summary,
                  onTap: _showInformation,
                  compact: true,
                ),
                if (model.filter != GradeFilter.all) _filterChip(),
              ],
            ),
          ),
      ],
    );
  }

  Widget _panel({required Widget child}) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );

  Widget _filterChip() => InputChip(
    label: Text(_filterLabel(model.filter)),
    onDeleted: () => model.setFilter(GradeFilter.all),
    deleteButtonTooltipMessage: '清除成绩筛选',
  );

  Widget _header({bool workspace = false}) {
    final account = model.account?.account;
    final label = account == null
        ? widget.schoolName
        : '${account.schoolName} · ${account.accountName}';
    final busy = model.data.loading || model.data.refreshing;
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
                Text('成绩', style: Theme.of(context).textTheme.headlineSmall),
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
          if (workspace) ...[
            const SizedBox(width: 16),
            FilledButton.tonalIcon(
              onPressed: busy
                  ? null
                  : model.canRefresh
                  ? _refresh
                  : widget.onOpenSettings,
              icon: const Icon(Icons.sync_rounded),
              label: Text(model.canRefresh ? '更新成绩' : '登录后更新'),
            ),
            const SizedBox(width: 8),
          ] else
            IconButton(
              tooltip: model.canRefresh ? '更新成绩' : '登录后更新成绩',
              onPressed: busy
                  ? null
                  : model.canRefresh
                  ? _refresh
                  : widget.onOpenSettings,
              icon: const Icon(Icons.sync_rounded),
            ),
          PopupMenuButton<_GradeAction>(
            tooltip: '成绩菜单',
            onSelected: _action,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _GradeAction.accounts,
                enabled:
                    !model.data.loading &&
                    model.data.library.accounts.isNotEmpty,
                child: const Text('本机保存的成绩'),
              ),
              PopupMenuItem(
                value: _GradeAction.information,
                enabled: model.snapshot != null,
                child: const Text('更新时间与统计说明'),
              ),
              PopupMenuItem(
                value: _GradeAction.clear,
                enabled: !busy && model.snapshot != null,
                child: const Text('清除本机成绩'),
              ),
            ],
          ),
          IconButton(
            tooltip: '账号与设置',
            onPressed: widget.onOpenSettings,
            icon: const Icon(Icons.person_outline_rounded),
          ),
        ],
      ),
    );
  }

  Widget _termBar() => Row(
    children: [
      Expanded(
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _chooseTerm,
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            label: Text(
              model.termLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            iconAlignment: IconAlignment.end,
          ),
        ),
      ),
      Tooltip(
        message:
            '正在查看本机保存的成绩\n'
            '更新时间：${_savedAt(model.snapshot!.fetchedAt)}',
        child: Text(
          '本机保存',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    ],
  );

  Widget _searchBar() => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: TextField(
          key: const ValueKey('grades-search'),
          controller: _search,
          textInputAction: TextInputAction.search,
          onChanged: model.setQuery,
          decoration: InputDecoration(
            labelText: '搜索成绩',
            hintText: '课程、代码或教师',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            suffixIcon: model.query.isEmpty
                ? null
                : IconButton(
                    tooltip: '清空搜索',
                    onPressed: () => model.setQuery(''),
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
      ),
      PopupMenuButton<GradeSort>(
        tooltip: '排序：${_sortLabel(model.sort)}',
        onSelected: model.setSort,
        icon: const Icon(Icons.sort_rounded),
        itemBuilder: (context) => [
          for (final sort in GradeSort.values)
            CheckedPopupMenuItem(
              value: sort,
              checked: sort == model.sort,
              child: Text(_sortLabel(sort)),
            ),
        ],
      ),
      PopupMenuButton<GradeFilter>(
        tooltip: '筛选：${_filterLabel(model.filter)}',
        onSelected: model.setFilter,
        icon: Icon(
          model.filter == GradeFilter.all
              ? Icons.filter_alt_outlined
              : Icons.filter_alt_rounded,
          color: model.filter == GradeFilter.all
              ? null
              : Theme.of(context).colorScheme.primary,
        ),
        itemBuilder: (context) => [
          for (final filter in GradeFilter.values)
            CheckedPopupMenuItem(
              value: filter,
              checked: filter == model.filter,
              child: Text(_filterLabel(filter)),
            ),
        ],
      ),
    ],
  );

  Widget _failure() {
    final failure = model.data.failure!;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        '${failure.message}'
                        '${model.snapshot == null ? '' : '\n仍显示上次保存的成绩。'}',
                        style: TextStyle(color: colors.onErrorContainer),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭成绩错误提示',
                    onPressed: model.dismissFailure,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              if (failure.kind == GradeFailureKind.storage)
                TextButton(
                  onPressed: model.data.loading ? null : model.retryLocalLoad,
                  child: const Text('重新读取本机成绩'),
                ),
              if (failure.kind == GradeFailureKind.authentication)
                TextButton(
                  onPressed: widget.onOpenSettings,
                  child: const Text('前往登录'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    if (model.data.loading ||
        (model.data.refreshing && model.snapshot == null)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(model.data.loading ? '正在读取本机成绩…' : '正在查询学校公布的成绩…'),
          ],
        ),
      );
    }
    final snapshot = model.snapshot;
    if (snapshot != null && snapshot.records.isNotEmpty) {
      return _EmptyGrades(
        icon: Icons.search_off_rounded,
        title: '没有符合条件的成绩',
        message: '可以调整学期、搜索内容或筛选条件。',
        actionLabel: '清空搜索与筛选',
        onAction: () {
          model.setQuery('');
          model.setFilter(GradeFilter.all);
        },
      );
    }
    if (snapshot != null) {
      return _EmptyGrades(
        icon: Icons.assignment_outlined,
        title: '学校暂无已公布成绩',
        message: '本次查询未返回成绩记录，可稍后主动更新。',
        actionLabel: model.canRefresh ? '更新成绩' : '登录后更新',
        onAction: model.data.refreshing
            ? null
            : model.canRefresh
            ? _refresh
            : widget.onOpenSettings,
      );
    }
    if (model.data.failure?.kind == GradeFailureKind.storage) {
      return const SizedBox.shrink();
    }
    if (!model.data.initialized) {
      return _EmptyGrades(
        icon: Icons.storage_rounded,
        title: '本机成绩尚未读取完成',
        message: '请重新读取，已保存的成绩会继续保留。',
        actionLabel: '重新读取本机成绩',
        onAction: model.retryLocalLoad,
      );
    }
    return _EmptyGrades(
      icon: Icons.school_outlined,
      title: model.account == null ? '登录后查询成绩' : '还没有保存的成绩',
      message: model.canRefresh
          ? '查询学校已公布的全部学期成绩，成功后保存在本机。'
          : '请先登录此学校的教务账号。已保存的成绩无需联网即可查看。',
      actionLabel: model.canRefresh ? '查询成绩' : '前往登录',
      onAction: model.canRefresh ? _refresh : widget.onOpenSettings,
    );
  }
}

Widget _choice({
  required String label,
  required bool selected,
  required VoidCallback onTap,
}) => ListTile(
  title: Text(label),
  selected: selected,
  trailing: selected ? const Icon(Icons.check_rounded) : null,
  onTap: onTap,
);

class _ChoiceSheet extends StatelessWidget {
  const _ChoiceSheet({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .8,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: '关闭$title',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.fromLTRB(
              8,
              0,
              8,
              16 + MediaQuery.paddingOf(context).bottom,
            ),
            children: children,
          ),
        ),
      ],
    ),
  );
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.summary,
    required this.onTap,
    this.compact = false,
  });

  final GradeSummary summary;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metrics = [
      ('成绩记录', '${summary.recordCount} 条'),
      (
        '记录学分',
        summary.recordCount > 0 && summary.creditsCount == 0
            ? '暂无'
            : _number(summary.totalCredits),
      ),
      ('参考加权绩点', summary.weightedGradePoint?.toStringAsFixed(2) ?? '暂无'),
    ];
    return Tooltip(
      message: '查看统计范围与计算口径',
      child: Material(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: compact
                ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
                : const EdgeInsets.all(12),
            child: compact
                ? Wrap(
                    spacing: 24,
                    runSpacing: 8,
                    children: [
                      for (final metric in metrics)
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${metric.$1}  ',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              TextSpan(
                                text: metric.$2,
                                style: theme.textTheme.titleSmall,
                              ),
                            ],
                          ),
                        ),
                    ],
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final columns =
                          constraints.maxWidth >=
                              MediaQuery.textScalerOf(context).scale(280)
                          ? 3
                          : 2;
                      final width =
                          (constraints.maxWidth - (columns - 1) * 12) / columns;
                      return Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          for (final metric in metrics)
                            SizedBox(
                              width: width,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    metric.$2,
                                    style: theme.textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    metric.$1,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

class _EmptyGrades extends StatelessWidget {
  const _EmptyGrades({
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

String _sortLabel(GradeSort sort) => switch (sort) {
  GradeSort.schoolOrder => '学校顺序',
  GradeSort.scoreDescending => '成绩从高到低',
  GradeSort.creditDescending => '学分从高到低',
  GradeSort.gradePointDescending => '绩点从高到低',
  GradeSort.name => '课程名称',
};

String _filterLabel(GradeFilter filter) => switch (filter) {
  GradeFilter.all => '全部成绩',
  GradeFilter.nonNumeric => '文字 / 未公布',
  GradeFilter.retakes => '补考与重修',
  GradeFilter.failed => '学校标记未通过',
};

String _number(double value) =>
    value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

String _savedAt(DateTime value) {
  final date = value.toLocal();
  String padded(int number) => number.toString().padLeft(2, '0');
  return '${date.year}/${padded(date.month)}/${padded(date.day)} '
      '${padded(date.hour)}:${padded(date.minute)}';
}
