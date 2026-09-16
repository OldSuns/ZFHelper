import 'package:flutter/material.dart';

import '../../courses/view_models/courses_view_model.dart';
import '../../grades/view_models/grades_view_model.dart';
import '../../schedule/view_models/timetable_view_model.dart';
import '../widgets/settings_section.dart';
import 'local_data_page.dart';

class AppSettingsPage extends StatelessWidget {
  const AppSettingsPage({
    required this.timetable,
    required this.grades,
    required this.courses,
    super.key,
  });

  final TimetableViewModel timetable;
  final GradesViewModel grades;
  final CoursesViewModel courses;

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
  Widget build(BuildContext context) => SettingsPageScaffold(
    title: '数据与应用',
    children: [
      SettingsSection(
        children: [
          SettingsEntry(
            icon: Icons.storage_outlined,
            title: '本地数据',
            subtitle: '查看各账号保存的课表、日程、成绩与选课数据',
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
}
