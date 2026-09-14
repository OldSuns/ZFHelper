import 'package:flutter/material.dart';
import 'package:zf_core/zf_core.dart';

import '../../../../data/repositories/schedule_repository.dart';
import '../../../core/adaptive_sheet.dart';
import '../../schedule/view_models/timetable_view_model.dart';
import '../../schedule/views/course_editor_page.dart';
import '../../schedule/views/schedule_calendar_page.dart';
import '../../schedule/views/schedule_picker_sheets.dart';
import '../widgets/settings_section.dart';

class ScheduleSettingsSection extends StatelessWidget {
  const ScheduleSettingsSection({required this.viewModel, super.key});

  final TimetableViewModel viewModel;

  void _message(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _refresh(
    BuildContext context, {
    bool useSchoolDefault = false,
  }) async {
    final scope = viewModel.account?.account.scope;
    final saved = await viewModel.refresh(useSchoolDefault: useSchoolDefault);
    if (!context.mounted || viewModel.account?.account.scope != scope) return;
    if (!saved) {
      if (viewModel.data.failure?.kind == ScheduleFailureKind.termSelection) {
        await _chooseTerm(context, importAfterSelection: true);
      }
      return;
    }
    if (viewModel.schedule == null ||
        (useSchoolDefault &&
            viewModel.account?.catalog?.selectedTerm == null)) {
      _message(context, '学校没有指定默认学期，请选择学期后导入');
      await _chooseTerm(context, importAfterSelection: true);
      return;
    }
    _message(
      context,
      viewModel.schedule!.importWarnings.isEmpty
          ? '课表已保存在本机，下次主动更新前一直可用'
          : '课表已保存在本机，请查看下方的导入提示',
    );
  }

  Future<void> _chooseTerm(
    BuildContext context, {
    bool importAfterSelection = false,
  }) async {
    final selected = await selectScheduleTerm(
      context,
      viewModel,
      forImport: importAfterSelection,
    );
    if (selected && importAfterSelection && context.mounted) {
      await _refresh(context);
    }
  }

  Future<void> _calendar(BuildContext context) async {
    if (await showScheduleCalendar(context, viewModel) && context.mounted) {
      _message(context, '校历与作息已保存');
    }
  }

  Future<void> _addCourse(BuildContext context) async {
    if (await showScheduleCourseEditor(context, viewModel) && context.mounted) {
      _message(context, '课程已保存到本机');
    }
  }

  Future<void> _toggleAgenda(BuildContext context) async {
    if (!await viewModel.toggleAgenda() && context.mounted) {
      _message(context, viewModel.data.failure?.message ?? '课表显示方式未能保存');
    }
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String action,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _restore(BuildContext context) async {
    final target = viewModel.editTarget;
    if (target == null ||
        !await _confirm(
          context,
          title: '恢复学校上课安排？',
          message: '取消对学校安排的隐藏和本地调整，保留另外添加的本地课程。',
          action: '恢复',
        ) ||
        !context.mounted) {
      return;
    }
    final saved = await viewModel.restoreHiddenEntries(target: target);
    if (saved && context.mounted) _message(context, '学校上课安排已恢复');
  }

  Future<void> _accounts(BuildContext context) async {
    final accounts = viewModel.data.library.accounts;
    final action = await showAdaptiveSheet<({AccountScope scope, bool remove})>(
      context: context,
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .75,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                '本机保存的课表',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            for (final account in accounts)
              ListTile(
                title: Text(
                  '${account.account.schoolName} · ${account.account.accountName}',
                ),
                subtitle: Text(
                  '${account.account.loginName} · ${account.schedules.length} 个学期',
                ),
                selected:
                    account.account.scope == viewModel.account?.account.scope,
                onTap: () =>
                    Navigator.of(context)
                        .pop((scope: account.account.scope, remove: false)),
                trailing: IconButton(
                  tooltip: '清除此账号的课表',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () =>
                      Navigator.of(context)
                          .pop((scope: account.account.scope, remove: true)),
                ),
              ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    if (!action.remove) {
      await viewModel.selectAccount(action.scope);
      return;
    }
    final record = accounts.firstWhere(
      (item) => item.account.scope == action.scope,
    );
    if (!await _confirm(
          context,
          title: '清除此账号的本机课表？',
          message:
              '${record.account.schoolName} · ${record.account.accountName} 的所有已保存学期、本地课程和校历校正将被清除。学校数据不受影响。',
          action: '清除课表',
        ) ||
        !context.mounted) {
      return;
    }
    if (await viewModel.removeSavedAccount(action.scope) && context.mounted) {
      _message(context, '此账号的本机课表已清除');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: viewModel,
    builder: (context, _) {
      final account = viewModel.account?.account;
      final term = viewModel.selectedTerm;
      final busy = viewModel.data.loading || viewModel.data.refreshing;
      final canEdit =
          viewModel.imported != null && viewModel.editTarget != null;
      final failure = viewModel.data.failure;
      final warnings = viewModel.imported?.importWarnings ?? const <String>[];
      return SettingsSection(
        title: '课表',
        children: [
          if (busy) const LinearProgressIndicator(minHeight: 2),
          if (failure != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        failure.message,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                  if (failure.kind == ScheduleFailureKind.storage)
                    TextButton(
                      onPressed: busy ? null : viewModel.retryLocalLoad,
                      child: const Text('重试读取'),
                    ),
                  IconButton(
                    tooltip: '关闭课表错误提示',
                    onPressed: viewModel.dismissFailure,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          SettingsEntry(
            icon: Icons.date_range_outlined,
            title: '课表学期',
            subtitle: account == null
                ? '添加教务账号后可选择学年与学期'
                : '${account.schoolName} · ${account.loginName}\n'
                      '${term?.label ?? '尚未选择，导入时读取学校当前学期'}',
            onTap: account != null && !busy ? () => _chooseTerm(context) : null,
          ),
          SettingsEntry(
            icon: Icons.sync_rounded,
            title: viewModel.hasSchedule ? '更新课表' : '导入课表',
            subtitle: viewModel.canRefresh
                ? '获取所选学期，保留本地课程与校历设置'
                : '请先在“账号与学校”中登录课表所属账号',
            onTap: viewModel.canRefresh && !busy
                ? () => _refresh(context)
                : null,
          ),
          if (term != null)
            SettingsEntry(
              icon: Icons.school_outlined,
              title: '导入教务当前学期',
              subtitle: '重新读取学校当前学期，可用于新学期切换',
              onTap: viewModel.canRefresh && !busy
                  ? () => _refresh(context, useSchoolDefault: true)
                  : null,
            ),
          if (warnings.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('导入提示'),
              subtitle: Text(warnings.join('\n')),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 8,
              ),
            ),
          SettingsEntry(
            icon: Icons.add_rounded,
            title: '添加课程',
            subtitle: '向当前学期添加本地课程',
            onTap: canEdit && !busy ? () => _addCourse(context) : null,
          ),
          SettingsEntry(
            icon: Icons.schedule_outlined,
            title: '校历与作息',
            subtitle: '设置当前学期的教学周与上课时间',
            onTap: canEdit && !busy ? () => _calendar(context) : null,
          ),
          SwitchListTile.adaptive(
            secondary: const Icon(Icons.view_agenda_outlined),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 8,
            ),
            title: const Text('课表日程视图'),
            subtitle: Text(viewModel.agenda ? '当前学期按天显示课程列表' : '当前学期显示每周课程网格'),
            value: viewModel.agenda,
            onChanged: canEdit && !busy ? (_) => _toggleAgenda(context) : null,
          ),
          if (viewModel.settings.hiddenEntryIds.isNotEmpty)
            SettingsEntry(
              icon: Icons.restore_rounded,
              title: '恢复学校安排',
              subtitle: '撤销对学校课程的隐藏与本地调整',
              onTap: canEdit && !busy ? () => _restore(context) : null,
            ),
          SettingsEntry(
            icon: Icons.folder_outlined,
            title: '本机保存的课表',
            subtitle: '切换或清除账号的离线课表',
            onTap: !busy && viewModel.data.library.accounts.isNotEmpty
                ? () => _accounts(context)
                : null,
          ),
        ],
      );
    },
  );
}
