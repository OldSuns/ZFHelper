import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:zf_core/zf_core.dart';

import '../ui/core/app_theme.dart';
import '../ui/features/auth/view_models/auth_view_model.dart';
import '../ui/features/auth/views/school_connection_page.dart';
import '../ui/features/auth/views/login_page.dart';
import '../ui/features/grades/view_models/grades_view_model.dart';
import '../ui/features/grades/views/grades_page.dart';
import '../ui/features/courses/view_models/courses_view_model.dart';
import '../ui/features/courses/views/courses_page.dart';
import '../ui/features/schedule/view_models/timetable_view_model.dart';
import '../ui/features/schedule/views/timetable_page.dart';
import '../ui/features/settings/views/settings_page.dart';
import '../ui/features/settings/view_models/schedule_widget_view_model.dart';
import '../ui/features/settings/view_models/update_check_view_model.dart';
import 'app_configuration.dart';

enum AppDestination {
  timetable('课表', Icons.calendar_month_outlined, Icons.calendar_month),
  courses('选课', Icons.search_rounded, Icons.search_rounded),
  grades('成绩', Icons.assessment_outlined, Icons.assessment_rounded),
  settings('设置', Icons.settings_outlined, Icons.settings);

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
  late final GradesViewModel _grades;
  late final CoursesViewModel _courses;
  late final UpdateCheckViewModel _updateCheck;
  ScheduleWidgetViewModel? _scheduleWidget;
  StreamSubscription<DateTime>? _widgetLaunches;
  bool _checkingExit = false;

  @override
  void initState() {
    super.initState();
    _timetable = TimetableViewModel(
      repository: widget.configuration.schedule,
      clock: widget.configuration.clock,
    );
    _auth = AuthViewModel(
      widget.configuration.auth,
      onRemoveAccountData: (scope) async {
        await widget.configuration.removeAccountData(scope);
        await _synchronizeWidgetAfterRemoval();
      },
      onRemoveSchoolData: (schoolId) async {
        await widget.configuration.removeSchoolData(schoolId);
        await _synchronizeWidgetAfterRemoval();
      },
    );
    _grades = GradesViewModel(repository: widget.configuration.grades);
    _courses = CoursesViewModel(repository: widget.configuration.courses);
    _updateCheck = UpdateCheckViewModel(
      repository: widget.configuration.releases,
    );
    final widgetPlatform = widget.configuration.scheduleWidgetPlatform;
    if (widgetPlatform != null) {
      _scheduleWidget = ScheduleWidgetViewModel(
        repository: widget.configuration.schedule,
        appearance: widget.configuration.appearance,
        platform: widgetPlatform,
        clock: widget.configuration.clock,
      );
      _widgetLaunches = _scheduleWidget!.launches.listen(_openWidgetDate);
      unawaited(_initializeWidget());
    }
    unawaited(_timetable.initialize());
    unawaited(_grades.initialize());
    unawaited(_courses.initialize());
    unawaited(_auth.restore());
    unawaited(widget.configuration.appearance.initialize());
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timetable.dispose();
    _grades.dispose();
    _courses.dispose();
    _updateCheck.dispose();
    _auth.dispose();
    unawaited(_widgetLaunches?.cancel());
    _scheduleWidget?.dispose();
    widget.configuration.appearance.dispose();
    unawaited(widget.configuration.schedule.dispose());
    unawaited(widget.configuration.grades.dispose());
    unawaited(widget.configuration.courses.dispose());
    widget.configuration.releases.dispose();
    unawaited(widget.configuration.auth.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _timetable.refreshToday();
      unawaited(_scheduleWidget?.refreshStatus());
      if (_auth.state.canRestoreSession && !_auth.state.isBusy) {
        unawaited(_auth.restore());
      }
    }
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    final repository = widget.configuration.courses;
    if (!repository.hasActiveOperations) return AppExitResponse.exit;
    if (_checkingExit || !mounted) return AppExitResponse.cancel;
    _checkingExit = true;
    try {
      final exit = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('退出并暂停选课？'),
          content: const Text('关闭软件会停止后续尝试。已发送的请求不能撤回，重新打开后可在选课页核实结果或继续。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('继续运行'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('暂停并退出'),
            ),
          ],
        ),
      );
      if (exit != true) return AppExitResponse.cancel;
      if (await repository.pauseForExit()) return AppExitResponse.exit;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(repository.state.failure ?? '选课状态未保存，请稍后重试退出'),
          ),
        );
      }
      return AppExitResponse.cancel;
    } finally {
      _checkingExit = false;
    }
  }

  void _selectDestination(int index, {bool resetTimetableSection = true}) {
    _timetable.refreshToday();
    final destination = AppDestination.values[index];
    if (resetTimetableSection && destination == AppDestination.timetable) {
      _timetable.showSection(ScheduleSection.timetable);
    }
    setState(() => _destination = destination);
  }

  void _openSettings() => _selectDestination(AppDestination.settings.index);

  Future<void> _synchronizeWidgetAfterRemoval() async {
    final model = _scheduleWidget;
    if (model == null) return;
    await widget.configuration.appearance.initialize();
    if (!await model.synchronize()) {
      throw LoginFailure(
        LoginFailureCode.storage,
        model.failure ?? model.sourceNotice ?? '桌面小组件数据未能清理，请重试移除操作',
      );
    }
  }

  Future<void> _initializeWidget() async {
    await _timetable.initialize();
    if (!mounted) return;
    final date = await _scheduleWidget!.consumeLaunch();
    if (date != null) _openWidgetDate(date);
    await _scheduleWidget?.refreshStatus();
  }

  void _openWidgetDate(DateTime date) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      _timetable.selectAgendaDate(date);
      _timetable.showSection(ScheduleSection.agenda);
      _selectDestination(
        AppDestination.timetable.index,
        resetTimetableSection: false,
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _configureSchool(SchoolConnection profile) {
    Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) =>
            LoginPage(viewModel: _auth, profile: profile, usernameHint: ''),
      ),
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
        final extended = constraints.maxWidth >= AppLayout.extendedRailMinWidth;
        return Scaffold(
          body: Row(
            children: [
              if (isWide) ...[
                _DesktopNavigation(
                  extended: extended,
                  destination: _destination,
                  onSelect: _selectDestination,
                ),
                const VerticalDivider(width: 1),
              ],
              Expanded(
                child: ListenableBuilder(
                  listenable: Listenable.merge([
                    _auth,
                    _timetable,
                    _grades,
                    _courses,
                  ]),
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
    if (_destination != AppDestination.settings &&
        _auth.state.profile == null &&
        !_auth.state.isBusy &&
        _auth.state.storageFailure == null &&
        !_timetable.data.loading &&
        _timetable.data.failure == null &&
        _timetable.data.library.accounts.isEmpty &&
        !_grades.data.loading &&
        _grades.data.failure == null &&
        _grades.data.library.accounts.isEmpty &&
        !_courses.data.loading &&
        _courses.data.failure == null &&
        _courses.data.library.accounts.isEmpty) {
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
      AppDestination.courses => CoursesPage(
        viewModel: _courses,
        schoolName: _auth.state.profile?.name ?? '尚未设置学校',
        onOpenSettings: _openSettings,
      ),
      AppDestination.grades => GradesPage(
        viewModel: _grades,
        schoolName: _auth.state.profile?.name ?? '尚未设置学校',
        onOpenSettings: _openSettings,
      ),
      AppDestination.settings => SettingsPage(
        auth: _auth,
        appearance: widget.configuration.appearance,
        timetable: _timetable,
        grades: _grades,
        courses: _courses,
        updateCheck: _updateCheck,
        scheduleWidget: _scheduleWidget,
      ),
    };
  }
}

class _DesktopNavigation extends StatelessWidget {
  const _DesktopNavigation({
    required this.extended,
    required this.destination,
    required this.onSelect,
  });

  static const _compactWidth = 88.0;

  final bool extended;
  final AppDestination destination;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        child: NavigationRail(
          extended: extended,
          minWidth: _compactWidth,
          minExtendedWidth: 184,
          scrollable: true,
          selectedIndex: destination.index,
          onDestinationSelected: onSelect,
          labelType: extended
              ? NavigationRailLabelType.none
              : NavigationRailLabelType.all,
          leading: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: extended ? 20 : 8,
              vertical: 24,
            ),
            child: SizedBox(
              width: extended ? null : _compactWidth - AppLayout.pagePadding,
              child: Text(
                'ZFHelper',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          destinations: [
            for (final item in AppDestination.values)
              NavigationRailDestination(
                icon: Icon(item.icon),
                selectedIcon: Icon(item.selectedIcon),
                label: SizedBox(
                  width: extended
                      ? null
                      : _compactWidth - AppLayout.pagePadding,
                  child: Text(
                    item.label,
                    textAlign: extended ? TextAlign.start : TextAlign.center,
                  ),
                ),
                padding: const EdgeInsets.symmetric(vertical: 6),
              ),
          ],
        ),
      ),
    );
  }
}
