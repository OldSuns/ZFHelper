import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zf_core/zf_core.dart';

import '../../../../data/repositories/schedule_repository.dart';
import '../../../core/app_theme.dart';
import '../view_models/timetable_view_model.dart';
import 'teaching_week_selector.dart';

Future<bool> showScheduleCourseEditor(
  BuildContext context,
  TimetableViewModel viewModel, {
  ScheduleEntry? entry,
  ScheduleTarget? target,
  ScheduleSnapshot? snapshot,
  int? week,
  List<ScheduleOccurrenceOverride>? expectedOverrides,
}) async {
  final editing = viewModel.adjustmentContext;
  final destination = target ?? editing?.target;
  final original = snapshot ?? editing?.baseline;
  if (destination == null || original == null) return false;
  final root = entry == null
      ? null
      : original.entries
            .where((item) => item.id == (entry.sourceEntryId ?? entry.id))
            .firstOrNull;
  if (entry != null && root == null) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('原始课程已更新，请重新打开课程详情')));
    return false;
  }
  final changes = List<ScheduleOccurrenceOverride>.unmodifiable(
    expectedOverrides ?? (root == null ? const [] : editing!.changesFor(root)),
  );
  final initialWeek = week ?? viewModel.selectedWeek;
  final value = await Navigator.of(context).push<ScheduleEntry>(
    MaterialPageRoute(
      builder: (context) => CourseEditorPage(
        entry: root,
        initialWeek: initialWeek,
        visibleWeekCount: max(
          original.navigationWeekLimit ?? original.observedMaxWeek,
          initialWeek,
        ),
        periodCount: original.maxPeriod,
        occurrenceChangeCount: changes.length,
        onSave: (value) async =>
            await viewModel.saveLocalEntry(
              value,
              target: destination,
              replacing: root,
              expectedOverrides: changes,
            )
            ? null
            : viewModel.data.failure?.message ?? '保存未完成，请重试',
      ),
    ),
  );
  return value != null;
}

class CourseEditorPage extends StatefulWidget {
  const CourseEditorPage({
    super.key,
    this.entry,
    required this.initialWeek,
    required this.visibleWeekCount,
    required this.periodCount,
    this.occurrenceChangeCount = 0,
    this.onSave,
  }) : assert(initialWeek > 0),
       assert(visibleWeekCount > 0),
       assert(periodCount >= 0);

  final ScheduleEntry? entry;
  final int initialWeek;
  final int visibleWeekCount;
  final int periodCount;
  final int occurrenceChangeCount;
  final Future<String?> Function(ScheduleEntry)? onSave;

  @override
  State<CourseEditorPage> createState() => _CourseEditorPageState();
}

class _CourseEditorPageState extends State<CourseEditorPage> {
  final _formKey = GlobalKey<FormState>();
  final _focusNodes = <String, FocusNode>{};
  late final TextEditingController _name;
  late final TextEditingController _teacher;
  late final TextEditingController _campus;
  late final TextEditingController _location;
  late final TextEditingController _startPeriod;
  late final TextEditingController _endPeriod;
  late final TextEditingController _weeks;
  int? _weekday;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _name = TextEditingController(text: entry?.name ?? '');
    _teacher = TextEditingController(text: entry?.teacher ?? '');
    _campus = TextEditingController(text: entry?.campus ?? '');
    _location = TextEditingController(text: entry?.location ?? '');
    _startPeriod = TextEditingController(
      text: entry?.startPeriod?.toString() ?? '',
    );
    _endPeriod = TextEditingController(
      text: entry?.endPeriod?.toString() ?? '',
    );
    _weeks = TextEditingController(
      text: entry == null
          ? '${widget.initialWeek}'
          : _weekExpression(entry.weeks),
    );
    _weekday = entry?.weekday;
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _teacher,
      _campus,
      _location,
      _startPeriod,
      _endPeriod,
      _weeks,
    ]) {
      controller.dispose();
    }
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _focus(String name) =>
      _focusNodes.putIfAbsent(name, () => FocusNode(debugLabel: name));

  @override
  Widget build(BuildContext context) {
    final imported = widget.entry?.origin == ScheduleEntryOrigin.imported;
    final weekDraft = _parseWeekDraft(_weeks.text);
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: '取消编辑',
            icon: const Icon(Icons.close),
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
          ),
          title: Text(widget.entry == null ? '添加课程' : '编辑课程'),
        ),
        body: FocusScope(
          canRequestFocus: !_saving,
          child: AbsorbPointer(
            absorbing: _saving,
            child: SafeArea(
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Form(
                    key: _formKey,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.all(AppLayout.pagePadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_saveError != null) ...[
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                _saveError!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          Text(
                            imported
                                ? '调整会保存为本地课程；学校原始课表仍保留。'
                                : '保存到当前学期的本地课表。',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          if (widget.occurrenceChangeCount > 0) ...[
                            const SizedBox(height: 12),
                            Text(
                              '此处编辑整学期的原始安排。保存会撤销这条安排已有的 '
                              '${widget.occurrenceChangeCount} 项调课、停课或补课记录。'
                              '只改某一次课程，请返回使用“调课 / 停课 / 补课”。',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                          const SizedBox(height: AppLayout.sectionGap),
                          _textField(
                            'course-name',
                            '课程名称',
                            _name,
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? '请填写课程名称'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          _textField('course-teacher', '教师（选填）', _teacher),
                          const SizedBox(height: 16),
                          _textField('course-campus', '校区（选填）', _campus),
                          const SizedBox(height: 16),
                          _textField(
                            'course-location',
                            '教室 / 地点（选填）',
                            _location,
                          ),
                          const SizedBox(height: AppLayout.sectionGap),
                          Text(
                            '上课安排',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<int>(
                            key: const ValueKey('course-weekday'),
                            focusNode: _focus('course-weekday'),
                            initialValue: _weekday,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: '星期'),
                            items: [
                              for (
                                var day = 1;
                                day <= DateTime.daysPerWeek;
                                day++
                              )
                                DropdownMenuItem(
                                  value: day,
                                  child: Text(_weekdays[day - 1]),
                                ),
                            ],
                            onChanged: (value) =>
                                setState(() => _weekday = value),
                            validator: (value) =>
                                value == null ? '请选择星期' : null,
                          ),
                          const SizedBox(height: 16),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final fields = [
                                _periodField(
                                  'course-start-period',
                                  '开始节次',
                                  _startPeriod,
                                ),
                                _periodField(
                                  'course-end-period',
                                  '结束节次',
                                  _endPeriod,
                                ),
                              ];
                              if (constraints.maxWidth <
                                  440 *
                                      MediaQuery.textScalerOf(context)
                                          .scale(1)) {
                                return Column(
                                  children: [
                                    fields.first,
                                    const SizedBox(height: 16),
                                    fields.last,
                                  ],
                                );
                              }
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: fields.first),
                                  const SizedBox(width: 16),
                                  Expanded(child: fields.last),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.periodCount > 0
                                ? '当前课表显示 ${widget.periodCount} 节，可按实际安排填写更多节次。'
                                : '填写课节序号，例如第 3 节到第 4 节；无需先配置作息时间。',
                          ),
                          const SizedBox(height: AppLayout.sectionGap),
                          _textField(
                            'course-weeks',
                            '上课周次',
                            _weeks,
                            validator: (value) => _parseWeekDraft(value).error,
                            helperText: '支持 1-16、1-16(单)、2,5,8；也可填写更大的周次。',
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 8),
                          if (widget.entry == null)
                            Text('新课程已预选第 ${widget.initialWeek} 周，请按实际安排调整。'),
                          const SizedBox(height: 12),
                          TeachingWeekSelector(
                            value: weekDraft.weeks,
                            weekCount: widget.visibleWeekCount,
                            currentWeek: widget.initialWeek,
                            onChanged: _setWeeks,
                            enabled: !_saving,
                            semanticLabel: '选择上课周次',
                            keyPrefix: 'course',
                          ),
                          const SizedBox(height: 12),
                          Text(
                            weekDraft.error == null
                                ? '共 ${weekDraft.weeks.length} 个教学周'
                                : '请填写明确的上课周次，不会自动按每周排课。',
                            key: const ValueKey('course-weeks-summary'),
                          ),
                          const SizedBox(height: AppLayout.sectionGap),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              12 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: FilledButton(
              key: const ValueKey('course-save'),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '正在保存…' : '保存课程'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _textField(
    String key,
    String label,
    TextEditingController controller, {
    FormFieldValidator<String>? validator,
    String? helperText,
    ValueChanged<String>? onChanged,
  }) => TextFormField(
    key: ValueKey(key),
    focusNode: _focus(key),
    controller: controller,
    textInputAction: TextInputAction.next,
    decoration: InputDecoration(
      labelText: label,
      helperText: helperText,
      helperMaxLines: 4,
      errorMaxLines: 4,
    ),
    validator: validator,
    onChanged: onChanged,
  );

  Widget _periodField(
    String key,
    String label,
    TextEditingController controller,
  ) => TextFormField(
    key: ValueKey(key),
    focusNode: _focus(key),
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
      final number = int.tryParse(value?.trim() ?? '');
      if (number == null || number < 1) return '请填写大于 0 的节次';
      if (controller == _endPeriod &&
          number < (int.tryParse(_startPeriod.text) ?? 1)) {
        return '结束节次不能早于开始节次';
      }
      return null;
    },
  );

  ({Set<int> weeks, String? error}) _parseWeekDraft(String? value) {
    if (value == null || value.trim().isEmpty) {
      return (weeks: const {}, error: '请填写上课周次');
    }
    try {
      return (weeks: parseTeachingWeeks(value), error: null);
    } on ScheduleParseException catch (error) {
      return (
        weeks: const {},
        error: error.code == ScheduleParseCode.unsupported
            ? '周次范围过大，请缩短一次填写的区间'
            : '周次无法识别，请核对区间、逗号和单双周标记',
      );
    }
  }

  void _setWeeks(Set<int> weeks) {
    _weeks.text = _weekExpression(weeks, rangeEnd: widget.visibleWeekCount);
    setState(() {});
  }

  Future<void> _save() async {
    final invalid = _formKey.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      final first = invalid.first;
      final key = first.widget.key;
      if (key is ValueKey<String>) _focusNodes[key.value]?.requestFocus();
      Scrollable.ensureVisible(first.context, alignment: 0.1);
      return;
    }
    final previous = widget.entry;
    final isImported = previous?.origin == ScheduleEntryOrigin.imported;
    final entry = ScheduleEntry(
      id: previous?.origin == ScheduleEntryOrigin.local
          ? previous!.id
          : _newLocalId(),
      name: _name.text.trim(),
      teachingClassId: previous?.teachingClassId,
      courseCode: previous?.courseCode,
      teacher: _optional(_teacher.text),
      campus: _optional(_campus.text),
      location: _optional(_location.text),
      weekday: _weekday!,
      startPeriod: int.parse(_startPeriod.text),
      endPeriod: int.parse(_endPeriod.text),
      weeks: parseTeachingWeeks(_weeks.text),
      rawWeeks: _weeks.text.trim(),
      metadata: {
        ...?previous?.metadata,
        if (isImported) 'replacesImportedId': previous!.id,
      },
      origin: ScheduleEntryOrigin.local,
      kind: previous?.kind ?? ScheduleEntryKind.lesson,
    );
    final save = widget.onSave;
    if (save != null) {
      FocusScope.of(context).unfocus();
      setState(() {
        _saving = true;
        _saveError = null;
      });
      final error = await save(entry);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = error;
      });
      if (error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
        return;
      }
    }
    if (mounted) Navigator.of(context).pop(entry);
  }
}

const _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

String? _optional(String value) => value.trim().isEmpty ? null : value.trim();

String _newLocalId() {
  final random = Random.secure();
  final entropy = List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return 'local-$entropy';
}

String _weekExpression(Set<int> weeks, {int? rangeEnd}) {
  if (weeks.isEmpty) return '';
  final sorted = weeks.toList()..sort();
  if (rangeEnd != null && sorted.length > 1 && sorted.last <= rangeEnd) {
    final parity = sorted.first % 2;
    if (sorted.length == (rangeEnd + parity) ~/ 2 &&
        sorted.every((week) => week % 2 == parity)) {
      return '1-$rangeEnd(${parity == 1 ? '单' : '双'})';
    }
  }
  final ranges = <String>[];
  var start = sorted.first;
  var end = start;
  for (final week in sorted.skip(1)) {
    if (week == end + 1) {
      end = week;
    } else {
      ranges.add(start == end ? '$start' : '$start-$end');
      start = end = week;
    }
  }
  ranges.add(start == end ? '$start' : '$start-$end');
  return ranges.join(',');
}
