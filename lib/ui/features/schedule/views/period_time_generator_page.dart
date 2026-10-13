import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zf_core/zf_core.dart';

import 'period_time_edit_dialog.dart';
import 'period_time_fields.dart';

class PeriodTimeGeneratorPage extends StatefulWidget {
  const PeriodTimeGeneratorPage({
    super.key,
    required this.initialPlan,
    required this.campus,
  });

  final PeriodTimePlan initialPlan;
  final String? campus;

  @override
  State<PeriodTimeGeneratorPage> createState() =>
      _PeriodTimeGeneratorPageState();
}

class _PeriodTimeGeneratorPageState extends State<PeriodTimeGeneratorPage> {
  static const _contentWidth = 1120.0;
  static const _buttonStyle = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(0, 48)),
  );

  final _countsForm = GlobalKey<FormState>();
  final _durationsForm = GlobalKey<FormState>();
  final _sessions = {
    for (final session in PeriodSession.values) session: _SessionFields(),
  };
  final _classMinutes = TextEditingController();
  final _breakMinutes = TextEditingController();
  late PeriodTimePlan _preview;
  bool _hasPreview = false;
  bool _stale = false;
  String? _error;
  String? _previewError;
  String? _previewNote;
  // 预览里是否有手动微调：自动重新生成会丢弃它们，需要明确告知用户。
  bool _manualEdits = false;

  String? get _campus => normalizePeriodCampus(widget.campus);

  @override
  void initState() {
    super.initState();
    _preview = widget.initialPlan;
    final periods = _preview.periodsForCampus(_campus);
    for (final section in _preview.sections.where((s) => s.campus == _campus)) {
      final fields = _sessions[section.session]!;
      fields.count.text = '${section.lastPeriod - section.firstPeriod + 1}';
      final first = periods.where((p) => p.number == section.firstPeriod);
      if (first.length == 1) {
        fields.start.text = periodClock(first.single.startMinutes);
      }
    }
    _classMinutes.text = _uniform(
      periods.map((p) => p.endMinutes - p.startMinutes),
    );
    final gaps = <int>[];
    for (var index = 1; index < periods.length; index++) {
      final previous = periods[index - 1];
      final current = periods[index];
      final previousSection = _preview.sectionFor(previous);
      if (current.number == previous.number + 1 &&
          previousSection == _preview.sectionFor(current)) {
        gaps.add(current.startMinutes - previous.endMinutes);
      }
    }
    _breakMinutes.text = _uniform(gaps);
    _previewError = _validationError(_preview);
  }

  String _uniform(Iterable<int> values) {
    final distinct = values.toSet();
    return distinct.length == 1 && distinct.single >= 0
        ? '${distinct.single}'
        : '';
  }

  String? _validationError(PeriodTimePlan plan) {
    try {
      plan.validate();
      return null;
    } on PeriodTimeException catch (error) {
      return error.message;
    }
  }

  @override
  void dispose() {
    for (final fields in _sessions.values) {
      fields.count.dispose();
      fields.start.dispose();
      fields.longAfter.dispose();
      fields.longMinutes.dispose();
    }
    for (final controller in [_classMinutes, _breakMinutes]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _changed([String? value]) {
    setState(() {
      _stale = _hasPreview;
      _error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _generate();
    });
  }

  void _generate({bool apply = false}) {
    var valid = _countsForm.currentState!.validate();
    valid = _durationsForm.currentState!.validate() && valid;
    for (final fields in _sessions.values) {
      if ((int.tryParse(fields.count.text) ?? 0) > 0) {
        valid = fields.timeForm.currentState!.validate() && valid;
      }
    }
    if (!valid) {
      setState(() {
        _error = '请检查标出的设置。';
        _stale = _hasPreview;
      });
      return;
    }
    try {
      final enabled = _sessions.entries
          .where((entry) => (int.tryParse(entry.value.count.text) ?? 0) > 0)
          .toList();
      if (enabled.isEmpty) {
        throw const PeriodTimeException('请至少为一个时段填写节数。');
      }
      final plan = widget.initialPlan.generate(
        campus: _campus,
        inputs: [
          for (final entry in enabled)
            PeriodSectionInput(
              session: entry.key,
              count: int.parse(entry.value.count.text),
              startMinutes: parsePeriodClock(entry.value.start.text)!,
              longBreakAfter: entry.value.breakMode == _LongBreakMode.fixed
                  ? int.parse(entry.value.longAfter.text)
                  : null,
              longBreakEvery: entry.value.breakMode == _LongBreakMode.repeating
                  ? int.parse(entry.value.longAfter.text)
                  : null,
              longBreakMinutes: entry.value.breakMode == _LongBreakMode.none
                  ? null
                  : int.parse(entry.value.longMinutes.text),
            ),
        ],
        classMinutes: int.parse(_classMinutes.text),
        breakMinutes: int.parse(_breakMinutes.text),
      );
      final error = _validationError(plan);
      if (error != null) throw PeriodTimeException(error);
      if (apply) {
        Navigator.pop(context, plan);
      } else {
        _showPreview(
          plan,
          note: _manualEdits ? '已按最新参数重新生成，之前的手动调整未保留。' : null,
        );
      }
    } on PeriodTimeException catch (error) {
      setState(() {
        _error = error.message;
        _stale = _hasPreview;
      });
    }
  }

  void _apply() {
    if (_hasPreview && !_stale && _previewError == null) {
      Navigator.pop(context, _preview);
    } else {
      _generate(apply: true);
    }
  }

  void _showPreview(PeriodTimePlan plan, {String? note, bool manual = false}) {
    final error = _validationError(plan);
    setState(() {
      _preview = plan;
      _previewError = error;
      _previewNote = note;
      _error = null;
      _hasPreview = true;
      _stale = false;
      _manualEdits = manual;
    });
  }

  Future<void> _editPreviewBreak(PeriodTime period, PeriodTime next) async {
    final section = _preview.sectionFor(period);
    if (section == null || _preview.sectionFor(next) != section) return;
    final gap = next.startMinutes - period.endMinutes;
    await showDialog<void>(
      context: context,
      builder: (_) => PeriodValueDialog(
        title: '调整第 ${period.number} 节后的课间',
        label: '课间（分钟）',
        description: '调整后，本时段后续课节会同步移动。',
        initialValue: '$gap',
        numeric: true,
        onApply: (value) {
          try {
            _showPreview(
              _preview.changeBreak(
                afterNumber: period.number,
                campus: period.campus,
                minutes: int.parse(value),
              ),
              note: '已修改第 ${period.number} 节后的课间。',
              manual: true,
            );
            return null;
          } on FormatException {
            return '请输入有效的分钟数';
          } on PeriodTimeException catch (error) {
            return error.message;
          }
        },
      ),
    );
  }

  Future<void> _editPreviewPeriod(PeriodTime period) async {
    final result = await showDialog<PeriodTimePlan>(
      context: context,
      builder: (_) => _PreviewPeriodEditDialog(plan: _preview, period: period),
    );
    if (!mounted || result == null) return;
    _showPreview(result, note: '已修改第 ${period.number} 节时间。', manual: true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('智能排布作息')),
    body: SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentWidth),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                final configuration = _configuration(context);
                final preview = _previewPanel(context);
                return constraints.maxWidth >= 880 * scale
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 6, child: configuration),
                          const SizedBox(width: 16),
                          Expanded(flex: 5, child: preview),
                        ],
                      )
                    : Column(
                        children: [
                          configuration,
                          const SizedBox(height: 16),
                          preview,
                        ],
                      );
              },
            ),
          ),
        ),
      ),
    ),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentWidth),
            child: Align(
              alignment: Alignment.centerRight,
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: _pair(
                  OutlinedButton(
                    style: _buttonStyle,
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    style: _buttonStyle,
                    onPressed: _apply,
                    child: const Text('应用到作息草稿'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _configuration(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panel([
          Row(
            children: [
              Expanded(
                child: Text(
                  _campus ?? '通用作息',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const Chip(label: Text('实时预览')),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '生成时按上午、下午、晚上从第 1 节连续排布，仅修改当前校区。节数留空或填 0 可停用该时段。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _message(context, _error!, error: true),
          ],
        ]),
        _sectionTitle(context, '时长规则'),
        _panel([
          Form(
            key: _durationsForm,
            child: Column(
              children: [
                _pair(
                  _numberField(_classMinutes, '每节课（分钟）'),
                  _numberField(_breakMinutes, '课间（分钟）', allowZero: true),
                ),
                const SizedBox(height: 8),
                Text(
                  '已有时长不统一或缺少记录时留空，请填写生成规则。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ]),
        _sectionTitle(context, '时段设置'),
        Form(
          key: _countsForm,
          child: Column(
            children: [
              for (final entry in _sessions.entries) ...[
                _sessionPanel(context, entry),
                if (entry.key != _sessions.keys.last)
                  const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _sessionPanel(
    BuildContext context,
    MapEntry<PeriodSession, _SessionFields> entry,
  ) {
    final theme = Theme.of(context);
    final fields = entry.value;
    final count = int.tryParse(fields.count.text) ?? 0;
    final start = parsePeriodClock(fields.start.text);
    final modeText = switch (fields.breakMode) {
      _LongBreakMode.none => '统一课间',
      _LongBreakMode.fixed =>
        '第 ${fields.longAfter.text.isEmpty ? '?' : fields.longAfter.text} 节后',
      _LongBreakMode.repeating =>
        '每 ${fields.longAfter.text.isEmpty ? '?' : fields.longAfter.text} 节',
    };
    final summary = count <= 0
        ? '不排课'
        : '$count 节 · ${start == null ? '未设置开始时间' : '${periodClock(start)} 起'} · $modeText';
    return _panel([
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _sessionIcon(entry.key),
            size: 20,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              periodSessionLabel(entry.key),
              style: theme.textTheme.titleSmall,
            ),
          ),
          Flexible(
            child: Text(
              summary,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _pair(
        _numberField(fields.count, '节数', allowZero: true, allowEmpty: true),
        Form(
          key: fields.timeForm,
          child: PeriodClockField(
            controller: fields.start,
            label: '首课开始',
            onChanged: _changed,
          ),
        ),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<_LongBreakMode>(
        key: ValueKey('session-break-${entry.key.name}'),
        initialValue: fields.breakMode,
        isExpanded: true,
        decoration: const InputDecoration(labelText: '课间安排', isDense: true),
        items: const [
          DropdownMenuItem(value: _LongBreakMode.none, child: Text('统一课间')),
          DropdownMenuItem(
            value: _LongBreakMode.fixed,
            child: Text('指定课间（第几节后单独调整）'),
          ),
          DropdownMenuItem(
            value: _LongBreakMode.repeating,
            child: Text('循环课间（如 5、10、5、10 分钟）'),
          ),
        ],
        onChanged: (value) {
          setState(() {
            fields.breakMode = value ?? _LongBreakMode.none;
          });
          _changed();
        },
      ),
      if (fields.breakMode != _LongBreakMode.none) ...[
        const SizedBox(height: 12),
        _pair(
          _numberField(
            fields.longAfter,
            fields.breakMode == _LongBreakMode.fixed ? '第几节后' : '每隔几节',
          ),
          _numberField(fields.longMinutes, '休息时长（分钟）', allowZero: true),
        ),
      ],
    ]);
  }

  Widget _sectionTitle(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _numberField(
    TextEditingController controller,
    String label, {
    bool allowZero = false,
    bool allowEmpty = false,
  }) => TextFormField(
    controller: controller,
    keyboardType: TextInputType.number,
    textInputAction: TextInputAction.next,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(4),
    ],
    decoration: InputDecoration(
      labelText: label,
      isDense: true,
      errorMaxLines: 2,
    ),
    onChanged: _changed,
    validator: (value) {
      if (allowEmpty && (value?.isEmpty ?? true)) return null;
      final number = int.tryParse(value ?? '');
      if (number == null || number < (allowZero ? 0 : 1)) {
        return allowZero ? '请填写 0 或正整数' : '请填写正整数';
      }
      return null;
    },
  );

  Widget _previewPanel(BuildContext context) {
    final theme = Theme.of(context);
    final periods = _preview.periodsForCampus(_campus);
    return _panel([
      Row(
        children: [
          Expanded(
            child: Text(
              _hasPreview ? '作息预览' : '当前作息',
              style: theme.textTheme.titleMedium,
            ),
          ),
          if (_hasPreview)
            Text(
              '${periods.length} 节',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      const SizedBox(height: 12),
      if (_stale) ...[
        _message(
          context,
          _error == null ? '预览正在根据参数更新。' : '参数有误，预览仍是上次生成的结果，修正后自动更新。',
        ),
        const SizedBox(height: 12),
      ],
      if (_previewError != null) ...[
        _message(context, _previewError!, error: true),
        const SizedBox(height: 12),
      ],
      if (_previewNote != null) ...[
        Text(
          _previewNote!,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 12),
      ],
      if (periods.isEmpty)
        Text(
          '尚无作息，请先配置时段并生成预览。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        )
      else
        for (var index = 0; index < periods.length; index++)
          _previewPeriodRow(context, periods, index),
    ]);
  }

  Widget _previewPeriodRow(
    BuildContext context,
    List<PeriodTime> periods,
    int index,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final compact = constraints.maxWidth < 340 * scale;
        final axisWidth = 62 * scale;
        final period = periods[index];
        final section = _preview.sectionFor(period);
        final previous = index == 0 ? null : periods[index - 1];
        final next = index + 1 < periods.length ? periods[index + 1] : null;
        final nextSection = next == null ? null : _preview.sectionFor(next);
        final gap = next == null ? null : next.startMinutes - period.endMinutes;
        final sameSection = section != null && section == nextSection;
        final newSection =
            index == 0 || _preview.sectionFor(previous!) != section;
        final widgets = <Widget>[];

        if (newSection) {
          if (index > 0) widgets.add(const Divider(height: 24));
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (section != null) ...[
                        Icon(
                          _sessionIcon(section.session),
                          size: 17,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        section == null
                            ? '未划分时段'
                            : periodSessionLabel(section.session),
                        style: theme.textTheme.titleSmall,
                      ),
                    ],
                  ),
                  if (section != null)
                    Text(
                      _sectionSummary(periods, section),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          );
        }

        widgets.add(
          InkWell(
            onTap: () => _editPreviewPeriod(period),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 0, 2),
              child: Row(
                children: [
                  Expanded(
                    child: compact
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '第 ${period.number} 节',
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${periodClock(period.startMinutes)} – ${periodClock(period.endMinutes)}',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              SizedBox(
                                width: axisWidth,
                                child: Text(
                                  '第 ${period.number} 节',
                                  style: theme.textTheme.titleSmall,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${periodClock(period.startMinutes)} – ${periodClock(period.endMinutes)}',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                  ),
                  IconButton(
                    tooltip: '修改第 ${period.number} 节',
                    onPressed: () => _editPreviewPeriod(period),
                    icon: const Icon(Icons.edit_outlined, size: 20),
                  ),
                ],
              ),
            ),
          ),
        );

        if (gap != null) {
          widgets.add(
            InkWell(
              key: ValueKey('period-break-${period.number}'),
              borderRadius: BorderRadius.circular(8),
              onTap: sameSection
                  ? () => _editPreviewBreak(period, next!)
                  : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: EdgeInsets.only(
                    left: compact ? 4 : axisWidth + 12,
                    top: 8,
                    bottom: 8,
                    right: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        gap < 0
                            ? Icons.error_outline
                            : Icons.more_time_outlined,
                        size: 16,
                        color: gap < 0
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          gap < 0
                              ? '与下节重叠 ${-gap} 分钟'
                              : '${sameSection ? '课间' : '距下一节'} $gap 分钟',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: gap < 0
                                ? theme.colorScheme.error
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (sameSection)
                        Tooltip(
                          message: '调整第 ${period.number} 节后的课间',
                          child: Icon(
                            Icons.tune,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
          if (sameSection) widgets.add(const Divider(height: 1));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: widgets,
        );
      },
    );
  }

  String _sectionSummary(List<PeriodTime> periods, PeriodTimeSection section) {
    final sectionPeriods = periods
        .where(
          (period) =>
              period.number >= section.firstPeriod &&
              period.number <= section.lastPeriod,
        )
        .toList();
    if (sectionPeriods.isEmpty) {
      return '第 ${section.firstPeriod}–${section.lastPeriod} 节';
    }
    return '第 ${section.firstPeriod}–${section.lastPeriod} 节 · '
        '${periodClock(sectionPeriods.first.startMinutes)}–'
        '${periodClock(sectionPeriods.last.endMinutes)}';
  }

  Widget _panel(List<Widget> children) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );

  Widget _pair(Widget first, Widget second) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      return constraints.maxWidth >= 300 * scale
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: first),
                const SizedBox(width: 12),
                Expanded(child: second),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [first, const SizedBox(height: 12), second],
            );
    },
  );

  Widget _message(BuildContext context, String text, {bool error = false}) =>
      Semantics(
        liveRegion: true,
        child: Text(
          text,
          style: TextStyle(
            color: error
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.primary,
          ),
        ),
      );
}

IconData _sessionIcon(PeriodSession session) => switch (session) {
  PeriodSession.morning => Icons.wb_sunny_outlined,
  PeriodSession.afternoon => Icons.wb_twilight_outlined,
  PeriodSession.evening => Icons.nights_stay_outlined,
};

class _SessionFields {
  final count = TextEditingController();
  final start = TextEditingController();
  final longAfter = TextEditingController();
  final longMinutes = TextEditingController();
  final timeForm = GlobalKey<FormState>();
  var breakMode = _LongBreakMode.none;
}

enum _LongBreakMode { none, fixed, repeating }

class _PreviewPeriodEditDialog extends StatefulWidget {
  const _PreviewPeriodEditDialog({required this.plan, required this.period});

  final PeriodTimePlan plan;
  final PeriodTime period;

  @override
  State<_PreviewPeriodEditDialog> createState() =>
      _PreviewPeriodEditDialogState();
}

class _PreviewPeriodEditDialogState extends State<_PreviewPeriodEditDialog> {
  final _form = GlobalKey<FormState>();
  late final _start = TextEditingController(
    text: periodClock(widget.period.startMinutes),
  );
  late final _end = TextEditingController(
    text: periodClock(widget.period.endMinutes),
  );
  String? _error;
  bool _shiftFollowing = true;

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  void _apply() {
    if (!_form.currentState!.validate()) return;
    try {
      final result = widget.plan.edit(
        number: widget.period.number,
        campus: widget.period.campus,
        startMinutes: parsePeriodClock(_start.text)!,
        endMinutes: parsePeriodClock(_end.text)!,
        shiftFollowing: _shiftFollowing,
      );
      Navigator.pop(context, result);
    } on PeriodTimeException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('修改第 ${widget.period.number} 节'),
    scrollable: true,
    content: SizedBox(
      width: 400,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('修改后，本时段后续节次会同步移动，保留原有课长和课间。'),
            const SizedBox(height: 16),
            PeriodClockField(
              key: const ValueKey('preview-period-start'),
              controller: _start,
              label: '开始时间',
            ),
            const SizedBox(height: 16),
            PeriodClockField(
              key: const ValueKey('preview-period-end'),
              controller: _end,
              label: '结束时间',
              allowDayEnd: true,
              validator: (value) {
                final start = parsePeriodClock(_start.text);
                final end = parsePeriodClock(value ?? '');
                return start != null && end != null && end <= start
                    ? '结束时间必须晚于开始时间'
                    : null;
              },
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _shiftFollowing,
              onChanged: (value) =>
                  setState(() => _shiftFollowing = value ?? true),
              title: const Text('同步移动本时段后续课节'),
              subtitle: const Text('保留后续课节之间原有的课长和课间。'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const ValueKey('preview-period-apply'),
        onPressed: _apply,
        child: const Text('应用修改'),
      ),
    ],
  );
}
