import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zfhelper/data/repositories/release_repository.dart';
import 'package:zfhelper/data/storage/update_preferences_store.dart';
import 'package:zfhelper/platform/app_installer_platform.dart';
import 'package:zfhelper/ui/features/settings/view_models/update_check_view_model.dart';

import '../../../../support/settings_fakes.dart';
import '../../../../support/update_fakes.dart';

void main() {
  late DateTime now;
  late TestUpdatePreferencesStore preferences;
  late FakeAppInstaller installer;
  late Directory downloadDirectory;

  setUp(() {
    now = DateTime(2026, 9, 12, 13);
    preferences = TestUpdatePreferencesStore();
    installer = FakeAppInstaller();
    downloadDirectory = Directory.systemTemp.createTempSync('zfhelper-vm-');
    addTearDown(() {
      if (downloadDirectory.existsSync()) {
        downloadDirectory.deleteSync(recursive: true);
      }
    });
  });

  UpdateCheckViewModel buildModel(
    ReleaseRepositoryHarness harness, {
    String version = '0.1.7+1',
  }) {
    final model = UpdateCheckViewModel(
      repository: harness.repository,
      readVersion: () async => version,
      preferences: preferences,
      clock: () => now,
      installer: installer,
      resolveDownloadDirectory: () async => downloadDirectory.path,
    );
    addTearDown(model.dispose);
    return model;
  }

  test('auto-check is skipped within the 24-hour interval', () async {
    preferences.value = UpdatePreferences(
      lastAutoCheckAt: now.subtract(const Duration(hours: 12)),
    );
    final harness = ReleaseRepositoryHarness(
      respond: (options) => releaseJsonResponse(
        releaseJson(tag: 'v0.2.0', assets: [apkAssetJson('0.2.0')]),
      ),
    );
    addTearDown(harness.dispose);
    final model = buildModel(harness);

    await model.autoCheck();

    expect(harness.adapter.requests, isEmpty);
    expect(model.updateAvailable, isNull);
    expect(model.consumeNotice(), isNull);
    expect(
      preferences.value.lastAutoCheckAt,
      now.subtract(const Duration(hours: 12)),
    );
  });

  test(
    'auto-check runs after the interval and notices a new release once',
    () async {
      preferences.value = UpdatePreferences(
        lastAutoCheckAt: now.subtract(const Duration(hours: 25)),
      );
      final harness = ReleaseRepositoryHarness(
        respond: (options) => releaseJsonResponse(
          releaseJson(tag: 'v0.2.0', assets: [apkAssetJson('0.2.0')]),
        ),
      );
      addTearDown(harness.dispose);
      final model = buildModel(harness);

      await model.autoCheck();

      expect(model.updateAvailable, isTrue);
      expect(model.failure, isNull);
      expect(preferences.value.lastAutoCheckAt, now);
      final notice = model.consumeNotice();
      expect(notice, 'v0.2.0');
      expect(model.consumeNotice(), isNull);

      // The next auto-check of the same tag stays silent.
      now = now.add(const Duration(hours: 25));
      await model.autoCheck();
      expect(model.consumeNotice(), isNull);
      expect(model.updateAvailable, isTrue);
    },
  );

  test('auto-check failures stay silent but record the attempt', () async {
    preferences.value = UpdatePreferences(
      lastAutoCheckAt: now.subtract(const Duration(hours: 25)),
    );
    final harness = ReleaseRepositoryHarness(
      respond: (options) => throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      ),
    );
    addTearDown(harness.dispose);
    final model = buildModel(harness);

    await model.autoCheck();

    expect(model.failure, isNull);
    expect(model.updateAvailable, isNull);
    expect(model.consumeNotice(), isNull);
    expect(preferences.value.lastAutoCheckAt, now);
  });

  test('a failed silent check keeps the previously known release', () async {
    preferences.value = UpdatePreferences(
      lastAutoCheckAt: now.subtract(const Duration(hours: 25)),
    );
    var failing = false;
    final harness = ReleaseRepositoryHarness(
      respond: (options) => failing
          ? throw DioException.connectionError(
              requestOptions: options,
              reason: 'offline',
            )
          : releaseJsonResponse(
              releaseJson(tag: 'v0.2.0', assets: [apkAssetJson('0.2.0')]),
            ),
    );
    addTearDown(harness.dispose);
    final model = buildModel(harness);

    await model.autoCheck();
    expect(model.updateAvailable, isTrue);

    now = now.add(const Duration(hours: 25));
    failing = true;
    await model.autoCheck();

    expect(model.failure, isNull);
    expect(model.updateAvailable, isTrue);
    expect(model.latest?.tagName, 'v0.2.0');
  });

  test('manual check reports failures and stays retryable', () async {
    final harness = ReleaseRepositoryHarness(
      respond: (options) => throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      ),
    );
    addTearDown(harness.dispose);
    final model = buildModel(harness);

    await model.check();

    expect(model.failure, contains('无法连接 GitHub'));
    expect(model.isBusy, isFalse);
  });

  test('a pre-release build newer than the latest stable shows its own release notes', () async {
    final harness = ReleaseRepositoryHarness(
      respond: (options) => options.uri.path.endsWith('/latest')
          ? releaseJsonResponse(
              releaseJson(tag: 'v0.1.8', assets: [apkAssetJson('0.1.8')]),
            )
          : releaseJsonResponse(
              releaseJson(
                tag: 'v0.2.0-beta.1',
                assets: [apkAssetJson('0.2.0-beta.1')],
              ),
            ),
    );
    addTearDown(harness.dispose);
    final model = buildModel(harness, version: '0.2.0-beta.1+2');

    await model.check();

    expect(model.failure, isNull);
    expect(model.updateAvailable, isFalse);
    expect(model.latest?.tagName, 'v0.1.8');
    expect(model.currentRelease?.tagName, 'v0.2.0-beta.1');
  });

  test(
    'an unpublished pre-release version tolerates a 404 for its own tag',
    () async {
      final harness = ReleaseRepositoryHarness(
        respond: (options) => options.uri.path.endsWith('/latest')
            ? releaseJsonResponse(
                releaseJson(tag: 'v0.1.8', assets: [apkAssetJson('0.1.8')]),
              )
            : notFoundResponse(),
      );
      addTearDown(harness.dispose);
      final model = buildModel(harness, version: '0.2.0-beta.1+2');

      await model.check();

      expect(model.failure, isNull);
      expect(model.updateAvailable, isFalse);
      expect(model.latest?.tagName, 'v0.1.8');
      expect(model.currentRelease, isNull);
    },
  );

  test(
    'a pre-release build is offered the stable release once it overtakes it',
    () async {
      final harness = ReleaseRepositoryHarness(
        respond: (options) => releaseJsonResponse(
          releaseJson(tag: 'v0.2.0', assets: [apkAssetJson('0.2.0')]),
        ),
      );
      addTearDown(harness.dispose);
      final model = buildModel(harness, version: '0.2.0-beta.1+2');

      await model.check();

      expect(model.failure, isNull);
      expect(model.updateAvailable, isTrue);
      expect(model.latest?.tagName, 'v0.2.0');
      expect(model.currentRelease, isNull);
      expect(
        harness.adapter.requests.map((uri) => uri.path).single,
        endsWith('/latest'),
      );
    },
  );

  test(
    'a stable version still fails the check when its tag is missing',
    () async {
      final harness = ReleaseRepositoryHarness(
        respond: (options) => options.uri.path.endsWith('/latest')
            ? releaseJsonResponse(
                releaseJson(tag: 'v0.1.8', assets: [apkAssetJson('0.1.8')]),
              )
            : notFoundResponse(),
      );
      addTearDown(harness.dispose);
      final model = buildModel(harness, version: '0.9.9+1');

      await model.check();

      expect(model.failure, contains('404'));
      expect(model.updateAvailable, isNull);
      expect(model.currentRelease, isNull);
    },
  );

  test('download stores the APK and triggers the installer', () async {
    final harness = ReleaseRepositoryHarness(
      probe: (_) async => true,
      respond: (options) => downloadResponseOf('apk-bytes'),
    );
    addTearDown(harness.dispose);
    final model = buildModel(harness);
    final asset = ReleaseAsset(
      name: 'zfhelper-test.apk',
      url: Uri.parse(
        'https://github.com/OldSuns/ZFHelper/releases/download/v0.2.0/zfhelper-test.apk',
      ),
    );

    await model.startDownload(asset);

    final state = model.downloadState;
    expect(state, isA<UpdateDownloadReady>());
    final path = (state as UpdateDownloadReady).path;
    expect(File(path).readAsStringSync(), 'apk-bytes');
    expect(installer.installRequests, [path]);
    expect(model.installFailure, isNull);
  });

  test('download failures surface a retryable message', () async {
    final harness = ReleaseRepositoryHarness(
      probe: (_) async => false,
      respond: (options) => throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      ),
    );
    addTearDown(harness.dispose);
    final model = buildModel(harness);
    final asset = ReleaseAsset(
      name: 'zfhelper-test.apk',
      url: Uri.parse(
        'https://github.com/OldSuns/ZFHelper/releases/download/v0.2.0/zfhelper-test.apk',
      ),
    );

    await model.startDownload(asset);

    final state = model.downloadState;
    expect(state, isA<UpdateDownloadFailed>());
    expect((state as UpdateDownloadFailed).message, contains('无法连接下载服务器'));
    expect(installer.installRequests, isEmpty);
  });

  test('install permission failures keep the download retryable', () async {
    final harness = ReleaseRepositoryHarness(
      probe: (_) async => true,
      respond: (options) => downloadResponseOf('apk-bytes'),
    );
    addTearDown(harness.dispose);
    installer.failure = const AppInstallerException(
      '需要允许安装未知应用后重试',
      permissionRequired: true,
    );
    final model = buildModel(harness);
    final asset = ReleaseAsset(
      name: 'zfhelper-test.apk',
      url: Uri.parse(
        'https://github.com/OldSuns/ZFHelper/releases/download/v0.2.0/zfhelper-test.apk',
      ),
    );

    await model.startDownload(asset);

    expect(model.downloadState, isA<UpdateDownloadReady>());
    expect(model.installFailure, contains('安装未知应用'));
  });
}
