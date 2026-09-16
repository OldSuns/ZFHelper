import 'package:flutter/material.dart';

import '../../auth/view_models/auth_view_model.dart';
import '../../courses/view_models/courses_view_model.dart';
import '../../grades/view_models/grades_view_model.dart';
import '../../schedule/view_models/timetable_view_model.dart';
import '../view_models/appearance_view_model.dart';
import '../view_models/schedule_widget_view_model.dart';
import '../widgets/settings_section.dart';
import 'account_settings_page.dart';
import 'app_settings_page.dart';
import 'display_settings_page.dart';
import 'schedule_settings_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    required this.auth,
    required this.appearance,
    required this.timetable,
    required this.grades,
    required this.courses,
    this.scheduleWidget,
    super.key,
  });

  final AuthViewModel auth;
  final AppearanceViewModel appearance;
  final TimetableViewModel timetable;
  final GradesViewModel grades;
  final CoursesViewModel courses;
  final ScheduleWidgetViewModel? scheduleWidget;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([auth, appearance]),
    builder: (context, _) {
      final school = auth.state.profile?.name;
      final account = auth.state.selectedAccount?.account;
      return SettingsPageScaffold(
        title: '设置',
        children: [
          SettingsSection(
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
                    builder: (context) => AccountSettingsPage(viewModel: auth),
                  ),
                ),
              ),
              SettingsEntry(
                icon: Icons.palette_outlined,
                title: '显示',
                subtitle:
                    appearance.failure ??
                    (appearance.busy ? '正在保存或读取外观设置…' : appearance.label),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (context) =>
                        DisplaySettingsPage(viewModel: appearance),
                  ),
                ),
              ),
              SettingsEntry(
                icon: Icons.calendar_view_week_outlined,
                title: '课表',
                subtitle: '导入与管理课表、校历作息、桌面小组件',
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (context) => ScheduleSettingsPage(
                      viewModel: timetable,
                      scheduleWidget: scheduleWidget,
                    ),
                  ),
                ),
              ),
              SettingsEntry(
                icon: Icons.settings_applications_outlined,
                title: '数据与应用',
                subtitle: '本地数据、更新与应用信息',
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (context) => AppSettingsPage(
                      timetable: timetable,
                      grades: grades,
                      courses: courses,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
}
