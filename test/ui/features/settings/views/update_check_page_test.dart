import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zfhelper/platform/app_installer_platform.dart';
import 'package:zfhelper/ui/features/courses/view_models/courses_view_model.dart';
import 'package:zfhelper/ui/features/grades/view_models/grades_view_model.dart';
import 'package:zfhelper/ui/features/schedule/view_models/timetable_view_model.dart';
import 'package:zfhelper/ui/features/settings/views/app_settings_page.dart';
import 'package:zfhelper/ui/features/settings/views/update_check_page.dart';
import 'package:zfhelper/ui/features/settings/view_models/update_check_view_model.dart';

import '../../../../support/course_fakes.dart';
import '../../../../support/grade_fakes.dart';
import '../../../../support/schedule_fakes.dart';
import '../../../../support/update_fakes.dart';

void main() {
  late Directory downloadDirectory;
  late FakeAppInstaller installer;

  setUp(() {
    downloadDirectory = Directory.systemTemp.createTempSync('zfhelper-page-');
    installer = FakeAppInstaller();
    addTearDown(() {
      if (downloadDirectory.existsSync()) {
        downloadDirectory.deleteSync(recursive: true);
      }
    });
  });

  UpdateCheckViewModel buildModel(
    ReleaseRepositoryHarness harness, {
    TargetPlatform platform = TargetPlatform.android,
    String version = '0.1.7+1',
  }) {
    final model = UpdateCheckViewModel(
      repository: harness.repository,
      readVersion: () async => version,
      installer: installer,
      resolveDownloadDirectory: () async => downloadDirectory.path,
    );
    addTearDown(model.dispose);
    return model;
  }

  Future<void> pumpPage(
    WidgetTester tester,
    UpdateCheckViewModel model, {
    TargetPlatform platform = TargetPlatform.android,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: platform),
        home: UpdateCheckPage(viewModel: model),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Widget tests run in a fake-async zone where the repository's real
  // dart:io writes never complete, so downloads must run inside runAsync.
  Future<void> runDownload(
    WidgetTester tester,
    UpdateCheckViewModel model,
  ) async {
    final asset = model.latest!.assetWithExtension('.apk')!;
    await tester.runAsync(() => model.startDownload(asset));
    await tester.pumpAndSettle();
  }

  testWidgets('shows a retryable failure message when the check fails', (
    tester,
  ) async {
    final harness = ReleaseRepositoryHarness(
      respond: (options) => ResponseBody.fromString('{}', 403),
    );
    addTearDown(harness.dispose);
    final model = buildModel(harness);
    await pumpPage(tester, model);

    expect(find.textContaining('请求受限'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('shows the up-to-date state for the current release', (
    tester,
  ) async {
    final harness = ReleaseRepositoryHarness(
      respond: (options) => releaseJsonResponse(
        releaseJson(tag: 'v0.1.7', assets: [apkAssetJson('0.1.7')]),
      ),
    );
    addTearDown(harness.dispose);
    final model = buildModel(harness);
    await pumpPage(tester, model);

    expect(find.text('当前已是最新版本'), findsOneWidget);
    expect(find.textContaining('当前版本 0.1.7+1'), findsOneWidget);
  });

  testWidgets('explains when an unpublished pre-release has no release page', (
    tester,
  ) async {
    final harness = ReleaseRepositoryHarness(
      respond: (options) => options.uri.path.endsWith('/latest')
          ? releaseJsonResponse(
              releaseJson(tag: 'v0.1.8', assets: [apkAssetJson('0.1.8')]),
            )
          : notFoundResponse(),
    );
    addTearDown(harness.dispose);
    final model = buildModel(harness, version: '0.2.0-beta.1+2');
    await pumpPage(tester, model);

    expect(find.text('准备检查更新…'), findsNothing);
    expect(find.textContaining('当前已是最新版本'), findsOneWidget);
    expect(find.textContaining('没有对应的发布页'), findsOneWidget);
    expect(find.text('重新检查'), findsOneWidget);
  });

  testWidgets('downloads and installs the Android APK in-app', (tester) async {
    final harness = ReleaseRepositoryHarness(
      probe: (_) async => true,
      respond: (options) => options.uri.host == 'api.github.com'
          ? releaseJsonResponse(
              releaseJson(tag: 'v0.2.0', assets: [apkAssetJson('0.2.0')]),
            )
          : downloadResponseOf('apk-bytes'),
    );
    addTearDown(harness.dispose);
    final model = buildModel(harness);
    await pumpPage(tester, model);

    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.textContaining('最新版本 v0.2.0'), findsOneWidget);
    expect(find.text('下载并安装'), findsOneWidget);

    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.textContaining('最新版本 v0.2.0'), findsOneWidget);
    expect(find.text('下载并安装'), findsOneWidget);

    await runDownload(tester, model);

    expect(find.text('安装'), findsOneWidget);
    expect(installer.installRequests, hasLength(1));
    expect(
      File(installer.installRequests.single).readAsStringSync(),
      'apk-bytes',
    );
  });

  testWidgets('shows the system permission hint when install is blocked', (
    tester,
  ) async {
    installer.failure = const AppInstallerException(
      '需要允许安装未知应用后重试',
      permissionRequired: true,
    );
    final harness = ReleaseRepositoryHarness(
      probe: (_) async => true,
      respond: (options) => options.uri.host == 'api.github.com'
          ? releaseJsonResponse(
              releaseJson(tag: 'v0.2.0', assets: [apkAssetJson('0.2.0')]),
            )
          : downloadResponseOf('apk-bytes'),
    );
    addTearDown(harness.dispose);
    final model = buildModel(harness);
    await pumpPage(tester, model);

    await runDownload(tester, model);

    expect(find.textContaining('安装未知应用'), findsOneWidget);
    expect(find.text('安装'), findsOneWidget);
  });

  testWidgets('offers a retry when the download fails', (tester) async {
    final harness = ReleaseRepositoryHarness(
      probe: (_) async => false,
      respond: (options) => options.uri.host == 'api.github.com'
          ? releaseJsonResponse(
              releaseJson(tag: 'v0.2.0', assets: [apkAssetJson('0.2.0')]),
            )
          : throw DioException.connectionError(
              requestOptions: options,
              reason: 'offline',
            ),
    );
    addTearDown(harness.dispose);
    final model = buildModel(harness);
    await pumpPage(tester, model);

    await runDownload(tester, model);

    expect(find.textContaining('无法连接下载服务器'), findsOneWidget);
    expect(find.text('重试下载'), findsOneWidget);
  });

  testWidgets('notes a missing Android package instead of hiding the action', (
    tester,
  ) async {
    final harness = ReleaseRepositoryHarness(
      respond: (options) => releaseJsonResponse(
        releaseJson(
          tag: 'v0.2.0',
          assets: [
            {
              'name': 'zfhelper-0.2.0-windows.zip',
              'browser_download_url': 'https://github.com/OldSuns/ZFHelper/releases/download/v0.2.0/zfhelper-0.2.0-windows.zip',
            },
          ],
        ),
      ),
    );
    addTearDown(harness.dispose);
    final model = buildModel(harness);
    await pumpPage(tester, model);

    expect(find.text('下载并安装'), findsNothing);
    expect(find.textContaining('未提供 Android 安装包'), findsOneWidget);
  });

  testWidgets('keeps the browser download on Windows', (tester) async {
    final harness = ReleaseRepositoryHarness(
      respond: (options) => releaseJsonResponse(
        releaseJson(
          tag: 'v0.1.7',
          assets: [
            {
              'name': 'zfhelper-0.1.7-windows.zip',
              'browser_download_url': 'https://github.com/OldSuns/ZFHelper/releases/download/v0.1.7/zfhelper-0.1.7-windows.zip',
            },
          ],
        ),
      ),
    );
    addTearDown(harness.dispose);
    final model = buildModel(harness);
    await pumpPage(tester, model, platform: TargetPlatform.windows);

    expect(find.text('下载 Windows 版'), findsOneWidget);
    expect(find.text('下载并安装'), findsNothing);
  });

  testWidgets('the settings entry shows an update badge only when available', (
    tester,
  ) async {
    final harness = ReleaseRepositoryHarness(
      respond: (options) => releaseJsonResponse(releaseJson(tag: 'v0.1.7')),
    );
    addTearDown(harness.dispose);
    final model = buildModel(harness);
    model.updateAvailable = true;

    final timetable = TimetableViewModel(
      repository: testScheduleRepository(),
      clock: () => DateTime(2026, 9, 12, 13),
    );
    final grades = GradesViewModel(repository: testGradeRepository());
    final courses = CoursesViewModel(repository: testCourseRepository());

    await tester.pumpWidget(
      MaterialApp(
        home: AppSettingsPage(
          timetable: timetable,
          grades: grades,
          courses: courses,
          updateCheck: model,
        ),
      ),
    );
    expect(find.text('新'), findsOneWidget);

    model.updateAvailable = false;
    model.check();
    await tester.pumpAndSettle();
    expect(find.text('新'), findsNothing);

    // Dispose before test-body end: the view models' refresh timers must not
    // outlive the fake-async zone.
    timetable.dispose();
    grades.dispose();
    courses.dispose();
  });
}
