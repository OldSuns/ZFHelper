import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../schedule/view_models/timetable_view_model.dart';
import '../view_models/schedule_widget_view_model.dart';
import '../widgets/settings_section.dart';
import 'schedule_settings_section.dart';
import 'schedule_widget_settings_page.dart';

class ScheduleSettingsPage extends StatelessWidget {
  const ScheduleSettingsPage({
    required this.viewModel,
    this.scheduleWidget,
    super.key,
  });

  final TimetableViewModel viewModel;
  final ScheduleWidgetViewModel? scheduleWidget;

  @override
  Widget build(BuildContext context) => SettingsPageScaffold(
    title: '课表',
    children: [
      ScheduleSettingsSection(viewModel: viewModel, title: null),
      const SizedBox(height: AppLayout.sectionGap),
      SettingsSection(
        children: [
          SettingsEntry(
            icon: Icons.widgets_outlined,
            title: '桌面小组件',
            subtitle: '在 Android 桌面查看课程安排',
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (context) =>
                    ScheduleWidgetSettingsPage(viewModel: scheduleWidget),
              ),
            ),
          ),
        ],
      ),
    ],
  );
}
