import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zf_core/zf_core.dart';

import '../ui/core/app_theme.dart';
import '../ui/core/empty_state_card.dart';
import '../ui/core/feature_page.dart';
import '../ui/features/auth/view_models/auth_view_model.dart';
import '../ui/features/auth/views/school_connection_page.dart';
import '../ui/features/auth/views/login_page.dart';
import '../ui/features/schedule/view_models/timetable_view_model.dart';
import '../ui/features/schedule/views/timetable_page.dart';
import '../ui/features/settings/views/account_settings_page.dart';
import 'app_configuration.dart';

enum AppDestination {
  timetable('课表', Icons.calendar_month_outlined, Icons.calendar_month),
  courses('选课', Icons.search_rounded, Icons.search_rounded),
  tasks('任务', Icons.task_alt_outlined, Icons.task_alt_rounded),
  grades('成绩', Icons.assessment_outlined, Icons.assessment_rounded);

  const AppDestination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class AppShell extends StatefulWidget {
  const AppShell({required this.configuration, super.key});

  final AppConfiguration configuration;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  AppDestination _destination = AppDestination.timetable;
  late final TimetableViewModel _timetable;
  late final AuthViewModel _auth;

  @override
  void initState() {
    super.initState();
    _timetable = TimetableViewModel(
      repository: widget.configuration.schedule,
      clock: widget.configuration.clock,
    );
    _auth = AuthViewModel(widget.configuration.auth);
    unawaited(_timetable.initialize());
    unawaited(_auth.restore());
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timetable.dispose();
    _auth.dispose();
    unawaited(widget.configuration.schedule.dispose());
    unawaited(widget.configuration.auth.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _timetable.refreshToday();
      if (_auth.state.canRestoreSession && !_auth.state.isBusy) {
        unawaited(_auth.restore());
      }
    }
  }

  void _selectDestination(int index) {
    _timetable.refreshToday();
    setState(() => _destination = AppDestination.values[index]);
  }

  void _openSettings() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => AccountSettingsPage(viewModel: _auth),
      ),
    );
  }

  void _configureSchool(SchoolConnection profile) {
    Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (context) => LoginPage(viewModel: _auth)),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _destination == AppDestination.timetable,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && _destination != AppDestination.timetable) {
        _selectDestination(AppDestination.timetable.index);
      }
    },
    child: LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= AppLayout.navigationRailMinWidth;
        return Scaffold(
          body: Row(
            children: [
              if (isWide) ...[
                SafeArea(
                  child: NavigationRail(
                    scrollable: true,
                    selectedIndex: _destination.index,
                    onDestinationSelected: _selectDestination,
                    labelType: NavigationRailLabelType.all,
                    leading: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'ZFHelper',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    destinations: [
                      for (final destination in AppDestination.values)
                        NavigationRailDestination(
                          icon: Icon(destination.icon),
                          selectedIcon: Icon(destination.selectedIcon),
                          label: Text(destination.label),
                        ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
              ],
              Expanded(
                child: ListenableBuilder(
                  listenable: Listenable.merge([_auth, _timetable]),
                  builder: (context, _) => _buildPage(),
                ),
              ),
            ],
          ),
          bottomNavigationBar: isWide
              ? null
              : NavigationBar(
                  selectedIndex: _destination.index,
                  onDestinationSelected: _selectDestination,
                  destinations: [
                    for (final destination in AppDestination.values)
                      NavigationDestination(
                        icon: Icon(destination.icon),
                        selectedIcon: Icon(destination.selectedIcon),
                        label: destination.label,
                      ),
                  ],
                ),
        );
      },
    ),
  );

  Widget _buildPage() {
    if (_auth.state.profile == null &&
        !_auth.state.isBusy &&
        _auth.state.storageFailure == null &&
        !_timetable.data.loading &&
        _timetable.data.failure == null &&
        _timetable.data.library.accounts.isEmpty) {
      return SchoolConnectionPage(
        isNewSchool: true,
        onSave: _auth.configureSchool,
        onSelected: _configureSchool,
      );
    }
    return switch (_destination) {
      AppDestination.timetable => TimetablePage(
        viewModel: _timetable,
        schoolName: _auth.state.profile?.name ?? '尚未设置学校',
        isSignedIn: _auth.state.isSignedIn,
        onOpenSettings: _openSettings,
      ),
      AppDestination.courses => _connectionPage(
        title: '选课',
        icon: Icons.search_rounded,
        heading: '查看可选课程',
        message: '连接教务账号后，查看可选教学班、教师与剩余名额。',
      ),
      AppDestination.grades => _connectionPage(
        title: '成绩',
        icon: Icons.assessment_outlined,
        heading: '查看学期成绩',
        message: '连接教务账号后，按学期查看课程成绩、学分与绩点。',
      ),
      AppDestination.tasks => FeaturePage(
        title: '任务',
        schoolName: _auth.state.profile?.name ?? '尚未设置学校',
        onOpenSettings: _openSettings,
        children: [
          EmptyStateCard(
            icon: Icons.task_alt_outlined,
            title: '还没有选课任务',
            message: '在选课页选择目标课程后，可以创建即时、定时或捡漏任务。',
            actionLabel: '前往选课',
            onAction: () => _selectDestination(AppDestination.courses.index),
          ),
        ],
      ),
    };
  }

  Widget _connectionPage({
    required String title,
    required IconData icon,
    required String heading,
    required String message,
  }) => FeaturePage(
    title: title,
    schoolName: _auth.state.profile?.name ?? '尚未设置学校',
    onOpenSettings: _openSettings,
    children: [
      EmptyStateCard(
        icon: icon,
        title: heading,
        message: _auth.state.isSignedIn ? '教务账号已验证，$title查询功能尚未接入。' : message,
        actionLabel: '账号与设置',
        onAction: _openSettings,
      ),
    ],
  );
}
