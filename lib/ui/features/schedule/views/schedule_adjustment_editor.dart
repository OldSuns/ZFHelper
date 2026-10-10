import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zf_core/zf_core.dart';

import '../../../core/adaptive_sheet.dart';
import '../../../core/app_theme.dart';
import '../view_models/schedule_labels.dart';
import '../view_models/timetable_view_model.dart';
import 'schedule_adjustment_widgets.dart';

part 'schedule_adjustment_course_fields.dart';
part 'schedule_adjustment_preview.dart';

Future<bool> showScheduleAdjustmentEditor(
  BuildContext context,
  TimetableViewModel viewModel, {
  ScheduleEntry? entry,
  int? week,
  int? weekday,
  ScheduleOccurrenceOverride? sourceOverride,
  ScheduleChangeKind initialKind = ScheduleChangeKind.reschedule,
}) async {
  final editing = viewModel.adjustmentContext;
  if (editing == null) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('请先选择一份已保存的课表。')));
    return false;
  }
  final initialWeek =
      sourceOverride?.sourceWeek ?? week ?? viewModel.selectedWeek;
  final initialWeekday = sourceOverride != null
      ? sourceOverride.source.weekday
      : entry != null
      ? entry.weekday
      : weekday ?? viewModel.today.weekday;
  final currentWeek = viewModel.currentPosition.week;
  final weekCount = viewModel.weekCount;
  final account = viewModel.account!.account;
  final accountLabel = '${account.schoolName} · ${account.accountName}';
  try {
    if (sourceOverride != null) {
      ScheduleOccurrenceSelection.captureSource(
        baseline: editing.baseline,
        overrides: editing.overrides,
        override: sourceOverride,
      );
    } else if (entry != null) {
      ScheduleOccurrenceSelection.capture(
        baseline: editing.baseline,
        overrides: editing.overrides,
        entry: entry,
        week: initialWeek,
      );
    }
  } on ScheduleOccurrenceException catch (error) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(error.message)));
    return false;
  }
  final saved = await showAdaptiveSheet<bool>(
    context: context,
    maxWidth: 760,
    builder: (context) => _ScheduleAdjustmentEditor(
      baseline: editing.baseline,
      imported: editing.imported,
      effective: editing.effective,
      settings: editing.settings,
      accountLabel: accountLabel,
      initialWeek: initialWeek,
      initialWeekday: initialWeekday,
      initialEntry: entry,
      initialSource: sourceOverride,
      initialKind: sourceOverride == null
          ? initialKind
          : ScheduleChangeKind.makeup,
      currentWeek: currentWeek,
      weekCount: weekCount,
      onSave: (changes) async =>
          await viewModel.applyOccurrenceChanges(
            changes,
            target: editing.target,
          )
          ? null
          : viewModel.data.failure?.message ?? '调整未能保存，请重试。',
    ),
  );
  return saved == true;
}

class _ScheduleAdjustmentEditor extends StatefulWidget {
  const _ScheduleAdjustmentEditor({
    required this.baseline,
    required this.imported,
    required this.effective,
    required this.settings,
    required this.accountLabel,
    required this.initialWeek,
    required this.initialWeekday,
    required this.initialEntry,
    required this.initialSource,
    required this.initialKind,
    required this.currentWeek,
    required this.weekCount,
    required this.onSave,
  });

  final ScheduleSnapshot baseline;
  final ScheduleSnapshot imported;
  final ScheduleSnapshot effective;
  final ScheduleSettings settings;
  final String accountLabel;
  final int initialWeek;
  final int? initialWeekday;
  final ScheduleEntry? initialEntry;
  final ScheduleOccurrenceOverride? initialSource;
  final ScheduleChangeKind initialKind;
  final int? currentWeek;
  final int weekCount;
  final Future<String?> Function(List<ScheduleOccurrenceChange>) onSave;

  @override
  State<_ScheduleAdjustmentEditor> createState() =>
      _ScheduleAdjustmentEditorState();
}

class _ScheduleAdjustmentEditorState extends State<_ScheduleAdjustmentEditor> {
  final _form = GlobalKey<FormState>();
  final _previewKey = GlobalKey();
  final _drafts = <String, _AdjustmentDraft>{};
  late ScheduleChangeKind _kind;
  late int _sourceWeek;
  late int? _sourceWeekday;
  late int _targetWeek;
  int? _targetWeekday;
  late bool _wholeDay;
  late bool _originalBasis;
  bool _saving = false;
  String? _saveError;
  String? _previewError;
  _AdjustmentPreview? _preview;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
    _sourceWeek = _targetWeek = widget.initialWeek;
    _sourceWeekday = widget.initialWeekday;
    _wholeDay = widget.initialEntry == null && widget.initialSource == null;
    _originalBasis =
        _kind == ScheduleChangeKind.makeup && widget.initialEntry == null;
    _prepareDrafts();
    _refreshPreview();
  }

  @override
  void dispose() {
    for (final draft in _drafts.values) {
      draft.dispose();
    }
    super.dispose();
  }

  List<_AdjustmentSource> get _sources {
    final original = _kind == ScheduleChangeKind.makeup && _originalBasis;
    final entries = original
        ? widget.baseline.entries
        : widget.effective.entries;
    final sources = <_AdjustmentSource>[];
    for (final entry in entries) {
      if (entry.weekday != _sourceWeekday || !entry.occursInWeek(_sourceWeek)) {
        continue;
      }
      final owner = original
          ? widget.settings.occurrenceOverrides
                .where((value) => value.key == (entry.id, _sourceWeek))
                .firstOrNull
          : null;
      final effective = owner == null && original
          ? widget.effective.entries.singleWhere(
              (value) => value.id == entry.id,
            )
          : entry;
      sources.add(
        _AdjustmentSource(entry: effective, week: _sourceWeek, owner: owner),
      );
    }
    sources.sort((left, right) {
      final period = (left.entry.startPeriod ?? 0).compareTo(
        right.entry.startPeriod ?? 0,
      );
      return period == 0 ? left.entry.name.compareTo(right.entry.name) : period;
    });
    return sources;
  }

  void _prepareDrafts() {
    for (final source in _sources) {
      _drafts.putIfAbsent(
        source.key,
        () => _AdjustmentDraft(
          source,
          selected:
              _wholeDay ||
              source.entry.id == widget.initialEntry?.id ||
              source.owner?.key == widget.initialSource?.key &&
                  source.owner != null,
        ),
      );
    }
  }

  void _update(VoidCallback change) {
    setState(() {
      change();
      _saveError = null;
      _prepareDrafts();
      _refreshPreview();
    });
  }

  void _refreshPreview() {
    _preview = null;
    _previewError = null;
    try {
      final changes = [
        for (final source in _sources)
          if (_wholeDay || _drafts[source.key]!.selected)
            _changeFor(_drafts[source.key]!),
      ];
      if (changes.isEmpty) {
        _previewError = '请选择需要调整的课程。';
        return;
      }
      _preview = _AdjustmentPreview.create(
        baseline: widget.baseline,
        imported: widget.imported,
        settings: widget.settings,
        changes: changes,
      );
    } on ScheduleOccurrenceException catch (error) {
      _previewError = error.message;
    } on FormatException catch (error) {
      _previewError = error.message;
    }
  }

  ScheduleOccurrenceChange _changeFor(_AdjustmentDraft draft) {
    final first = _wholeDay ? null : draft.selectedStart;
    final last = _wholeDay ? null : draft.selectedEnd;
    final source = draft.source;
    final selection = source.owner == null
        ? ScheduleOccurrenceSelection.capture(
            baseline: widget.baseline,
            overrides: widget.settings.occurrenceOverrides,
            entry: source.entry,
            week: source.week,
            startPeriod: first,
            endPeriod: last,
          )
        : ScheduleOccurrenceSelection.captureSource(
            baseline: widget.baseline,
            overrides: widget.settings.occurrenceOverrides,
            override: source.owner!,
            startPeriod: first,
            endPeriod: last,
          );
    final cancel = _kind == ScheduleChangeKind.cancel;
    return ScheduleOccurrenceChange(
      selection: selection,
      kind: _kind,
      targetWeek: cancel ? null : _targetWeek,
      targetWeekday: cancel ? null : _targetWeekday,
      targetStartPeriod: cancel ? null : draft.targetStart,
      location: cancel || !draft.changeLocation ? null : draft.location.text,
    );
  }

  void _setWholeDay(bool value) => _update(() {
    if (_wholeDay && !value) {
      for (final source in _sources) {
        _drafts[source.key]!.selected = true;
      }
    }
    _wholeDay = value;
  });

  Future<void> _save() async {
    if (_saving) return;
    final invalid = _form.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      await Scrollable.ensureVisible(invalid.first.context, alignment: .1);
      return;
    }
    _update(() {});
    final preview = _preview;
    if (preview == null) {
      final target = _previewKey.currentContext;
      if (target != null) await Scrollable.ensureVisible(target);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      final error = await widget.onSave(preview.changes);
      if (!mounted) return;
      if (error == null) {
        Navigator.of(context).pop(true);
      } else {
        setState(() => _saveError = error);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final target = _previewKey.currentContext;
          if (mounted && target != null) Scrollable.ensureVisible(target);
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<bool>(
    canPop: !_saving,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .9,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(),
              const Divider(height: 1),
              Flexible(
                child: FocusScope(
                  canRequestFocus: !_saving,
                  child: AbsorbPointer(
                    absorbing: _saving,
                    child: Form(
                      key: _form,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.all(AppLayout.pagePadding),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _content(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? '正在保存…' : '保存本次$_kindLabel'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  String get _kindLabel => switch (_kind) {
    ScheduleChangeKind.reschedule => '调课',
    ScheduleChangeKind.cancel => '停课',
    ScheduleChangeKind.makeup => '补课',
  };

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '调课 / 停课 / 补课',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        IconButton(
          tooltip: '取消调整',
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );

  List<Widget> _content() => [
    Text(widget.accountLabel),
    const SizedBox(height: 8),
    Text(
      widget.effective.term.label,
      style: Theme.of(context).textTheme.titleMedium,
    ),
    const SizedBox(height: 8),
    const Text('调整只保存到本地课表。选中的课程会在一次保存中一起更新。'),
    if (widget.effective.calendar.firstWeekMonday == null) ...[
      const SizedBox(height: 8),
      const Text('尚未设置校历，将按教学周和星期确定安排。'),
    ],
    const SizedBox(height: 16),
    _kindPicker(),
    const SizedBox(height: AppLayout.sectionGap),
    if (_kind == ScheduleChangeKind.makeup) ...[
      _basisPicker(),
      const SizedBox(height: 16),
    ],
    _dayPicker(source: true),
    const SizedBox(height: 16),
    _scopePicker(),
    const SizedBox(height: 16),
    ..._courseFields(),
    const SizedBox(height: AppLayout.sectionGap),
    if (_kind != ScheduleChangeKind.cancel) ...[
      _dayPicker(source: false),
      const SizedBox(height: AppLayout.sectionGap),
    ],
    _previewContent(),
  ];

  Widget _kindPicker() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final kind in ScheduleChangeKind.values)
        ChoiceChip(
          materialTapTargetSize: MaterialTapTargetSize.padded,
          label: Text(switch (kind) {
            ScheduleChangeKind.reschedule => '调课',
            ScheduleChangeKind.cancel => '停课',
            ScheduleChangeKind.makeup => '补课',
          }),
          selected: kind == _kind,
          onSelected: (_) => _update(() => _kind = kind),
        ),
    ],
  );

  Widget _basisPicker() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('补课来源', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            label: const Text('当前安排'),
            selected: !_originalBasis,
            onSelected: (_) => _update(() => _originalBasis = false),
          ),
          ChoiceChip(
            label: const Text('原始安排'),
            selected: _originalBasis,
            onSelected: (_) => _update(() => _originalBasis = true),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        _originalBasis
            ? '按调整前的课程选择要补的节次，已停课的安排也在这里。现有课程会保留。'
            : '在当前安排之外增加一次课程；现有课程会保留。',
      ),
    ],
  );

  Widget _scopePicker() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      ChoiceChip(
        label: Text(_sourceWeekday == null ? '全部课程' : '整天课程'),
        selected: _wholeDay,
        onSelected: (_) => _setWholeDay(true),
      ),
      ChoiceChip(
        label: const Text('选择课程 / 节次'),
        selected: !_wholeDay,
        onSelected: (_) => _setWholeDay(false),
      ),
    ],
  );

  Widget _dayPicker({required bool source}) => ScheduleAdjustmentDayPicker(
    label: source
        ? '来源安排'
        : _kind == ScheduleChangeKind.makeup
        ? '补课日期'
        : '调至日期',
    snapshot: source ? widget.baseline : widget.effective,
    week: source ? _sourceWeek : _targetWeek,
    weekday: source ? _sourceWeekday : _targetWeekday,
    weekCount: math.max(
      math.max(widget.weekCount, widget.baseline.observedMaxWeek),
      math.max(_sourceWeek, _targetWeek),
    ),
    currentWeek: widget.currentWeek,
    allowUnscheduled: source,
    onWeekChanged: (value) => _update(() {
      if (source) {
        _sourceWeek = value;
      } else {
        _targetWeek = value;
      }
    }),
    onWeekdayChanged: (value) => _update(() {
      if (source) {
        _sourceWeekday = value;
      } else {
        _targetWeekday = value;
      }
    }),
  );

  List<Widget> _courseFields() {
    final sources = _sources;
    if (sources.isEmpty) {
      return [
        ScheduleAdjustmentNotice(
          message: _kind == ScheduleChangeKind.makeup && !_originalBasis
              ? '这一天没有当前课程；如需为已停课程补课，可切换到原始安排。'
              : '这个教学周和星期没有可选课程。',
        ),
      ];
    }
    return [
      Text(
        _wholeDay
            ? '已选${_sourceWeekday == null ? '全部' : '当天全部'} ${sources.length} 项安排，默认保留各自的节次和地点。'
            : '选中课程后，可展开设置需要调整的连续节次。',
      ),
      const SizedBox(height: 12),
      for (final source in sources) ...[
        _AdjustmentCourseFields(
          key: ValueKey(source.key),
          draft: _drafts[source.key]!,
          wholeDay: _wholeDay,
          kind: _kind,
          onChanged: () => _update(() {}),
        ),
        const SizedBox(height: 12),
      ],
    ];
  }

  Widget _previewContent() => Column(
    key: _previewKey,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('保存前预览', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      if (_saveError != null) ...[
        ScheduleAdjustmentNotice(message: _saveError!, isError: true),
        const SizedBox(height: 12),
      ],
      if (_previewError != null)
        ScheduleAdjustmentNotice(message: _previewError!)
      else if (_preview case final value?)
        _AdjustmentPreviewView(preview: value),
    ],
  );
}
