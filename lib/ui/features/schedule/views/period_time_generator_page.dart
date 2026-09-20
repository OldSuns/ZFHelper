import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zf_core/zf_core.dart';

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
  final _longEvery = TextEditingController();
  final _longMinutes = TextEditingController();
  late PeriodTimePlan _preview;
  bool _longBreak = false;
  bool _hasPreview = false;
  bool _stale = false;
  String? _error;
  String? _previewError;
  String? _previewNote;

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
    }
    for (final controller in [
      _classMinutes,
      _breakMinutes,
      _longEvery,
      _longMinutes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _changed([String? value]) => setState(() {
    _stale = _hasPreview;
    _error = null;
  });

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
            ),
        ],
        classMinutes: int.parse(_classMinutes.text),
        breakMinutes: int.parse(_breakMinutes.text),
        longBreakEvery: _longBreak ? int.parse(_longEvery.text) : null,
        longBreakMinutes: _longBreak ? int.parse(_longMinutes.text) : null,
      );
      final error = _validationError(plan);
      if (error != null) throw PeriodTimeException(error);
      if (apply) {
        Navigator.pop(context, plan);
      } else {
        _showPreview(plan);
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

  void _showPreview(PeriodTimePlan plan, {String? note}) {
    final error = _validationError(plan);
    setState(() {
      _preview = plan;
      _previewError = error;
      _previewNote = note;
      _error = null;
      _hasPreview = true;
      _stale = false;
    });
  }

  Future<void> _editPreviewPeriod(PeriodTime period) async {
    final result = await showDialog<PeriodTimePlan>(
      context: context,
      builder: (_) => _PreviewPeriodEditDialog(plan: _preview, period: period),
    );
    if (!mounted || result == null) return;
    _showPreview(result, note: '已修改第 ${period.number} 节时间。');
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

  Widget _configuration(BuildContext context) => _panel([
    Row(
      children: [
        Expanded(
          child: Text(
            _campus ?? '通用作息',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        FilledButton.icon(
          style: _buttonStyle,
          onPressed: _generate,
          icon: const Icon(Icons.auto_fix_high_outlined),
          label: const Text('生成预览'),
        ),
      ],
    ),
    const SizedBox(height: 8),
    const Text('生成时按上午、下午、晚上从第 1 节连续排布，仅修改当前校区。节数留空或填 0 可停用该时段。'),
    const SizedBox(height: 16),
    Form(
      key: _countsForm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in _sessions.entries) ...[
            Text(
              periodSessionLabel(entry.key),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _pair(
              _numberField(
                entry.value.count,
                '节数',
                allowZero: true,
                allowEmpty: true,
              ),
              Form(
                key: entry.value.timeForm,
                child: PeriodClockField(
                  controller: entry.value.start,
                  label: '首课开始',
                  onChanged: _changed,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Form(
            key: _durationsForm,
            child: Column(
              children: [
                _pair(
                  _numberField(_classMinutes, '每节课（分钟）'),
                  _numberField(_breakMinutes, '课间（分钟）', allowZero: true),
                ),
                const SizedBox(height: 8),
                const Text('已有时长不统一或缺少记录时留空，请填写生成规则。'),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('周期性长课间'),
                  subtitle: const Text('在每个时段内重新计数'),
                  value: _longBreak,
                  onChanged: (value) {
                    _longBreak = value;
                    _changed();
                  },
                ),
                if (_longBreak)
                  _pair(
                    _numberField(_longEvery, '每隔几节'),
                    _numberField(_longMinutes, '休息（分钟）', allowZero: true),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
    const SizedBox(height: 16),
    if (_error != null) ...[
      _message(context, _error!, error: true),
      const SizedBox(height: 12),
    ],
  ]);

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
    final periods = _preview.periodsForCampus(_campus);
    return _panel([
      Text(
        _hasPreview ? '作息预览' : '当前作息',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 12),
      if (_stale) ...[
        _message(context, '参数已修改，请重新生成预览。生成后的具体节次仍可直接修改。'),
        const SizedBox(height: 12),
      ],
      if (_previewError != null) ...[
        _message(context, _previewError!, error: true),
        const SizedBox(height: 12),
      ],
      if (_previewNote != null) ...[
        Text(_previewNote!),
        const SizedBox(height: 12),
      ],
      if (periods.isEmpty) const Text('尚无作息，请先配置时段并生成预览。'),
      ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: periods.length,
        itemBuilder: (context, index) {
          final period = periods[index];
          final section = _preview.sectionFor(period);
          final next = index + 1 < periods.length ? periods[index + 1] : null;
          final gap = next == null
              ? null
              : next.startMinutes - period.endMinutes;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (index == 0 ||
                  _preview.sectionFor(periods[index - 1]) != section)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    section == null
                        ? '未划分时段'
                        : periodSessionLabel(section.session),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  '第 ${period.number} 节   '
                  '${periodClock(period.startMinutes)} – ${periodClock(period.endMinutes)}',
                ),
                subtitle: gap == null
                    ? null
                    : Text(
                        gap < 0
                            ? '与下节重叠 ${-gap} 分钟'
                            : '${section != null && section == _preview.sectionFor(next!) ? '课间' : '距下一节'} $gap 分钟',
                        style: TextStyle(
                          color: gap < 0
                              ? Theme.of(context).colorScheme.error
                              : null,
                        ),
                      ),
                trailing: IconButton(
                  tooltip: '修改第 ${period.number} 节',
                  onPressed: () => _editPreviewPeriod(period),
                  icon: const Icon(Icons.edit_outlined),
                ),
                onTap: () => _editPreviewPeriod(period),
              ),
              if (next != null) const Divider(height: 1),
            ],
          );
        },
      ),
    ]);
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

class _SessionFields {
  final count = TextEditingController();
  final start = TextEditingController();
  final timeForm = GlobalKey<FormState>();
}

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
