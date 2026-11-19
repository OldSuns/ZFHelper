import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/app_identity.dart';
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
        children: [
          Text('课表桌面小组件目前支持 Android。'),
          SizedBox(height: 12),
          Text('在 Android 设备上，可以长按桌面，从小组件列表添加$appDisplayName。'),
        ],
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
                      const Text(
                        '小组件随桌面尺寸调整：较矮时显示当前或下一节课，默认 3×2 和较宽的 4×2 都显示可上下滚动的课程列表。实际占格和可用尺寸由桌面决定。',
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '课程名称优先显示。空间充足时，当前课程显示距离下课的时间，今天的下一节课在开课前 30 分钟内显示倒计时。点击小组件可打开周课表。',
                      ),
                      const SizedBox(height: 12),
                      const Text('倒计时显示最近一次刷新时的分钟数，后台刷新可能延迟，不保证每分钟更新。'),
                      const SizedBox(height: 12),
                      const Text(
                        '内容跟随应用当前选择的账号、学期和外观。已保存的课程可以离线查看，课表和校历修改后自动同步。',
                      ),
                      const SizedBox(height: 12),
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
                  subtitle: const Text('显示正在进行课程的剩余时间，以及 30 分钟内的下一节课倒计时'),
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
                  subtitle: const Text('在课程卡片中显示教室或地点'),
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
                  subtitle: const Text('宽版小组件空间充足时显示授课教师'),
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
                    subtitle: const Text('无法读取设置时，可将三个显示选项恢复为默认开启'),
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
            const SizedBox(height: AppLayout.sectionGap),
            Text(
              '也可长按桌面添加小组件，长按已添加的小组件调整大小。课程、外观或这些显示设置变化后会自动同步；系统省电时可能延迟后台刷新。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
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
        content: const Text('课程倒计时、上课地点和教师信息将恢复为开启。已添加的小组件会立即更新，课表和外观设置保持不变。'),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('正在同步或更新小组件，请稍后重新重置显示设置。')),
        );
        return;
      }
      await model.resetSettings();
    }
  }

  static String _timestamp(DateTime value) =>
      '${value.month}月${value.day}日 ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
