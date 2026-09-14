import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zf_core/zf_core.dart';

import '../../../../data/repositories/course_repository.dart';
import '../../../../platform/selection_runtime.dart';
import '../view_models/courses_view_model.dart';
import 'course_list_tile.dart';

class CourseDetailsSheet extends StatefulWidget {
  const CourseDetailsSheet({
    required this.viewModel,
    required this.requestedCourse,
    required this.requestScope,
    required this.initialFuture,
    required this.onOpenSettings,
    super.key,
  });

  final CoursesViewModel viewModel;
  final CourseOffering requestedCourse;
  final AccountScope requestScope;
  final Future<CourseDetails?> initialFuture;
  final VoidCallback onOpenSettings;

  @override
  State<CourseDetailsSheet> createState() => _CourseDetailsSheetState();
}

class _CourseDetailsSheetState extends State<CourseDetailsSheet> {
  late Future<CourseDetails?> _future;
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  final _interval = TextEditingController(text: '5');
  final _duration = TextEditingController(text: '30');
  String? _selectedKey;
  String? _failure;
  SelectionMode _mode = SelectionMode.immediate;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _future = widget.initialFuture;
  }

  @override
  void dispose() {
    _scroll.dispose();
    _interval.dispose();
    _duration.dispose();
    super.dispose();
  }

  void _retry() {
    if (widget.viewModel.account?.account.scope != widget.requestScope) {
      setState(() => _failure = '正在查看的账号已切换，请关闭详情后重新选择课程。');
      return;
    }
    setState(() {
      _selectedKey = null;
      _failure = null;
      _future = widget.viewModel.sections(widget.requestedCourse);
    });
  }

  Future<void> _start(CourseDetails details, CourseSection section) async {
    if (_starting) return;
    final formValid = _form.currentState?.validate() ?? false;
    if (_mode == SelectionMode.watch) {
      final intervalError = _positiveDuration(_interval.text, minutes: false);
      final durationError = _positiveDuration(_duration.text, minutes: true);
      if (intervalError != null || durationError != null) {
        _showFailure(
          intervalError != null ? '检查间隔：$intervalError' : '持续时间：$durationError',
        );
        return;
      }
    }
    if (!formValid) return;
    setState(() {
      _starting = true;
      _failure = null;
    });
    final started = await widget.viewModel.start(
      details,
      section,
      mode: _mode,
      interval: _mode == SelectionMode.watch
          ? Duration(seconds: int.parse(_interval.text))
          : const Duration(seconds: 5),
      duration: _mode == SelectionMode.watch
          ? Duration(minutes: int.parse(_duration.text))
          : const Duration(minutes: 30),
    );
    if (!mounted) return;
    if (started) {
      Navigator.of(context).pop(true);
    } else {
      _showFailure(widget.viewModel.data.failure ?? '操作未能启动，请重试。');
    }
  }

  void _showFailure(String message) {
    setState(() {
      _starting = false;
      _failure = message;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .84,
      child: ListenableBuilder(
        listenable: widget.viewModel,
        builder: (context, _) => FutureBuilder<CourseDetails?>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('正在读取学校最新教学班…'),
                  ],
                ),
              );
            }
            final details = snapshot.data;
            if (snapshot.hasError || details == null) {
              return _errorBody(snapshot.error);
            }
            return _content(details);
          },
        ),
      ),
    ),
  );

  Widget _errorBody(Object? error) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.requestedCourse.name,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: Text(
            _failure ??
                widget.viewModel.data.failure ??
                (error == null ? '教学班读取失败，请重新查询。' : '教学班读取失败：$error'),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.tonal(onPressed: _retry, child: const Text('重试')),
            TextButton(
              onPressed: widget.onOpenSettings,
              child: const Text('查看登录状态'),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _content(CourseDetails details) {
    final selected = details.sections
        .where((section) => section.key == _selectedKey)
        .firstOrNull;
    final canQuery = widget.viewModel.canQuery(details.account.scope);
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: RadioGroup<String>(
              groupValue: _selectedKey,
              onChanged: (key) {
                if (!_starting) setState(() => _selectedKey = key);
              },
              child: CustomScrollView(
                controller: _scroll,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverToBoxAdapter(child: _header(details)),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList.list(
                      children: [
                        Text(details.round.label),
                        const SizedBox(height: 4),
                        Text(
                          '${details.course.courseId} · 学分 ${details.course.credit ?? '未提供'}'
                          '\n更新于 ${courseDateTime(details.fetchedAt, seconds: true)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('立即选课'),
                              selected: _mode == SelectionMode.immediate,
                              onSelected: _starting
                                  ? null
                                  : (_) => setState(
                                      () => _mode = SelectionMode.immediate,
                                    ),
                            ),
                            ChoiceChip(
                              label: const Text('持续捡漏'),
                              selected: _mode == SelectionMode.watch,
                              onSelected: _starting
                                  ? null
                                  : (_) => setState(
                                      () => _mode = SelectionMode.watch,
                                    ),
                            ),
                          ],
                        ),
                        if (_mode == SelectionMode.watch) _watchSettings(),
                        const SizedBox(height: 12),
                        Text(
                          details.sections.isEmpty
                              ? '学校当前没有返回可选教学班'
                              : '选择具体教学班',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        if (details.sections.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text('可稍后刷新课程，学校的开放范围可能已变化。'),
                          ),
                      ],
                    ),
                  ),
                  SliverList.separated(
                    itemCount: details.sections.length,
                    itemBuilder: (context, index) {
                      final section = details.sections[index];
                      return RadioListTile<String>(
                        value: section.key,
                        enabled: !_starting && section.isSelected != true,
                        selected: section.key == _selectedKey,
                        title: Text(section.name),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 4),
                          child: Text(
                            [
                              section.teacher ?? '教师未提供',
                              section.time ?? '上课时间未提供',
                              section.location ?? '地点未提供',
                              section.isSelected == true
                                  ? '学校已标记选中'
                                  : courseCapacityLabel(
                                      section.capacity,
                                      section.selected,
                                    ),
                            ].join('\n'),
                          ),
                        ),
                      );
                    },
                    separatorBuilder: (context, _) => const Divider(height: 1),
                  ),
                  if (_failure != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _failure!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: FilledButton.icon(
                onPressed: _starting
                    ? null
                    : !canQuery
                    ? widget.onOpenSettings
                    : selected == null
                    ? null
                    : () => _start(details, selected),
                icon: _starting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _mode == SelectionMode.watch
                            ? Icons.autorenew_rounded
                            : Icons.add_task_rounded,
                      ),
                label: Text(
                  _starting
                      ? '正在启动…'
                      : !canQuery
                      ? '登录此账号后继续'
                      : selected == null
                      ? '请先选择教学班'
                      : _mode == SelectionMode.watch
                      ? '开始捡漏'
                      : '确认选课',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(CourseDetails details) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                details.course.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                '${details.account.schoolName} · ${details.account.accountName}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '关闭教学班详情',
          onPressed: _starting ? null : () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    ),
  );

  Widget _watchSettings() {
    final runtime = widget.viewModel.data.runtime;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final fields = [
              TextFormField(
                controller: _interval,
                enabled: !_starting,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '检查间隔',
                  suffixText: '秒',
                ),
                validator: (value) => _positiveDuration(value, minutes: false),
              ),
              TextFormField(
                controller: _duration,
                enabled: !_starting,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '持续时间',
                  suffixText: '分钟',
                ),
                validator: (value) => _positiveDuration(value, minutes: true),
              ),
            ];
            if (constraints.maxWidth <
                MediaQuery.textScalerOf(context).scale(280)) {
              return Column(
                children: [fields[0], const SizedBox(height: 12), fields[1]],
              );
            }
            return Row(
              children: [
                Expanded(child: fields[0]),
                const SizedBox(width: 12),
                Expanded(child: fields[1]),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          runtime?.reason ??
              switch (runtime?.mode) {
                SelectionRuntimeMode.androidForegroundService =>
                  '开始后显示运行通知，可在通知中停止捡漏。系统结束运行后需手动恢复。',
                SelectionRuntimeMode.process =>
                  '保持软件运行即可持续检查，最小化后仍可捡漏。关闭软件或休眠会中断运行。',
                null => '启动时会检查设备运行条件，停止后可在操作记录中查看结果。',
              },
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

String? _positiveDuration(String? input, {required bool minutes}) {
  final value = int.tryParse(input?.trim() ?? '');
  if (value == null || value <= 0) return '请输入大于 0 的整数';
  final duration = minutes
      ? Duration(minutes: value)
      : Duration(seconds: value);
  if ((minutes ? duration.inMinutes : duration.inSeconds) != value) {
    return '数值过大';
  }
  return null;
}
