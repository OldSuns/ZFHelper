part of 'schedule_adjustment_editor.dart';

final class _AdjustmentSource {
  const _AdjustmentSource({
    required this.entry,
    required this.week,
    this.owner,
  });

  final ScheduleEntry entry;
  final int week;
  final ScheduleOccurrenceOverride? owner;

  String get key => '${owner == null ? 'entry' : 'source'}:${entry.id}:$week';
}

final class _AdjustmentDraft {
  _AdjustmentDraft(this.source, {required this.selected})
    : start = TextEditingController(
        text: source.entry.startPeriod?.toString() ?? '',
      ),
      end = TextEditingController(
        text: source.entry.endPeriod?.toString() ?? '',
      ),
      destination = TextEditingController(),
      location = TextEditingController(text: source.entry.location ?? '');

  final _AdjustmentSource source;
  final TextEditingController start;
  final TextEditingController end;
  final TextEditingController destination;
  final TextEditingController location;
  bool selected;
  bool changeLocation = false;

  int? get selectedStart =>
      source.entry.startPeriod == null ? null : _period(start, '原课开始节次');
  int? get selectedEnd =>
      source.entry.endPeriod == null ? null : _period(end, '原课结束节次');
  int? get targetStart =>
      destination.text.trim().isEmpty ? null : _period(destination, '目标开始节次');

  int _period(TextEditingController controller, String label) {
    final value = int.tryParse(controller.text.trim());
    if (value == null || value < 1) {
      throw FormatException('$label需要填写大于 0 的整数。');
    }
    return value;
  }

  void dispose() {
    start.dispose();
    end.dispose();
    destination.dispose();
    location.dispose();
  }
}

class _AdjustmentCourseFields extends StatelessWidget {
  const _AdjustmentCourseFields({
    required this.draft,
    required this.wholeDay,
    required this.kind,
    required this.onChanged,
    super.key,
  });

  final _AdjustmentDraft draft;
  final bool wholeDay;
  final ScheduleChangeKind kind;
  final VoidCallback onChanged;

  bool get _timed => draft.source.entry.startPeriod != null;
  bool get _hasTarget => kind != ScheduleChangeKind.cancel;
  bool get _hasFields => !wholeDay && _timed || _hasTarget;

  @override
  Widget build(BuildContext context) {
    final entry = draft.source.entry;
    final subtitle = Text(
      [
        entry.schedulePeriodsText,
        entry.schedulePlaceText,
        if (draft.source.owner != null) '按原始安排补课',
      ].join(' · '),
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wholeDay)
            ListTile(title: Text(entry.name), subtitle: subtitle)
          else
            CheckboxListTile(
              title: Text(entry.name),
              subtitle: subtitle,
              value: draft.selected,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (value) {
                draft.selected = value!;
                onChanged();
              },
            ),
          if ((wholeDay || draft.selected) && _hasFields)
            ExpansionTile(
              title: Text(_hasTarget ? '调整节次和地点' : '选择停课节次'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              children: _fields(),
            ),
        ],
      ),
    );
  }

  List<Widget> _fields() => [
    if (!wholeDay && _timed) ...[
      ScheduleAdjustmentFieldRow(
        first: _periodField(draft.start, '原课开始节次'),
        second: _periodField(draft.end, '原课结束节次'),
      ),
      const SizedBox(height: 8),
      Text('原安排为 ${draft.source.entry.schedulePeriodsText}，可选择其中一段连续节次。'),
      const SizedBox(height: 16),
    ],
    if (_hasTarget && _timed) ...[
      _periodField(draft.destination, '目标开始节次（选填）', optional: true),
      const SizedBox(height: 8),
      const Text('留空时保留所选节次；填写后会保留相同的节数。'),
      const SizedBox(height: 16),
    ],
    if (_hasTarget && !_timed) ...[
      const Text('这门课尚未安排节次，本次会保留该状态并调整上课日期。'),
      const SizedBox(height: 12),
    ],
    if (_hasTarget) ...[
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('修改本次地点'),
        value: draft.changeLocation,
        onChanged: (value) {
          draft.changeLocation = value;
          onChanged();
        },
      ),
      if (draft.changeLocation) ...[
        const SizedBox(height: 8),
        TextFormField(
          controller: draft.location,
          decoration: const InputDecoration(
            labelText: '本次教室 / 地点',
            helperText: '清空表示本次地点待安排。',
            helperMaxLines: 3,
          ),
          onChanged: (_) => onChanged(),
        ),
      ],
    ],
  ];

  Widget _periodField(
    TextEditingController controller,
    String label, {
    bool optional = false,
  }) => TextFormField(
    controller: controller,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    textInputAction: TextInputAction.next,
    decoration: InputDecoration(
      labelText: label,
      suffixText: '节',
      errorMaxLines: 3,
    ),
    validator: (value) {
      if (optional && (value?.trim().isEmpty ?? true)) return null;
      final number = int.tryParse(value?.trim() ?? '');
      return number == null || number < 1 ? '请输入大于 0 的整数' : null;
    },
    onChanged: (_) => onChanged(),
  );
}
