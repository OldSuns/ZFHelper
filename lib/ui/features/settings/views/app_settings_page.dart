import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../courses/view_models/courses_view_model.dart';
import '../../grades/view_models/grades_view_model.dart';
import '../../schedule/view_models/timetable_view_model.dart';
import '../../../../data/repositories/release_repository.dart';
import '../view_models/update_check_view_model.dart';
import '../widgets/settings_section.dart';
import 'local_data_page.dart';
import 'update_check_page.dart';

class AppSettingsPage extends StatelessWidget {
  const AppSettingsPage({
    required this.timetable,
    required this.grades,
    required this.courses,
    required this.updateCheck,
    super.key,
  });

  final TimetableViewModel timetable;
  final GradesViewModel grades;
  final CoursesViewModel courses;
  final UpdateCheckViewModel updateCheck;

  Future<void> _showAbout(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) => AlertDialog(
        icon: const Icon(Icons.school_outlined, size: 40),
        title: const Text('ZFHelper'),
        scrollable: true,
        content: Text(
          '${snapshot.data?.version ?? '读取版本中…'}\n\n新正方教务助手，提供课表、选课与成绩查询。',
        ),
        actions: [
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse(githubRepositoryUrl),
              mode: LaunchMode.externalApplication,
            ),
            child: const Text('Github'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
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
          SettingsEntry(
            icon: Icons.system_update_alt_rounded,
            title: '检查更新',
            subtitle: '查看 GitHub Release 与更新说明',
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (context) => UpdateCheckPage(viewModel: updateCheck),
              ),
            ),
          ),
          SettingsEntry(
            icon: Icons.info_outline,
            title: '关于应用',
            subtitle: 'ZFHelper · 查看版本信息',
            onTap: () => _showAbout(context),
          ),
        ],
      ),
    ],
  );
}
