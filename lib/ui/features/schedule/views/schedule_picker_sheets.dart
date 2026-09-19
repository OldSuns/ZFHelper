import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zf_core/zf_core.dart';

import '../../../../data/storage/schedule_store.dart';
import '../../../core/adaptive_sheet.dart';
import '../view_models/timetable_view_model.dart';

Future<bool> selectScheduleTerm(
  BuildContext context,
  TimetableViewModel viewModel, {
  bool forImport = false,
}) async {
  var account = viewModel.account;
  if (account == null) return false;
  if (!_hasLocalTermChoices(account) && viewModel.canRefresh) {
    await viewModel.refreshCatalog();
    if (!context.mounted) return false;
    account = viewModel.account;
    if (account == null) return false;
  }
  final term = await showScheduleTermPicker(
    context,
    account: account,
    forImport: forImport,
    viewModel: viewModel,
  );
  if (!context.mounted || term == null) return false;
  if (viewModel.account?.account.scope != account.account.scope) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('账号已切换，请重新选择该账号的学期')));
    return false;
  }
  final selected = await viewModel.selectTerm(term);
  return selected &&
      viewModel.account?.account.scope == account.account.scope &&
      viewModel.selectedTerm == term;
}

bool _hasLocalTermChoices(StoredScheduleAccount account) {
  final catalog = account.catalog;
  return account.schedules.isNotEmpty ||
      catalog != null &&
          (catalog.terms.isNotEmpty ||
              catalog.yearOptions.isNotEmpty && catalog.termOptions.isNotEmpty);
}

Future<AcademicTerm?> showScheduleTermPicker(
  BuildContext context, {
  required StoredScheduleAccount account,
  bool forImport = false,
  TimetableViewModel? viewModel,
}) => showAdaptiveSheet<AcademicTerm>(
  context: context,
  builder: (context) =>
      _TermPicker(account: account, forImport: forImport, viewModel: viewModel),
);

class _TermPicker extends StatefulWidget {
  const _TermPicker({
    required this.account,
    required this.forImport,
    required this.viewModel,
  });
  final StoredScheduleAccount account;
  final bool forImport;
  final TimetableViewModel? viewModel;

  @override
  State<_TermPicker> createState() => _TermPickerState();
}

class _TermPickerState extends State<_TermPicker> {
  late StoredScheduleAccount _account;
  String? _year;
  String? _term;
  final _manualYear = TextEditingController();
  ZhengfangSemester? _manualSemester;
  String? _yearError;
  String? _semesterError;
  bool _refreshing = false;
  String? _refreshFailure;

  @override
  void initState() {
    super.initState();
    _account = widget.account;
  }

  @override
  void dispose() {
    _manualYear.dispose();
    super.dispose();
  }

  void _selectManualTerm() {
    final semester = _manualSemester;
    if (semester == null) {
      setState(() => _semesterError = '请选择学期');
      return;
    }
    try {
      final term = AcademicTerm.zhengfang(
        startYear: _manualYear.text,
        semester: semester,
      );
      Navigator.of(context).pop(term);
    } on FormatException catch (error) {
      setState(() => _yearError = error.message);
    }
  }

  Future<void> _refreshCatalog() async {
    final viewModel = widget.viewModel;
    if (viewModel == null || _refreshing) return;
    final scope = _account.account.scope;
    setState(() {
      _refreshing = true;
      _refreshFailure = null;
    });
    final refreshed = await viewModel.refreshCatalog();
    if (!mounted) return;
    final account = viewModel.account;
    setState(() {
      _refreshing = false;
      if (refreshed && account != null && account.account.scope == scope) {
        _account = account;
        _year = null;
        _term = null;
      } else {
        _refreshFailure = viewModel.data.failure?.message ?? '刷新学期列表失败，请稍后重试';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final account = _account;
    final catalog = account.catalog;
    final selectedYearCode = _year ?? catalog?.selectedTerm?.yearCode;
    final selectedTermCode = _term ?? catalog?.selectedTerm?.termCode;
    final terms = <String, AcademicTerm>{
      for (final term in catalog?.terms ?? <AcademicTerm>[]) term.key: term,
      for (final snapshot in account.schedules.values)
        snapshot.term.key: snapshot.term,
    }.values.toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '选择学期',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (widget.viewModel?.canRefresh ?? false)
                  IconButton(
                    key: const ValueKey('schedule-term-catalog-refresh'),
                    tooltip: '刷新学期列表',
                    onPressed: _refreshing ? null : _refreshCatalog,
                    icon: _refreshing
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                  ),
                IconButton(
                  tooltip: '关闭学期选择',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              widget.forImport
                  ? '请选择要导入的学年和学期。也可以手动填写，不依赖学校页面提供选项。'
                  : '已保存的学期可离线查看。其他学期可手动选择，再前往“设置 → 课表”导入。',
            ),
            if (_refreshFailure != null) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(
                  _refreshFailure!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
            const SizedBox(height: 12),
            for (final term in terms)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(term.label),
                subtitle: Text(
                  [
                    if (catalog?.selectedTerm?.key == term.key) '教务默认学期',
                    account.schedules.containsKey(term.key) ? '已保存在本机' : '尚未导入',
                  ].join(' · '),
                ),
                selected: term.key == account.selectedTermKey,
                trailing: term.key == account.selectedTermKey
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.of(context).pop(term),
              ),
            if (catalog != null &&
                catalog.yearOptions.isNotEmpty &&
                catalog.termOptions.isNotEmpty) ...[
              const Divider(),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const ValueKey('schedule-year-picker'),
                isExpanded: true,
                decoration: const InputDecoration(labelText: '学校提供的学年'),
                initialValue: selectedYearCode,
                items: [
                  for (final year in catalog.yearOptions)
                    DropdownMenuItem(value: year.code, child: Text(year.label)),
                ],
                onChanged: (value) => setState(() => _year = value),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: const ValueKey('schedule-term-picker'),
                isExpanded: true,
                decoration: const InputDecoration(labelText: '学校提供的学期'),
                initialValue: selectedTermCode,
                items: [
                  for (final term in catalog.termOptions)
                    DropdownMenuItem(value: term.code, child: Text(term.label)),
                ],
                onChanged: (value) => setState(() => _term = value),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: selectedYearCode == null || selectedTermCode == null
                    ? null
                    : () {
                        final year = catalog.yearOptions.firstWhere(
                          (item) => item.code == selectedYearCode,
                        );
                        final term = catalog.termOptions.firstWhere(
                          (item) => item.code == selectedTermCode,
                        );
                        Navigator.of(context).pop(
                          AcademicTerm(
                            yearCode: year.code,
                            termCode: term.code,
                            label: '${year.label} ${term.label}',
                          ),
                        );
                      },
                child: Text(widget.forImport ? '导入此学期' : '查看此学期'),
              ),
            ],
            const Divider(),
            ExpansionTile(
              key: const ValueKey('schedule-manual-term-expansion'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: Text(
                '手动选择学年学期',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              children: [
                if (catalog == null ||
                    catalog.yearOptions.isEmpty ||
                    catalog.termOptions.isEmpty)
                  const Text('学校页面未提供完整学期列表，请填写你要查看的学年和学期。'),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('schedule-manual-year'),
                  controller: _manualYear,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: InputDecoration(
                    labelText: '学年起始年份',
                    helperText: '填写学年开始的四位年份',
                    errorText: _yearError,
                    errorMaxLines: 3,
                  ),
                  onChanged: (_) {
                    if (_yearError != null) setState(() => _yearError = null);
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<ZhengfangSemester>(
                  key: const ValueKey('schedule-manual-semester'),
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: '学期',
                    errorText: _semesterError,
                  ),
                  items: [
                    for (final semester in ZhengfangSemester.values)
                      DropdownMenuItem(
                        value: semester,
                        child: Text(semester.label),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    _manualSemester = value;
                    _semesterError = null;
                  }),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const ValueKey('schedule-manual-term-submit'),
                  onPressed: _selectManualTerm,
                  child: Text(widget.forImport ? '导入此学期' : '查看此学期'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<int?> showScheduleWeekPicker(
  BuildContext context, {
  required ScheduleSnapshot snapshot,
  required int selectedWeek,
  required int weekCount,
  required int? currentWeek,
}) => showAdaptiveSheet<int>(
  context: context,
  builder: (context) => _WeekPicker(
    snapshot: snapshot,
    selectedWeek: selectedWeek,
    weekCount: weekCount,
    currentWeek: currentWeek,
  ),
);

class _WeekPicker extends StatefulWidget {
  const _WeekPicker({
    required this.snapshot,
    required this.selectedWeek,
    required this.weekCount,
    required this.currentWeek,
  });
  final ScheduleSnapshot snapshot;
  final int selectedWeek;
  final int weekCount;
  final int? currentWeek;

  @override
  State<_WeekPicker> createState() => _WeekPickerState();
}

class _WeekPickerState extends State<_WeekPicker> {
  static const _weekButtonMaxWidth = 96.0;
  static const _weekButtonHeight = 56.0;

  final _input = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _jump() {
    final week = int.tryParse(_input.text.trim());
    final total = widget.snapshot.navigationWeekLimit;
    if (week == null || week < 1 || (total != null && week > total)) {
      setState(
        () => _error = total == null ? '请输入大于 0 的教学周' : '请输入 1 到 $total 周',
      );
      return;
    }
    Navigator.of(context).pop(week);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .65,
      ),
      child: CustomScrollView(
        shrinkWrap: true,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '选择教学周',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭教学周选择',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('schedule-jump-week-input'),
                          controller: _input,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: '跳转到第几周',
                            errorText: _error,
                            errorMaxLines: 3,
                          ),
                          onSubmitted: (_) => _jump(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(onPressed: _jump, child: const Text('跳转')),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent:
                    _weekButtonMaxWidth *
                    (MediaQuery.textScalerOf(context).scale(14) / 14),
                mainAxisExtent:
                    _weekButtonHeight *
                    (MediaQuery.textScalerOf(context).scale(14) / 14),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: widget.weekCount,
              itemBuilder: (context, index) {
                final week = index + 1;
                final current = week == widget.currentWeek;
                final selected = week == widget.selectedWeek;
                final date = widget.snapshot.calendar.weekDates(week)?.start;
                final theme = Theme.of(context);
                return Semantics(
                  selected: selected,
                  child: OutlinedButton(
                    key: ValueKey('schedule-select-week-$week'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      backgroundColor: selected
                          ? theme.colorScheme.secondaryContainer
                          : null,
                      foregroundColor: selected
                          ? theme.colorScheme.onSecondaryContainer
                          : null,
                      side: selected
                          ? BorderSide(color: theme.colorScheme.primary)
                          : null,
                    ),
                    onPressed: () => Navigator.of(context).pop(week),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          current ? '本周 · $week' : '第$week周',
                          semanticsLabel: '第$week周${current ? '，本周' : ''}',
                          textAlign: TextAlign.center,
                        ),
                        if (date != null)
                          Text(
                            '${date.month}/${date.day}',
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
