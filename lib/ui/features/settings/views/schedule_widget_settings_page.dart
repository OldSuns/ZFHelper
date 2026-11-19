import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../view_models/schedule_widget_view_model.dart';
import '../widgets/settings_section.dart';

class ScheduleWidgetSettingsPage extends StatefulWidget {
  const ScheduleWidgetSettingsPage({required this.viewModel, super.key});
  final ScheduleWidgetViewModel? viewModel;

  @override
  State<ScheduleWidgetSettingsPage> createState() =>
      _ScheduleWidgetSettingsPageState();
}

class _ScheduleWidgetSettingsPageState extends State<ScheduleWidgetSettingsPage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(widget.viewModel?.refreshStatus());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.viewModel?.refreshStatus());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.viewModel;
    if (model == null) {
      return const SettingsPageScaffold(
        title: '桌面小组件',
        children: [Text('仅支持 Android')],
      );
    }
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final capabilities = model.capabilities;
        final lastSync = capabilities?.lastSync;
        return SettingsPageScaffold(
          title: '桌面小组件',
          children: [
            SettingsSection(
              children: [
                ListTile(
                  leading: const Icon(Icons.calendar_view_day_outlined),
                  title: const Text('课表小组件'),
                  subtitle: Text(model.sourceLabel),
                  contentPadding: const EdgeInsets.all(20),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        capabilities == null
                            ? '正在读取桌面小组件状态…'
                            : '已添加 ${capabilities.count} 个小组件',
                      ),
                      if (lastSync != null)
                        Text('最近同步：${_timestamp(lastSync)}'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppLayout.sectionGap),
            SettingsSection(
              title: '显示内容',
              children: [
                SwitchListTile.adaptive(
                  secondary: const Icon(Icons.timer_outlined),
                  title: const Text('显示课程倒计时'),
                  value: model.settings.showCountdown,
                  onChanged: !model.settingsInitialized || model.busy
                      ? null
                      : (value) {
                          unawaited(model.updateSettings(showCountdown: value));
                        },
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                ),
                SwitchListTile.adaptive(
                  secondary: const Icon(Icons.place_outlined),
                  title: const Text('显示上课地点'),
                  value: model.settings.showLocation,
                  onChanged: !model.settingsInitialized || model.busy
                      ? null
                      : (value) {
                          unawaited(model.updateSettings(showLocation: value));
                        },
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                ),
                SwitchListTile.adaptive(
                  secondary: const Icon(Icons.person_outline),
                  title: const Text('显示教师信息'),
                  value: model.settings.showTeacher,
                  onChanged: !model.settingsInitialized || model.busy
                      ? null
                      : (value) {
                          unawaited(model.updateSettings(showTeacher: value));
                        },
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                ),
                if (model.settingsReadFailure != null)
                  ListTile(
                    leading: const Icon(Icons.settings_backup_restore),
                    title: const Text('重置显示设置'),
                    trailing: const Icon(Icons.chevron_right),
                    enabled: !model.busy,
                    onTap: model.busy ? null : () => _resetSettings(model),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppLayout.sectionGap),
            if (model.sourceNotice case final notice?) ...[
              Text(notice),
              const SizedBox(height: 12),
            ],
            if (model.failure case final failure?) ...[
              Semantics(
                liveRegion: true,
                child: Text(
                  failure,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: model.busy || !model.canSync
                      ? null
                      : () async {
                          final message = await model.requestPin();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(content: Text(message)));
                          }
                        },
                  icon: const Icon(Icons.add),
                  label: const Text('添加到桌面'),
                ),
                OutlinedButton.icon(
                  onPressed: model.busy || !model.canSync
                      ? null
                      : model.synchronize,
                  icon: const Icon(Icons.sync),
                  label: const Text('重新同步'),
                ),
              ],
            ),
            if (model.busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        );
      },
    );
  }

  Future<void> _resetSettings(ScheduleWidgetViewModel model) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置小组件显示设置？'),
        content: const Text('重新开启课程倒计时、上课地点和教师信息。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      if (model.busy) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('正在同步，请稍后重试。')));
        return;
      }
      await model.resetSettings();
    }
  }

  static String _timestamp(DateTime value) =>
      '${value.month}月${value.day}日 ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
