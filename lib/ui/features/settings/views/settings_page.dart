import 'package:flutter/material.dart';

import '../../../../data/storage/appearance_store.dart';
import '../../../core/app_theme.dart';
import '../../auth/view_models/auth_view_model.dart';
import '../../courses/view_models/courses_view_model.dart';
import '../../grades/view_models/grades_view_model.dart';
import '../../schedule/view_models/timetable_view_model.dart';
import '../view_models/appearance_view_model.dart';
import '../widgets/settings_section.dart';
import 'account_settings_page.dart';
import 'local_data_page.dart';
import 'schedule_settings_section.dart';

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

  void _message(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _showAbout(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.school_outlined, size: 40),
      title: const Text('ZFHelper'),
      scrollable: true,
      content: const Text('0.1.0\n\n新正方教务助手，提供课表、选课与成绩查询。'),
      actions: [
        const TextButton(onPressed: null, child: Text('Github')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );

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
            listenable: Listenable.merge([auth, appearance]),
            builder: (context, _) {
              final state = auth.state;
              final school = state.profile?.name;
              final account = state.selectedAccount?.account;
              return ListView(
                key: const PageStorageKey('settings-home'),
                padding: const EdgeInsets.all(AppLayout.workspacePadding),
                children: [
                  SettingsSection(
                    title: '账号',
                    children: [
                      SettingsEntry(
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
                  SettingsSection(
                    title: '显示',
                    children: [
                      SettingsEntry(
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
                    ],
                  ),
                  const SizedBox(height: AppLayout.sectionGap),
                  ScheduleSettingsSection(viewModel: timetable),
                  const SizedBox(height: AppLayout.sectionGap),
                  SettingsSection(
                    title: '数据与应用',
                    children: [
                      SettingsEntry(
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
                      const SettingsEntry(
                        icon: Icons.system_update_alt_rounded,
                        title: '检查更新',
                        subtitle: '暂未开放',
                        onTap: null,
                      ),
                      SettingsEntry(
                        icon: Icons.info_outline,
                        title: '关于应用',
                        subtitle: 'ZFHelper · 0.1.0',
                        onTap: () => _showAbout(context),
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
