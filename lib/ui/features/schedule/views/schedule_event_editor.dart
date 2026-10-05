import 'dart:math';

import 'package:flutter/material.dart';
import 'package:zf_core/zf_core.dart';

import '../../../core/adaptive_sheet.dart';
import '../view_models/schedule_labels.dart';
import '../view_models/timetable_view_model.dart';
import 'schedule_day_widgets.dart';

enum ScheduleEventEditResult { saved, deleted }

Future<ScheduleEventEditResult?> showScheduleEventEditor(
  BuildContext context,
  TimetableViewModel model, {
  required DateTime initialDate,
  ScheduleEvent? event,
}) async {
  final target = model.eventTarget;
  if (target == null) return null;
  final account = model.account!.account;
  return showAdaptiveSheet<ScheduleEventEditResult>(
    context: context,
    maxWidth: 640,
    builder: (context) => ScheduleEventEditor(
      initialDate: initialDate,
      event: event,
      accountLabel: '${account.schoolName} · ${account.accountName}',
      onSave: (value) async =>
          await model.saveEvent(value, target: target, replacing: event)
          ? null
          : model.data.failure?.message ?? '日程未能保存，请重试',
      onDelete: event == null
          ? null
          : () async => await model.removeEvent(event, target: target)
                ? null
                : model.data.failure?.message ?? '日程未能删除，请重试',
    ),
  );
}

class ScheduleEventEditor extends StatefulWidget {
  const ScheduleEventEditor({
    required this.initialDate,
    required this.accountLabel,
    required this.onSave,
    this.event,
    this.onDelete,
    super.key,
  });
  final DateTime initialDate;
  final String accountLabel;
  final ScheduleEvent? event;
  final Future<String?> Function(ScheduleEvent) onSave;
  final Future<String?> Function()? onDelete;

  @override
  State<ScheduleEventEditor> createState() => _ScheduleEventEditorState();
}

class _ScheduleEventEditorState extends State<ScheduleEventEditor> {
  final _form = GlobalKey<FormState>();
  final _titleFocus = FocusNode();
  late final TextEditingController _title;
  late final TextEditingController _location;
  late final TextEditingController _note;
  late final String _id;
  late DateTime _date;
  late ScheduleEventCategory _category;
  late bool _allDay;
  late bool _completed;
  int? _start;
  int? _end;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    _title = TextEditingController(text: event?.title ?? '');
    _location = TextEditingController(text: event?.location ?? '');
    _note = TextEditingController(text: event?.note ?? '');
    _date = event?.date ?? widget.initialDate;
    _category = event?.category ?? ScheduleEventCategory.todo;
    _allDay = event?.isAllDay ?? true;
    _completed = event?.completed ?? false;
    _start = event?.startMinutes;
    _end = event?.endMinutes;
    final random = Random.secure();
    _id =
        event?.id ??
        'event-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _note.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  bool get _canComplete =>
      _category == ScheduleEventCategory.todo ||
      _category == ScheduleEventCategory.homework;

  Future<void> _pickDate() async {
    final date = await pickScheduleDate(context, _date);
    if (mounted && date != null) setState(() => _date = date);
  }

  Future<void> _pickTime({required bool start}) async {
    final minutes = start ? _start : _end;
    final time = await showTimePicker(
      context: context,
      initialTime: minutes == null
          ? TimeOfDay.now()
          : TimeOfDay(
              hour: (minutes % ScheduleEvent.minutesPerDay) ~/ 60,
              minute: minutes % 60,
            ),
      helpText: start ? '开始时间' : '结束时间（00:00 表示当天 24:00）',
      cancelText: '取消',
      confirmText: '确定',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (!mounted || time == null) return;
    final selectedMinutes = time.hour * 60 + time.minute;
    setState(() {
      if (start) {
        _start = selectedMinutes;
      } else {
        _end = selectedMinutes == 0
            ? ScheduleEvent.minutesPerDay
            : selectedMinutes;
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_form.currentState!.validate()) {
      _titleFocus.requestFocus();
      return;
    }
    if (!_allDay && (_start == null || _end == null || _end! <= _start!)) {
      setState(() => _error = '请选择开始和结束时间，结束时间必须晚于开始时间。');
      return;
    }
    final event = ScheduleEvent(
      id: _id,
      title: _title.text.trim(),
      date: _date,
      category: _category,
      startMinutes: _allDay ? null : _start,
      endMinutes: _allDay ? null : _end,
      location: _optional(_location.text),
      note: _optional(_note.text),
      completed: _canComplete && _completed,
    );
    await _submit(() => widget.onSave(event), ScheduleEventEditResult.saved);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除日程？'),
        content: Text('删除「${widget.event!.title}」的本地记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _submit(widget.onDelete!, ScheduleEventEditResult.deleted);
    }
  }

  Future<void> _submit(
    Future<String?> Function() action,
    ScheduleEventEditResult result,
  ) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final error = await action();
      if (!mounted) return;
      if (error == null) {
        Navigator.pop(context, result);
      } else {
        setState(() => _error = error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_saving,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .88,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.event == null ? '新建日程' : '编辑日程',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭日程编辑',
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  key: const ValueKey('schedule-event-form-scroll'),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          widget.accountLabel,
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const ValueKey('schedule-event-title'),
                          controller: _title,
                          focusNode: _titleFocus,
                          enabled: !_saving,
                          decoration: const InputDecoration(labelText: '日程标题'),
                          textInputAction: TextInputAction.next,
                          validator: (value) =>
                              value?.trim().isEmpty ?? true ? '请填写日程标题' : null,
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<ScheduleEventCategory>(
                          key: const ValueKey('schedule-event-category'),
                          initialValue: _category,
                          decoration: const InputDecoration(labelText: '分类'),
                          items: [
                            for (final category in ScheduleEventCategory.values)
                              DropdownMenuItem(
                                value: category,
                                child: Text(category.label),
                              ),
                          ],
                          onChanged: _saving
                              ? null
                              : (value) => setState(() => _category = value!),
                        ),
                        const SizedBox(height: 8),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.event_outlined),
                          title: const Text('日期'),
                          subtitle: Text(scheduleDateText(_date, year: true)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _saving ? null : _pickDate,
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('全天'),
                          value: _allDay,
                          onChanged: _saving
                              ? null
                              : (value) => setState(() => _allDay = value),
                        ),
                        if (!_allDay) ...[
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final buttons = [
                                _timeButton(
                                  '开始',
                                  _start,
                                  () => _pickTime(start: true),
                                ),
                                _timeButton(
                                  '结束',
                                  _end,
                                  () => _pickTime(start: false),
                                ),
                              ];
                              final compact =
                                  constraints.maxWidth /
                                      (MediaQuery.textScalerOf(context)
                                              .scale(14) /
                                          14) <
                                  350;
                              return compact
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        buttons[0],
                                        const SizedBox(height: 8),
                                        buttons[1],
                                      ],
                                    )
                                  : Row(
                                      children: [
                                        Expanded(child: buttons[0]),
                                        const SizedBox(width: 12),
                                        Expanded(child: buttons[1]),
                                      ],
                                    );
                            },
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextField(
                          controller: _location,
                          enabled: !_saving,
                          decoration: const InputDecoration(
                            labelText: '地点（选填）',
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _note,
                          enabled: !_saving,
                          decoration: const InputDecoration(
                            labelText: '备注（选填）',
                          ),
                          minLines: 2,
                          maxLines: 4,
                        ),
                        if (_canComplete && widget.event != null)
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('已完成'),
                            value: _completed,
                            onChanged: _saving
                                ? null
                                : (value) =>
                                      setState(() => _completed = value!),
                          ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              _error!,
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
              if (_saving) const LinearProgressIndicator(minHeight: 2),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 20, 12),
                  child: Row(
                    children: [
                      if (widget.onDelete != null)
                        IconButton(
                          tooltip: '删除日程',
                          onPressed: _saving ? null : _delete,
                          icon: Icon(
                            Icons.delete_outline,
                            color: theme.colorScheme.error,
                          ),
                        ),
                      const Spacer(),
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        key: const ValueKey('schedule-event-save'),
                        onPressed: _saving ? null : _save,
                        child: Text(_saving ? '保存中' : '保存'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timeButton(String label, int? minutes, VoidCallback onTap) =>
      OutlinedButton.icon(
        onPressed: _saving ? null : onTap,
        icon: const Icon(Icons.schedule_outlined, size: 18),
        label: Text(
          '$label ${minutes == null ? '选择时间' : scheduleClockText(minutes)}',
        ),
      );

  static String? _optional(String value) =>
      value.trim().isEmpty ? null : value.trim();
}
