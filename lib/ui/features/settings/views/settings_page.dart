import 'package:flutter/material.dart';

import '../../../../data/storage/appearance_store.dart';
import '../../../core/app_theme.dart';
import '../../auth/view_models/auth_view_model.dart';
import '../../courses/view_models/courses_view_model.dart';
import '../../grades/view_models/grades_view_model.dart';
import '../../schedule/view_models/timetable_view_model.dart';
import '../../schedule/views/schedule_calendar_page.dart';
import '../view_models/appearance_view_model.dart';
import 'account_settings_page.dart';
import 'local_data_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    required this.auth,
    required this.appearance,
    required this.timetable,
    required this.grades,
    required this.courses,
    super.key,
  });

  final AuthViewModel auth;
  final AppearanceViewModel appearance;
  final TimetableViewModel timetable;
  final GradesViewModel grades;
  final CoursesViewModel courses;

  Future<void> _chooseAppearance(BuildContext context) async {
    final selected = await showDialog<AppAppearance>(
      context: context,
      builder: (context) => RadioGroup<AppAppearance>(
        groupValue: appearance.initialized ? appearance.appearance : null,
        onChanged: (value) => Navigator.of(context).pop(value),
        child: SimpleDialog(
          title: const Text('选择外观'),
          children: [
            for (final value in AppAppearance.values)
              RadioListTile<AppAppearance>(
                value: value,
                title: Text(AppearanceViewModel.labelFor(value)),
                subtitle: value == AppAppearance.system
                    ? const Text('随设备的浅色或深色模式切换')
                    : null,
              ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    final saved = await appearance.select(selected);
    if (!saved && context.mounted) {
      _message(context, appearance.failure ?? '外观设置正在保存，请稍后重试');
    }
  }

  Future<void> _calendar(BuildContext context) async {
    if (await showScheduleCalendar(context, timetable) && context.mounted) {
      _message(context, '校历与作息已保存');
    }
  }

  Future<void> _toggleAgenda(BuildContext context) async {
    if (!await timetable.toggleAgenda() && context.mounted) {
      _message(context, timetable.data.failure?.message ?? '课表显示方式未能保存');
    }
  }

  void _message(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('设置')),
    body: SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListenableBuilder(
            listenable: Listenable.merge([auth, appearance, timetable]),
            builder: (context, _) {
              final state = auth.state;
              final school = state.profile?.name;
              final account = state.selectedAccount?.account;
              final scheduleAccount = timetable.account?.account;
              final term = timetable.selectedTerm;
              final canConfigureSchedule =
                  timetable.imported != null && timetable.editTarget != null;
              final scheduleLabel = canConfigureSchedule
                  ? '${scheduleAccount!.schoolName} · ${scheduleAccount.loginName}\n${term!.label}'
                  : '导入课表后可设置教学周与上课时间';
              return ListView(
                key: const PageStorageKey('settings-home'),
                padding: const EdgeInsets.all(AppLayout.workspacePadding),
                children: [
                  _SettingsSection(
                    title: '账号',
                    children: [
                      _SettingsEntry(
                        icon: Icons.manage_accounts_outlined,
                        title: '账号与学校',
                        subtitle: school == null
                            ? '添加学校与教务账号'
                            : account == null
                            ? '$school · 管理学校与教务账号'
                            : '$school · ${account.displayName}（${account.loginName}）',
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (context) =>
                                AccountSettingsPage(viewModel: auth),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppLayout.sectionGap),
                  _SettingsSection(
                    title: '显示与课表',
                    children: [
                      _SettingsEntry(
                        icon: Icons.palette_outlined,
                        title: '外观',
                        subtitle:
                            appearance.failure ??
                            (appearance.busy
                                ? '正在保存或读取外观设置…'
                                : appearance.label),
                        onTap: appearance.busy
                            ? null
                            : () => _chooseAppearance(context),
                      ),
                      if (appearance.failure != null && !appearance.initialized)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 60, bottom: 8),
                            child: TextButton(
                              onPressed: appearance.busy
                                  ? null
                                  : appearance.initialize,
                              child: const Text('重试读取外观'),
                            ),
                          ),
                        ),
                      _SettingsEntry(
                        icon: Icons.schedule_outlined,
                        title: '教学周与作息',
                        subtitle: scheduleLabel,
                        onTap: canConfigureSchedule
                            ? () => _calendar(context)
                            : null,
                      ),
                      SwitchListTile.adaptive(
                        secondary: const Icon(Icons.view_agenda_outlined),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        title: const Text('课表日程视图'),
                        subtitle: Text(
                          canConfigureSchedule
                              ? '按日列出课程；此选项只用于上方账号的当前学期'
                              : '导入课表后可切换周课表或日程列表',
                        ),
                        value: timetable.agenda,
                        onChanged: canConfigureSchedule
                            ? (_) => _toggleAgenda(context)
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppLayout.sectionGap),
                  _SettingsSection(
                    title: '数据与应用',
                    children: [
                      _SettingsEntry(
                        icon: Icons.storage_outlined,
                        title: '本地数据',
                        subtitle: '查看各账号保存的课表、成绩与选课数据',
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (context) => LocalDataPage(
                              timetable: timetable,
                              grades: grades,
                              courses: courses,
                            ),
                          ),
                        ),
                      ),
                      _SettingsEntry(
                        icon: Icons.info_outline,
                        title: '关于应用',
                        subtitle: 'ZFHelper · 0.1.0',
                        onTap: () => showAboutDialog(
                          context: context,
                          applicationName: 'ZFHelper',
                          applicationVersion: '0.1.0',
                          applicationIcon: const Icon(
                            Icons.school_outlined,
                            size: 40,
                          ),
                          children: [const Text('新正方教务助手，提供课表、选课与成绩查询。')],
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      ListTileTheme.merge(
        minLeadingWidth: 24,
        horizontalTitleGap: 16,
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                if (index > 0)
                  const Divider(height: 1, indent: 60, endIndent: 20),
                children[index],
              ],
            ],
          ),
        ),
      ),
    ],
  );
}

class _SettingsEntry extends StatelessWidget {
  const _SettingsEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right),
    enabled: onTap != null,
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    onTap: onTap,
  );
}
