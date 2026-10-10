import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../platform/schedule_island_platform.dart';
import '../../../core/app_theme.dart';
import '../view_models/schedule_island_view_model.dart';
import '../widgets/settings_section.dart';

class ScheduleIslandSettingsPage extends StatefulWidget {
  const ScheduleIslandSettingsPage({required this.viewModel, super.key});

  final ScheduleIslandViewModel? viewModel;

  @override
  State<ScheduleIslandSettingsPage> createState() =>
      _ScheduleIslandSettingsPageState();
}

class _ScheduleIslandSettingsPageState extends State<ScheduleIslandSettingsPage>
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
        title: '课程实况与超级岛',
        children: [Text('课程实况通知仅支持 Android 16 或更新版本的设备。')],
      );
    }
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final status = model.status;
        return SettingsPageScaffold(
          title: '课程实况与超级岛',
          children: [
            if (model.busy) ...[
              const LinearProgressIndicator(semanticsLabel: '正在读取或保存课程实况设置'),
              const SizedBox(height: AppLayout.sectionGap),
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
            if (status == null)
              Text(model.busy ? '正在读取课程实况设置…' : '尚未读取课程实况设置。')
            else ...[
              _reminderSettings(model, status),
              const SizedBox(height: AppLayout.sectionGap),
              _displaySettings(model, status),
              const SizedBox(height: AppLayout.sectionGap),
              _systemSettings(model, status),
              const SizedBox(height: AppLayout.sectionGap),
              _statusOverview(model, status),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: model.busy
                    ? null
                    : () => _perform(model.refreshStatus),
                icon: const Icon(Icons.refresh),
                label: Text(model.failure == null ? '刷新状态' : '重试读取状态'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _reminderSettings(
    ScheduleIslandViewModel model,
    ScheduleIslandStatus status,
  ) => SettingsSection(
    title: '课程提醒',
    children: [
      SwitchListTile.adaptive(
        value: status.enabled,
        onChanged:
            model.busy || (!status.liveUpdatesSupported && !status.enabled)
            ? null
            : (enabled) => _perform(() => model.setEnabled(enabled)),
        title: const Text('启用课程提醒'),
        subtitle: Text(
          status.liveUpdatesSupported
              ? '使用已保存的课表与作息，显示课程状态和倒计时'
              : '需要 Android 16（API 36）及以上；当前设备 API ${status.androidVersion}',
        ),
        contentPadding: _tilePadding,
      ),
      Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('提前提醒'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final minutes in scheduleIslandLeadMinutes)
                  ChoiceChip(
                    label: Text(minutes == 0 ? '上课时' : '提前 $minutes 分钟'),
                    selected: status.leadMinutes == minutes,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    onSelected: model.busy
                        ? null
                        : (selected) {
                            if (selected) {
                              unawaited(
                                _perform(() => model.setLeadMinutes(minutes)),
                              );
                            }
                          },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('提醒跟随当前选择的账号和学期，只使用日期与作息完整的课程。'),
          ],
        ),
      ),
      ListTile(
        leading: const Icon(Icons.calendar_month_outlined),
        title: const Text('课表来源'),
        subtitle: Text(status.sourceLabel ?? '尚未选择可提醒的课表'),
        contentPadding: _tilePadding,
      ),
      if (status.sourceNotice case final notice?)
        Padding(padding: const EdgeInsets.all(20), child: Text(notice)),
    ],
  );

  Widget _displaySettings(
    ScheduleIslandViewModel model,
    ScheduleIslandStatus status,
  ) => SettingsSection(
    title: '显示样式与预览',
    children: [
      Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('胶囊内容'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final style in ScheduleIslandCapsuleStyle.values)
                  ChoiceChip(
                    label: Text(
                      style == ScheduleIslandCapsuleStyle.courseNameLocation
                          ? '课程名 + 地点'
                          : '仅课程名',
                    ),
                    selected: status.capsuleStyle == style,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    onSelected: model.busy
                        ? null
                        : (selected) {
                            if (selected) {
                              unawaited(
                                _perform(() => model.setCapsuleStyle(style)),
                              );
                            }
                          },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('「课程名 + 地点」在胶囊左侧绘制课程名、右侧显示地点；「仅课程名」只在右侧显示课程名。'),
            const SizedBox(height: 12),
            const Text('发送一条持续 2 分钟的示例通知；关闭提醒或尚未导入课表时也可预览。'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: model.busy || !status.liveUpdatesSupported
                      ? null
                      : () => _perform(model.preview),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('预览 2 分钟'),
                ),
                OutlinedButton.icon(
                  onPressed: model.busy || !status.previewVisible
                      ? null
                      : () => _perform(model.stopPreview),
                  icon: const Icon(Icons.clear),
                  label: const Text('清除预览'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('超级岛是否展示、采用哪种样式，由系统决定，请以预览的实际效果为准。'),
          ],
        ),
      ),
    ],
  );

  Widget _systemSettings(
    ScheduleIslandViewModel model,
    ScheduleIslandStatus status,
  ) => SettingsSection(
    title: '系统权限',
    children: [
      SettingsEntry(
        icon: Icons.notifications_outlined,
        title: '通知权限',
        subtitle: status.notificationsAllowed ? '已允许课程通知' : '未允许，点击在系统中开启',
        onTap: model.busy
            ? null
            : () => model.openSettings(
                ScheduleIslandSettingsTarget.notifications,
              ),
      ),
      if (status.liveUpdatesSupported &&
          status.notificationsAllowed &&
          !status.channelSupportsLiveUpdates)
        SettingsEntry(
          icon: Icons.notification_important_outlined,
          title: '课程通知设置',
          subtitle: '通知重要性过低，无法显示实况；点击在系统中调整',
          onTap: model.busy
              ? null
              : () => model.openSettings(ScheduleIslandSettingsTarget.channel),
        ),
      if (status.liveUpdatesSupported)
        SettingsEntry(
          icon: Icons.notifications_active_outlined,
          title: '实况通知权限',
          subtitle: status.promotionAllowed ? '已允许显示为实况通知' : '未允许，点击在系统中开启',
          onTap: model.busy
              ? null
              : () =>
                    model.openSettings(ScheduleIslandSettingsTarget.promotion),
        ),
      SettingsEntry(
        icon: Icons.alarm_outlined,
        title: '精确闹钟',
        subtitle: status.exactAlarmsAllowed
            ? '已允许按课程时间切换提醒'
            : '未允许，课程状态切换可能延迟；在系统中撤销权限后请重新打开应用',
        onTap: model.busy
            ? null
            : () => model.openSettings(ScheduleIslandSettingsTarget.alarms),
      ),
      SettingsEntry(
        icon: Icons.settings_applications_outlined,
        title: '应用与后台运行',
        subtitle: '在系统应用信息中检查自启动和省电限制；限制自启动可能阻止后台恢复',
        onTap: model.busy
            ? null
            : () => model.openSettings(ScheduleIslandSettingsTarget.app),
      ),
    ],
  );

  Widget _statusOverview(
    ScheduleIslandViewModel model,
    ScheduleIslandStatus status,
  ) => SettingsSection(
    title: '当前状态',
    children: [
      _statusTile(
        '课程通知',
        status.notificationVisible ? '已发布课程通知' : '当前没有已发布的课程通知',
      ),
      _statusTile(
        '示例通知',
        status.previewVisible ? '预览已发布，2 分钟后自动结束' : '当前没有示例通知',
      ),
      _statusTile(
        '系统实况标记',
        status.promoted
            ? '系统已标记为实况通知'
            : status.liveUpdatesSupported
            ? '当前通知尚未获得实况标记'
            : '当前 Android 版本不提供实况标记',
      ),
      if (status.activeLabel case final label?) _statusTile('当前课程', label),
      if (status.nextUpdate case final next?)
        _statusTile('下次状态更新', _timestamp(next)),
      if (status.hidden)
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('当前课程提醒已收起。'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: model.busy ? null : () => _perform(model.restore),
                icon: const Icon(Icons.restore),
                label: const Text('恢复当前课程提醒'),
              ),
            ],
          ),
        ),
    ],
  );

  Future<void> _perform(Future<void> Function() operation) async {
    await operation();
    if (!mounted) return;
    if (widget.viewModel?.failure case final failure?) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure)));
    }
  }

  static const _tilePadding = EdgeInsets.symmetric(horizontal: 20, vertical: 8);

  static Widget _statusTile(String title, String detail) => ListTile(
    title: Text(title),
    subtitle: Text(detail),
    contentPadding: _tilePadding,
  );

  static String _timestamp(DateTime value) =>
      '${value.month}月${value.day}日 '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}
