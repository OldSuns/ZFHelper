import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zf_core/zf_core.dart';

import '../../../core/app_theme.dart';
import '../view_models/period_times_view_model.dart';
import '../view_models/timetable_view_model.dart';
import 'period_times_editor.dart';

Future<bool> showScheduleCalendar(
  BuildContext context,
  TimetableViewModel viewModel,
) async {
  final snapshot = viewModel.imported;
  final target = viewModel.editTarget;
  if (snapshot == null || target == null) return false;
  final settings = viewModel.settings;
  final today = viewModel.today;
  final saved = await Navigator.of(context).push<ScheduleSettings>(
    MaterialPageRoute(
      builder: (context) => ScheduleCalendarPage(
        snapshot: snapshot,
        settings: settings,
        today: today,
        onSave: (value) async =>
            await viewModel.saveSettings(
              value,
              target: target,
              original: settings,
              originalImport: snapshot,
            )
            ? null
            : viewModel.data.failure?.message ?? '保存未完成，请重试',
      ),
    ),
  );
  return saved != null;
}

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
  late final TextEditingController _firstMonday;
  late final TextEditingController _totalWeeks;
  late final PeriodTimesViewModel _times;
  late bool _customCalendar;
  String? _error;
  bool _saving = false;
  bool _confirmingClose = false;

  @override
  void initState() {
    super.initState();
    _customCalendar = widget.settings.calendarOverride != null;
    final calendar =
        widget.settings.calendarOverride ?? widget.snapshot.calendar;
    _firstMonday = TextEditingController(
      text: _dateText(calendar.firstWeekMonday),
    );
    _totalWeeks = TextEditingController(
      text: calendar.totalWeeks?.toString() ?? '',
    );
    _times = PeriodTimesViewModel(
      schoolTimes: widget.snapshot.periodTimes,
      settings: widget.settings,
    )..addListener(_timesChanged);
  }

  @override
  void dispose() {
    _firstMonday.dispose();
    _totalWeeks.dispose();
    _scrollController.dispose();
    _errorFocus.dispose();
    _times.dispose();
    super.dispose();
  }

  void _timesChanged() => setState(() => _error = null);

  bool get _hasChanges {
    final original =
        widget.settings.calendarOverride ?? widget.snapshot.calendar;
    return _times.hasChanges ||
        _customCalendar != (widget.settings.calendarOverride != null) ||
        _firstMonday.text != _dateText(original.firstWeekMonday) ||
        _totalWeeks.text != (original.totalWeeks?.toString() ?? '');
  }

  Future<void> _cancel() async {
    if (_saving || _confirmingClose) return;
    if (!_hasChanges) {
      Navigator.pop(context);
      return;
    }
    _confirmingClose = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃未保存的修改？'),
        content: const Text('校历和作息预览尚未保存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('放弃修改'),
          ),
        ],
      ),
    );
    _confirmingClose = false;
    if (mounted && discard == true) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => PopScope<ScheduleSettings>(
    canPop: !_saving && !_hasChanges,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _cancel();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '取消设置',
          icon: const Icon(Icons.close),
          onPressed: _saving ? null : _cancel,
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
                constraints: const BoxConstraints(
                  maxWidth: AppLayout.contentMaxWidth,
                ),
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
                        PeriodTimesEditor(viewModel: _times),
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
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppLayout.contentMaxWidth,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                12 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('calendar-save'),
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? '正在保存…' : '保存设置'),
                ),
              ),
            ),
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
      ],
    );
  }

  void _changeCalendar() => setState(() {
    _customCalendar = true;
    _error = null;
  });

  void _restoreCalendar() => setState(() {
    _customCalendar = false;
    _error = null;
    _firstMonday.text = _dateText(widget.snapshot.calendar.firstWeekMonday);
    _totalWeeks.text = widget.snapshot.calendar.totalWeeks?.toString() ?? '';
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
    final timeError = _times.useCustomTimes ? _times.validationError : null;
    if (timeError != null) {
      _showError('作息预览存在冲突，修正后才能保存：$timeError');
      return;
    }
    final settings = widget.settings.copyWith(
      calendarOverride: _customCalendar ? _draftCalendar() : null,
      clearCalendarOverride: !_customCalendar,
      periodTimes: _times.useCustomTimes ? _times.plan.periods : const [],
      periodSections: _times.useCustomTimes ? _times.plan.sections : const [],
      useCustomPeriodTimes: _times.useCustomTimes,
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

  void _showError(String error) {
    setState(() => _error = error);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _errorFocus.requestFocus();
    });
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
