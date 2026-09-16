import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zf_core/zf_core.dart';

import '../view_models/period_times_view_model.dart';
import 'period_time_fields.dart';

class PeriodTimeEditDialog extends StatefulWidget {
  const PeriodTimeEditDialog({super.key, required this.viewModel, this.period});

  final PeriodTimesViewModel viewModel;
  final PeriodTime? period;

  @override
  State<PeriodTimeEditDialog> createState() => _PeriodTimeEditDialogState();
}

class _PeriodTimeEditDialogState extends State<PeriodTimeEditDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _number;
  late final TextEditingController _start;
  late final TextEditingController _end;
  int? _duration;
  bool _shiftFollowing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final period = widget.period;
    _number = TextEditingController(
      text:
          '${period?.number ?? ((widget.viewModel.periods.lastOrNull?.number ?? 0) + 1)}',
    );
    _start = TextEditingController(
      text: period == null ? '' : periodClock(period.startMinutes),
    );
    _end = TextEditingController(
      text: period == null ? '' : periodClock(period.endMinutes),
    );
    _duration = period == null ? null : period.endMinutes - period.startMinutes;
  }

  @override
  void dispose() {
    _number.dispose();
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  void _startChanged(String value) {
    final start = parsePeriodClock(value);
    final duration = _duration;
    if (start != null && duration != null) {
      _end.text = periodClock(start + duration);
    }
    setState(() => _error = null);
  }

  void _endChanged(String value) {
    final start = parsePeriodClock(_start.text);
    final end = parsePeriodClock(value);
    if (start != null && end != null && end > start) _duration = end - start;
    setState(() => _error = null);
  }

  void _apply() {
    if (!_form.currentState!.validate()) return;
    final start = parsePeriodClock(_start.text)!;
    final end = parsePeriodClock(_end.text)!;
    final period = widget.period;
    final changed = widget.viewModel.change(
      (plan) => period == null
          ? plan.add(
              PeriodTime(
                number: int.parse(_number.text),
                campus: widget.viewModel.campus,
                startMinutes: start,
                endMinutes: end,
              ),
            )
          : plan.edit(
              number: period.number,
              campus: period.campus,
              startMinutes: start,
              endMinutes: end,
              shiftFollowing: _shiftFollowing,
            ),
    );
    if (changed) {
      Navigator.pop(context);
    } else {
      setState(() => _error = widget.viewModel.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final period = widget.period;
    final section = period == null
        ? null
        : widget.viewModel.plan.sectionFor(period);
    return AlertDialog(
      title: Text(period == null ? '添加课节' : '调整第 ${period.number} 节'),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.viewModel.campus ?? '通用（未指定校区）'),
              if (period == null) ...[
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('period-edit-number'),
                  controller: _number,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: '节次'),
                  validator: (value) {
                    final number = int.tryParse(value ?? '');
                    return number == null || number < 1 ? '请填写大于 0 的节次' : null;
                  },
                ),
              ],
              const SizedBox(height: 16),
              PeriodClockField(
                key: const ValueKey('period-edit-start'),
                controller: _start,
                label: '开始时间',
                onChanged: _startChanged,
              ),
              const SizedBox(height: 16),
              PeriodClockField(
                key: const ValueKey('period-edit-end'),
                controller: _end,
                label: '结束时间',
                allowDayEnd: true,
                onChanged: _endChanged,
                validator: (value) {
                  final start = parsePeriodClock(_start.text);
                  final end = parsePeriodClock(value ?? '');
                  return start != null && end != null && end <= start
                      ? '结束时间必须晚于开始时间'
                      : null;
                },
              ),
              if (section != null && period!.number < section.lastPeriod)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _shiftFollowing,
                  onChanged: (value) =>
                      setState(() => _shiftFollowing = value!),
                  title: const Text('同步移动本时段后续课节'),
                  subtitle: Text(
                    '联动至${periodSessionLabel(section.session)}第 ${section.lastPeriod} 节，保留课长和课间。',
                  ),
                )
              else if (period != null && section == null) ...[
                const SizedBox(height: 12),
                const Text('尚未划分时段，本次只调整这一节。'),
              ],
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
          key: const ValueKey('period-edit-apply'),
          onPressed: _apply,
          child: const Text('应用到预览'),
        ),
      ],
    );
  }
}

class PeriodValueDialog extends StatefulWidget {
  const PeriodValueDialog({
    super.key,
    required this.title,
    required this.label,
    required this.description,
    required this.onApply,
    this.initialValue = '',
    this.numeric = false,
  });

  final String title;
  final String label;
  final String description;
  final String initialValue;
  final bool numeric;
  final String? Function(String) onApply;

  @override
  State<PeriodValueDialog> createState() => _PeriodValueDialogState();
}

class _PeriodValueDialogState extends State<PeriodValueDialog> {
  final _form = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: widget.initialValue);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply() {
    if (!_form.currentState!.validate()) return;
    final error = widget.onApply(_controller.text.trim());
    if (error == null) {
      Navigator.pop(context);
    } else {
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    scrollable: true,
    content: SizedBox(
      width: 400,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.description),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('period-value-input'),
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              keyboardType: widget.numeric ? TextInputType.number : null,
              inputFormatters: widget.numeric
                  ? [FilteringTextInputFormatter.digitsOnly]
                  : null,
              decoration: InputDecoration(labelText: widget.label),
              validator: (value) {
                if (value?.trim().isEmpty ?? true) return '请填写${widget.label}';
                if (widget.numeric) {
                  final minutes = int.tryParse(value!);
                  if (minutes == null || minutes < 0) return '请填写不小于 0 的分钟数';
                }
                return null;
              },
              onFieldSubmitted: (_) => _apply(),
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
        key: const ValueKey('period-value-apply'),
        onPressed: _apply,
        child: const Text('确定'),
      ),
    ],
  );
}
