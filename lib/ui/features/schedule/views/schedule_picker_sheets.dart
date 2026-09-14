import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zf_core/zf_core.dart';

import '../../../../data/storage/schedule_store.dart';

Future<AcademicTerm?> showScheduleTermPicker(
  BuildContext context, {
  required StoredScheduleAccount account,
  bool forImport = false,
}) => showModalBottomSheet<AcademicTerm>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (context) => _TermPicker(account: account, forImport: forImport),
);

class _TermPicker extends StatefulWidget {
  const _TermPicker({required this.account, required this.forImport});
  final StoredScheduleAccount account;
  final bool forImport;

  @override
  State<_TermPicker> createState() => _TermPickerState();
}

class _TermPickerState extends State<_TermPicker> {
  String? _year;
  String? _term;
  final _manualYear = TextEditingController();
  ZhengfangSemester? _manualSemester;
  String? _yearError;
  String? _semesterError;

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

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    final catalog = account.catalog;
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
            Text('选择学期', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              widget.forImport
                  ? '请选择要导入的学年和学期。也可以手动填写，不依赖学校页面提供选项。'
                  : '已保存的学期可离线查看。其他学期可手动选择，再点击导入课表。',
            ),
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
                items: [
                  for (final term in catalog.termOptions)
                    DropdownMenuItem(value: term.code, child: Text(term.label)),
                ],
                onChanged: (value) => setState(() => _term = value),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _year == null || _term == null
                    ? null
                    : () {
                        final year = catalog.yearOptions.firstWhere(
                          (item) => item.code == _year,
                        );
                        final term = catalog.termOptions.firstWhere(
                          (item) => item.code == _term,
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
            const SizedBox(height: 12),
            Text('手动选择学年学期', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
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
}) => showModalBottomSheet<int>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
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
                  Text('选择教学周', style: Theme.of(context).textTheme.titleLarge),
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
