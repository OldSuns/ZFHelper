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
        children: [
          Text('课表桌面小组件目前支持 Android。'),
          SizedBox(height: 12),
          Text('在 Android 设备上，可以长按桌面，从小组件列表添加 ZFHelper 课表。'),
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
                        '默认约占 3×2 格，可缩至约 2×1 格，实际占格由桌面决定。低矮时显示课程与时间摘要，增高后补充地点或切换为可滚动课表；窄布局自动纵向排列。点击课程可打开对应日期的日程。',
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '跟随应用当前选择的账号、学期和外观。已保存的课程可以离线查看，课表和校历修改后自动同步。',
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
              '也可长按桌面添加小组件，长按已添加的小组件调整大小。显示按系统周期和课程边界刷新；系统省电时可能延迟，宽列表提供刷新按钮，也可在此重新同步。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      },
    );
  }

  static String _timestamp(DateTime value) =>
      '${value.month}月${value.day}日 ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
