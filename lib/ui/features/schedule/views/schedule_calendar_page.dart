import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zf_core/zf_core.dart';

import '../../../core/app_theme.dart';

class ScheduleCalendarPage extends StatefulWidget {
  const ScheduleCalendarPage({
    super.key,
    required this.snapshot,
    required this.settings,
    required this.today,
    this.onSave,
  });

  final ScheduleSnapshot snapshot;
  final ScheduleSettings settings;
  final DateTime today;
  final Future<String?> Function(ScheduleSettings)? onSave;

  @override
  State<ScheduleCalendarPage> createState() => _ScheduleCalendarPageState();
}

class _ScheduleCalendarPageState extends State<ScheduleCalendarPage> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  final _errorFocus = FocusNode(debugLabel: 'calendar-form-error');
  final _ownedDrafts = <_PeriodDraft>[];
  late final TextEditingController _firstMonday;
  late final TextEditingController _totalWeeks;
  late List<_PeriodDraft> _periods;
  late bool _customCalendar;
  late bool _customTimes;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _customCalendar = widget.settings.calendarOverride != null;
    _customTimes = widget.settings.useCustomPeriodTimes;
    final calendar =
        widget.settings.calendarOverride ?? widget.snapshot.calendar;
    _firstMonday = TextEditingController(
      text: _dateText(calendar.firstWeekMonday),
    );
    _totalWeeks = TextEditingController(
      text: calendar.totalWeeks?.toString() ?? '',
    );
    final times = _customTimes
        ? widget.settings.periodTimes
        : widget.snapshot.periodTimes;
    _periods = times.map(_newDraft).toList();
  }

  @override
  void dispose() {
    _firstMonday.dispose();
    _totalWeeks.dispose();
    _scrollController.dispose();
    _errorFocus.dispose();
    for (final draft in _ownedDrafts) {
      draft.dispose();
    }
    super.dispose();
  }

  _PeriodDraft _newDraft([PeriodTime? period]) {
    final draft = _PeriodDraft(_ownedDrafts.length, period);
    _ownedDrafts.add(draft);
    return draft;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '取消设置',
          icon: const Icon(Icons.close),
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        title: const Text('校历与作息'),
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
                    controller: _scrollController,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.all(AppLayout.pagePadding),
                    // Form fields stay mounted while validation moves focus back to
                    // the error summary. A lazy list can dispose them mid-validation.
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _header(),
                        for (var index = 0; index < _periods.length; index++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _periodCard(_periods[index], index + 1),
                          ),
                        _periodFooter(),
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
            key: const ValueKey('calendar-save'),
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '正在保存…' : '保存设置'),
          ),
        ),
      ),
    ),
  );

  Widget _header() {
    final theme = Theme.of(context);
    final school = widget.snapshot.calendar;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.snapshot.term.label, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text('校历和作息按当前账号、当前学期保存，更新课表时保留本地设置。'),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Focus(
            focusNode: _errorFocus,
            child: Semantics(
              liveRegion: true,
              child: Container(
                key: const ValueKey('calendar-error'),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: AppLayout.sectionGap),
        Text('教学周校历', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          _customCalendar
              ? '当前使用用户校正'
              : school.source == TeachingCalendarSource.unknown
              ? '学校校历待确认'
              : '当前使用学校校历',
          key: const ValueKey('calendar-source'),
        ),
        if (school.sourceLabel != null) Text('学校来源：${school.sourceLabel}'),
        const SizedBox(height: 16),
        TextFormField(
          key: const ValueKey('calendar-first-monday'),
          controller: _firstMonday,
          keyboardType: TextInputType.datetime,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: '第一教学周的周一',
            hintText: 'YYYY-MM-DD',
            helperText: '可留空；请选择教学周起点，不把报到日直接当作第一周。',
            helperMaxLines: 4,
            errorMaxLines: 3,
            suffixIcon: IconButton(
              key: const ValueKey('calendar-pick-date'),
              tooltip: '选择第一周周一',
              icon: const Icon(Icons.calendar_month_outlined),
              onPressed: _pickMonday,
            ),
          ),
          validator: _dateError,
          onChanged: (_) => _changeCalendar(),
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const ValueKey('calendar-total-weeks'),
          controller: _totalWeeks,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: '总教学周数（选填）',
            suffixText: '周',
            helperText: '留空表示学期长度待确认，不会用课程的最大周次代替。',
            helperMaxLines: 4,
            errorMaxLines: 3,
          ),
          validator: _totalWeeksError,
          onChanged: (_) => _changeCalendar(),
        ),
        const SizedBox(height: 12),
        Text(_calendarPreview, key: const ValueKey('calendar-preview')),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('calendar-set-current-week'),
            onPressed: _setCurrentWeek,
            icon: const Icon(Icons.today_outlined),
            label: const Text('按当前教学周校正'),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('calendar-restore'),
            onPressed: _customCalendar ? _restoreCalendar : null,
            icon: const Icon(Icons.restore),
            label: const Text('恢复学校校历'),
          ),
        ),
        const SizedBox(height: AppLayout.sectionGap),
        const Divider(),
        const SizedBox(height: AppLayout.sectionGap),
        Text('课节作息', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          _customTimes ? '当前使用本地作息' : '当前使用学校作息',
          key: const ValueKey('period-source'),
        ),
        const SizedBox(height: 8),
        Text('学校提供 ${widget.snapshot.periodTimes.length} 项时间。下面的编辑只保存为本地设置。'),
        const SizedBox(height: 8),
        const Text('使用 24 小时制；同一校区的节次不能重复，时间按节次递增且不能重叠。'),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('period-restore'),
            onPressed: _customTimes ? _restoreTimes : null,
            icon: const Icon(Icons.restore),
            label: const Text('恢复学校作息'),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _periodCard(_PeriodDraft draft, int index) => Card(
    key: ValueKey('period-${draft.id}'),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '作息 $index',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                key: ValueKey('period-${draft.id}-remove'),
                tooltip: '删除作息 $index',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => setState(() {
                  _customTimes = true;
                  _error = null;
                  _periods.remove(draft);
                }),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey('period-${draft.id}-number'),
            controller: draft.number,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '节次',
              suffixText: '节',
              errorMaxLines: 3,
            ),
            validator: _periodNumberError,
            onChanged: (_) => _changeTimes(),
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: ValueKey('period-${draft.id}-campus'),
            controller: draft.campus,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: '校区（选填）'),
            onChanged: (_) => _changeTimes(),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final start = _timeField(draft, isEnd: false);
              final end = _timeField(draft, isEnd: true);
              if (constraints.maxWidth <
                  500 * MediaQuery.textScalerOf(context).scale(1)) {
                return Column(
                  children: [start, const SizedBox(height: 16), end],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: start),
                  const SizedBox(width: 16),
                  Expanded(child: end),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );

  Widget _timeField(_PeriodDraft draft, {required bool isEnd}) {
    final controller = isEnd ? draft.end : draft.start;
    final label = isEnd ? '结束时间' : '开始时间';
    return TextFormField(
      key: ValueKey('period-${draft.id}-${isEnd ? 'end' : 'start'}'),
      controller: controller,
      keyboardType: TextInputType.datetime,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'HH:mm',
        errorMaxLines: 3,
        suffixIcon: IconButton(
          tooltip: '选择$label',
          icon: const Icon(Icons.schedule),
          onPressed: () => _pickTime(controller, isEnd: isEnd),
        ),
      ),
      validator: (value) {
        final error = _timeError(value, isEnd: isEnd);
        if (error != null) return error;
        if (isEnd) {
          final start = _minutes(draft.start.text);
          if (start != null && _minutes(value!)! <= start) {
            return '结束时间必须晚于开始时间';
          }
        }
        return null;
      },
      onChanged: (_) => _changeTimes(),
    );
  }

  Widget _periodFooter() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_periods.isEmpty) ...[
        Text(_customTimes ? '本地作息已清空；保存后仅显示课节序号。' : '学校未提供作息，课表仍可按课节序号显示。'),
        const SizedBox(height: 16),
      ],
      OutlinedButton.icon(
        key: const ValueKey('period-add'),
        onPressed: () => setState(() {
          _customTimes = true;
          _error = null;
          _periods.add(_newDraft());
        }),
        icon: const Icon(Icons.add),
        label: const Text('添加课节时间'),
      ),
      const SizedBox(height: AppLayout.sectionGap),
    ],
  );

  void _changeCalendar() => setState(() {
    _customCalendar = true;
    _error = null;
  });

  void _changeTimes() => setState(() {
    _customTimes = true;
    _error = null;
  });

  void _restoreCalendar() => setState(() {
    _customCalendar = false;
    _error = null;
    _firstMonday.text = _dateText(widget.snapshot.calendar.firstWeekMonday);
    _totalWeeks.text = widget.snapshot.calendar.totalWeeks?.toString() ?? '';
  });

  void _restoreTimes() => setState(() {
    _customTimes = false;
    _error = null;
    _periods = widget.snapshot.periodTimes.map(_newDraft).toList();
  });

  Future<void> _pickMonday() async {
    final current = _civilDate(_firstMonday.text);
    final validMonday = current?.weekday == DateTime.monday ? current : null;
    final picked = await showDatePicker(
      context: context,
      initialDate: validMonday,
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
      currentDate: widget.today,
      selectableDayPredicate: (date) => date.weekday == DateTime.monday,
      helpText: '选择第一教学周的周一',
      cancelText: '取消',
      confirmText: '选定',
      errorInvalidText: '请选择周一',
    );
    if (!mounted || picked == null) return;
    _firstMonday.text = _dateText(picked);
    _changeCalendar();
  }

  Future<void> _setCurrentWeek() async {
    var input = '';
    final form = GlobalKey<FormState>();
    final week = await showDialog<int>(
      context: context,
      builder: (context) {
        void submit() {
          if (form.currentState!.validate()) {
            Navigator.of(context).pop(int.parse(input.trim()));
          }
        }

        return AlertDialog(
          title: const Text('设置当前教学周'),
          scrollable: true,
          content: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('今天是 ${_dateText(widget.today)}。填写学校当前教学周，程序将据此计算第一周的周一。'),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('calendar-current-week-input'),
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  onChanged: (value) => input = value,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '今天是第几教学周',
                    suffixText: '周',
                    errorMaxLines: 3,
                  ),
                  validator: (value) {
                    final number = int.tryParse(value?.trim() ?? '');
                    if (number == null || number < 1) return '请填写大于 0 的教学周';
                    final total = int.tryParse(_totalWeeks.text.trim());
                    if (total != null && total > 0 && number > total) {
                      return '不能超过已填写的 $total 周';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => submit(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(onPressed: submit, child: const Text('确定')),
          ],
        );
      },
    );
    if (!mounted || week == null) return;
    final calendar = TeachingCalendar.fromWeekReference(
      date: widget.today,
      week: week,
      source: TeachingCalendarSource.user,
    );
    _firstMonday.text = _dateText(calendar.firstWeekMonday);
    _changeCalendar();
  }

  Future<void> _pickTime(
    TextEditingController controller, {
    required bool isEnd,
  }) async {
    final existing = _minutes(controller.text);
    final initial = existing == null || existing == PeriodTime.minutesPerDay
        ? TimeOfDay(hour: widget.today.hour, minute: widget.today.minute)
        : TimeOfDay(hour: existing ~/ 60, minute: existing % 60);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      initialEntryMode: TimePickerEntryMode.input,
      emptyInitialInput: existing == null,
      helpText: isEnd ? '选择结束时间' : '选择开始时间',
      cancelText: '取消',
      confirmText: '选定',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (!mounted || picked == null) return;
    controller.text = _timeText(picked.hour * 60 + picked.minute);
    _changeTimes();
  }

  TeachingCalendar _draftCalendar() => TeachingCalendar(
    firstWeekMonday: _civilDate(_firstMonday.text),
    totalWeeks: _totalWeeks.text.trim().isEmpty
        ? null
        : int.parse(_totalWeeks.text.trim()),
    source: TeachingCalendarSource.user,
    sourceLabel: '用户校正',
  );

  String get _calendarPreview {
    if (_dateError(_firstMonday.text) != null ||
        _totalWeeksError(_totalWeeks.text) != null) {
      return '填写有效校历后可预览今天的教学周。';
    }
    final calendar = _customCalendar
        ? _draftCalendar()
        : widget.snapshot.calendar;
    final position = calendar.positionOn(widget.today);
    return switch (position.status) {
      TeachingWeekStatus.unknown => '当前教学周待确认',
      TeachingWeekStatus.beforeTerm => '今天处于开学前',
      TeachingWeekStatus.inTerm => '按此校历，今天是第 ${position.week} 教学周',
      TeachingWeekStatus.afterTerm => '按此校历，本学期已经结束',
    };
  }

  Future<void> _save() async {
    _formKey.currentState!.validate();
    final calendarError =
        _dateError(_firstMonday.text) ?? _totalWeeksError(_totalWeeks.text);
    if (calendarError != null) {
      _showError(calendarError);
      return;
    }
    final times = _customTimes
        ? _readPeriods()
        : (values: <PeriodTime>[], error: null);
    if (times.error != null) {
      _showError(times.error!);
      return;
    }
    final settings = widget.settings.copyWith(
      calendarOverride: _customCalendar ? _draftCalendar() : null,
      clearCalendarOverride: !_customCalendar,
      periodTimes: times.values,
      useCustomPeriodTimes: _customTimes,
    );
    final save = widget.onSave;
    if (save != null) {
      FocusScope.of(context).unfocus();
      setState(() => _saving = true);
      final error = await save(settings);
      if (!mounted) return;
      setState(() => _saving = false);
      if (error != null) {
        _showError(error);
        return;
      }
    }
    if (mounted) Navigator.of(context).pop(settings);
  }

  ({List<PeriodTime> values, String? error}) _readPeriods() {
    final values = <PeriodTime>[];
    final identities = <(String?, int)>{};
    for (var index = 0; index < _periods.length; index++) {
      final draft = _periods[index];
      final error =
          _periodNumberError(draft.number.text) ??
          _timeError(draft.start.text, isEnd: false) ??
          _timeError(draft.end.text, isEnd: true);
      if (error != null) return (values: [], error: '作息 ${index + 1}：$error');
      final number = int.parse(draft.number.text);
      final start = _minutes(draft.start.text)!;
      final end = _minutes(draft.end.text)!;
      if (start >= end) {
        return (values: [], error: '作息 ${index + 1}：结束时间必须晚于开始时间');
      }
      final campus = draft.campus.text.trim().isEmpty
          ? null
          : draft.campus.text.trim();
      if (!identities.add((campus, number))) {
        return (
          values: [],
          error: '${campus ?? '未指定校区'}的第 $number 节重复，请合并或修改节次',
        );
      }
      values.add(
        PeriodTime(
          number: number,
          startMinutes: start,
          endMinutes: end,
          campus: campus,
        ),
      );
    }
    values.sort((left, right) {
      final campus = (left.campus ?? '').compareTo(right.campus ?? '');
      return campus == 0 ? left.number.compareTo(right.number) : campus;
    });
    for (var index = 1; index < values.length; index++) {
      final previous = values[index - 1];
      final current = values[index];
      if (previous.campus == current.campus &&
          previous.endMinutes > current.startMinutes) {
        return (
          values: [],
          error:
              '${current.campus ?? '未指定校区'}的第 ${current.number} 节早于或重叠第 ${previous.number} 节，请核对时间',
        );
      }
    }
    return (values: values, error: null);
  }

  void _showError(String error) {
    setState(() => _error = error);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _errorFocus.requestFocus();
    });
  }
}

final class _PeriodDraft {
  _PeriodDraft(this.id, PeriodTime? value)
    : number = TextEditingController(text: value?.number.toString() ?? ''),
      campus = TextEditingController(text: value?.campus ?? ''),
      start = TextEditingController(
        text: value == null ? '' : _timeText(value.startMinutes),
      ),
      end = TextEditingController(
        text: value == null ? '' : _timeText(value.endMinutes),
      );

  final int id;
  final TextEditingController number;
  final TextEditingController campus;
  final TextEditingController start;
  final TextEditingController end;

  void dispose() {
    number.dispose();
    campus.dispose();
    start.dispose();
    end.dispose();
  }
}

String _dateText(DateTime? date) => date == null
    ? ''
    : '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';

DateTime? _civilDate(String text) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text.trim());
  if (match == null) return null;
  final date = DateTime(
    int.parse(match[1]!),
    int.parse(match[2]!),
    int.parse(match[3]!),
  );
  return _dateText(date) == text.trim() ? date : null;
}

String? _dateError(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final date = _civilDate(value);
  if (date == null || date.year < 1) return '请按 YYYY-MM-DD 填写有效日期';
  return date.weekday == DateTime.monday ? null : '第一教学周必须从周一开始';
}

String? _totalWeeksError(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final weeks = int.tryParse(value.trim());
  return weeks == null || weeks < 1 ? '总教学周数必须是大于 0 的整数，或留空' : null;
}

String? _periodNumberError(String? value) {
  final number = int.tryParse(value?.trim() ?? '');
  return number == null || number < 1 ? '请填写大于 0 的节次' : null;
}

int? _minutes(String value) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
  if (match == null) return null;
  final hour = int.parse(match[1]!);
  final minute = int.parse(match[2]!);
  if (minute > 59 || hour > 24 || (hour == 24 && minute != 0)) return null;
  return hour * 60 + minute;
}

String? _timeError(String? value, {required bool isEnd}) {
  final minutes = _minutes(value ?? '');
  if (minutes == null || (!isEnd && minutes >= PeriodTime.minutesPerDay)) {
    return '请填写有效的 24 小时制时间，如 08:30';
  }
  return null;
}

String _timeText(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';
