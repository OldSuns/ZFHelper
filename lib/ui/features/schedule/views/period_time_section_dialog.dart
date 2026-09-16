import 'package:flutter/material.dart';
import 'package:zf_core/zf_core.dart';

import 'period_time_fields.dart';

class PeriodTimeSectionDialog extends StatefulWidget {
  const PeriodTimeSectionDialog({
    super.key,
    required this.initialPlan,
    required this.campus,
  });

  final PeriodTimePlan initialPlan;
  final String? campus;

  @override
  State<PeriodTimeSectionDialog> createState() =>
      _PeriodTimeSectionDialogState();
}

class _PeriodTimeSectionDialogState extends State<PeriodTimeSectionDialog> {
  static const _buttonStyle = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(0, 48)),
  );
  final _form = GlobalKey<FormState>();
  late final List<int> _numbers;
  late final Map<PeriodSession, _SectionRange> _ranges;
  String? _error;

  String? get _campus => normalizePeriodCampus(widget.campus);

  @override
  void initState() {
    super.initState();
    _numbers =
        widget.initialPlan
            .periodsForCampus(_campus)
            .map((period) => period.number)
            .toSet()
            .toList()
          ..sort();
    _ranges = {
      for (final session in PeriodSession.values)
        session: _SectionRange(
          widget.initialPlan.sections
              .where(
                (section) =>
                    section.campus == _campus && section.session == session,
              )
              .firstOrNull,
        ),
    };
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    try {
      final result = widget.initialPlan.withSections(
        campus: _campus,
        sections: [
          for (final entry in _ranges.entries)
            if (entry.value.enabled)
              PeriodTimeSection(
                session: entry.key,
                firstPeriod: entry.value.first!,
                lastPeriod: entry.value.last!,
                campus: _campus,
              ),
        ],
      );
      Navigator.pop(context, result);
    } on PeriodTimeException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      // Measure outside AlertDialog: its intrinsic pass cannot query a LayoutBuilder.
      final contentWidth = (constraints.maxWidth - 128).clamp(0, 440);
      final sideBySide = contentWidth >= 280 * scale;
      return AlertDialog(
        title: const Text('划分时段'),
        scrollable: true,
        content: SizedBox(
          width: 440,
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _numbers.isEmpty
                      ? '当前校区没有课节作息，请先添加课节或生成时间。'
                      : '从当前预览的已有节次中选择每个时段的首节和末节。节号、起止时间和课间均保持不变。',
                ),
                for (final entry in _ranges.entries) ...[
                  CheckboxListTile(
                    key: ValueKey('period-section-${entry.key.name}-enabled'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(periodSessionLabel(entry.key)),
                    value: entry.value.enabled,
                    onChanged: _numbers.isEmpty
                        ? null
                        : (value) => setState(() {
                            entry.value.enabled = value!;
                            _error = null;
                          }),
                  ),
                  if (entry.value.enabled)
                    if (sideBySide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _boundary(entry.key, first: true)),
                          const SizedBox(width: 12),
                          Expanded(child: _boundary(entry.key, first: false)),
                        ],
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _boundary(entry.key, first: true),
                          const SizedBox(height: 12),
                          _boundary(entry.key, first: false),
                        ],
                      ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          OutlinedButton(
            style: _buttonStyle,
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('period-section-preview'),
            style: _buttonStyle,
            onPressed: _numbers.isEmpty ? null : _save,
            child: const Text('预览划分'),
          ),
        ],
      );
    },
  );

  Widget _boundary(PeriodSession session, {required bool first}) {
    final range = _ranges[session]!;
    final selected = first ? range.first : range.last;
    final options = [..._numbers];
    if (selected != null && !options.contains(selected)) options.add(selected);
    options.sort();
    return DropdownButtonFormField<int>(
      key: ValueKey(
        'period-section-${session.name}-${first ? 'first' : 'last'}',
      ),
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: first ? '首节' : '末节',
        isDense: true,
        errorMaxLines: 3,
      ),
      items: [
        for (final number in options)
          DropdownMenuItem(
            value: number,
            enabled: _numbers.contains(number),
            child: Text(
              _numbers.contains(number) ? '第 $number 节' : '第 $number 节（缺少作息）',
            ),
          ),
      ],
      onChanged: (value) => setState(() {
        if (first) {
          range.first = value;
        } else {
          range.last = value;
        }
        _error = null;
      }),
      validator: (value) =>
          value == null || !_numbers.contains(value) ? '请选择已有作息的节次' : null,
    );
  }
}

class _SectionRange {
  _SectionRange(PeriodTimeSection? section)
    : enabled = section != null,
      first = section?.firstPeriod,
      last = section?.lastPeriod;

  bool enabled;
  int? first;
  int? last;
}
