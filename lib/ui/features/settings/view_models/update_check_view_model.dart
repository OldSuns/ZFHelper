import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../data/repositories/release_repository.dart';
import '../../../../data/storage/update_preferences_store.dart';
import '../../../../platform/app_installer_platform.dart';

typedef VersionReader = Future<String> Function();
typedef DownloadDirectoryResolver = Future<String> Function();

/// Minimum spacing between startup update checks.
const _autoCheckInterval = Duration(hours: 24);

sealed class UpdateDownloadState {
  const UpdateDownloadState();
}

final class UpdateDownloadIdle extends UpdateDownloadState {
  const UpdateDownloadIdle();
}

final class UpdateDownloadProgress extends UpdateDownloadState {
  const UpdateDownloadProgress({required this.received, this.total});

  final int received;
  final int? total;
}

final class UpdateDownloadReady extends UpdateDownloadState {
  const UpdateDownloadReady(this.path);

  final String path;
}

final class UpdateDownloadFailed extends UpdateDownloadState {
  const UpdateDownloadFailed(this.message);

  final String message;
}

final class UpdateCheckViewModel extends ChangeNotifier {
  UpdateCheckViewModel({
    required this.repository,
    VersionReader? readVersion,
    this.preferences,
    this.clock,
    this.installer,
    this.resolveDownloadDirectory,
  }) : _readVersion = readVersion ?? _platformVersion;

  final ReleaseRepository repository;
  final AppInstallerPlatform? installer;
  final VersionReader _readVersion;
  final UpdatePreferencesStore? preferences;
  final DateTime Function()? clock;
  final DownloadDirectoryResolver? resolveDownloadDirectory;

  bool isBusy = false;
  bool? updateAvailable;
  String? currentVersion;
  ReleaseInfo? latest;
  ReleaseInfo? currentRelease;
  String? failure;

  /// Tag of a release discovered by the startup auto-check that has not been
  /// surfaced to the user yet; the shell consumes it via [consumeNotice].
  String? _pendingNotice;

  UpdateDownloadState downloadState = const UpdateDownloadIdle();
  String? installFailure;

  /// Startup check: silent, throttled to once per [_autoCheckInterval].
  /// Failures are recorded in preferences but never shown to the user; the
  /// manual check page remains the place to see errors and retry.
  Future<void> autoCheck() async {
    final preferences = this.preferences;
    final clock = this.clock;
    if (preferences == null || clock == null || isBusy) return;
    UpdatePreferences stored;
    try {
      stored = await preferences.read();
    } on Object {
      return;
    }
    final now = clock();
    if (stored.lastAutoCheckAt != null &&
        now.difference(stored.lastAutoCheckAt!) < _autoCheckInterval) {
      return;
    }
    var notifiedTag = stored.lastNotifiedTag;
    try {
      await _runCheck(silent: true);
      if (updateAvailable == true &&
          latest != null &&
          notifiedTag != latest!.tagName) {
        _pendingNotice = latest!.tagName;
        // Persisted together with the attempt time in one write below, so a
        // crash cannot leave the notice half-recorded.
        notifiedTag = _pendingNotice;
        notifyListeners();
      }
    } finally {
      await _writePreferences(
        UpdatePreferences(lastAutoCheckAt: now, lastNotifiedTag: notifiedTag),
      );
    }
  }

  /// Returns the release tag awaiting a user notice, clearing the request.
  /// The tag is already persisted, so a notice is shown at most once per
  /// release regardless of when this is called.
  String? consumeNotice() {
    final tag = _pendingNotice;
    _pendingNotice = null;
    return tag;
  }

  Future<void> check() => _runCheck(silent: false);

  Future<void> _runCheck({required bool silent}) async {
    if (isBusy) return;
    isBusy = true;
    failure = null;
    notifyListeners();
    try {
      final version = await _readVersion();
      final release = await repository.fetchLatest();
      final hasUpdate = compareVersions(release.tagName, version) > 0;
      ReleaseInfo? releaseForCurrentVersion;
      if (!hasUpdate) {
        final currentTag = releaseTagForVersion(version);
        releaseForCurrentVersion = release.tagName == currentTag
            ? release
            : await repository.fetchByTag(currentTag);
      }
      currentVersion = version;
      latest = release;
      currentRelease = releaseForCurrentVersion;
      updateAvailable = hasUpdate;
    } on Object catch (error) {
      // A failed check keeps the previously known release state: it must not
      // clear an existing update badge or discard shown release data.
      if (!silent) {
        failure = error is ReleaseException ? error.message : '检查更新失败，请稍后重试';
      }
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  /// Downloads [asset] into the configured download directory, reporting
  /// progress through [downloadState], and triggers the system installer once
  /// the file is complete.
  Future<void> startDownload(ReleaseAsset asset) async {
    if (downloadState is UpdateDownloadProgress) return;
    final resolver = resolveDownloadDirectory;
    downloadState = const UpdateDownloadProgress(received: 0);
    installFailure = null;
    notifyListeners();
    try {
      if (resolver == null) {
        throw const ReleaseException('当前环境不支持应用内下载，请打开发布页下载');
      }
      final directory = await resolver();
      final path = await repository.downloadAsset(
        asset,
        directory,
        onProgress: (received, total) {
          downloadState = UpdateDownloadProgress(
            received: received,
            total: total,
          );
          notifyListeners();
        },
      );
      downloadState = UpdateDownloadReady(path);
      notifyListeners();
      await installDownloaded();
    } on Object catch (error) {
      downloadState = UpdateDownloadFailed(
        error is ReleaseException ? error.message : '下载失败，请稍后重试',
      );
      notifyListeners();
    }
  }

  /// Launches the system installer for a completed download. Failures are
  /// reported through [installFailure] without discarding the download.
  Future<void> installDownloaded() async {
    final state = downloadState;
    if (state is! UpdateDownloadReady) return;
    final installer = this.installer;
    installFailure = null;
    notifyListeners();
    if (installer == null) {
      installFailure = '当前平台不支持应用内安装，请打开发布页下载';
      notifyListeners();
      return;
    }
    try {
      await installer.installApk(state.path);
    } on AppInstallerException catch (error) {
      installFailure = error.permissionRequired
          ? '系统已打开安装权限页面，请允许「安装未知应用」后返回重试'
          : error.message;
      notifyListeners();
    }
  }

  void resetDownload() {
    downloadState = const UpdateDownloadIdle();
    installFailure = null;
    notifyListeners();
  }

  Future<void> _writePreferences(UpdatePreferences preferences) async {
    final store = this.preferences;
    if (store == null) return;
    // Preference persistence must not surface as a user-visible error.
    try {
      await store.write(preferences);
    } on Object {
      // A failed write only means the notice may reappear later.
    }
  }

  static Future<String> _platformVersion() async =>
      (await PackageInfo.fromPlatform()).version;
}
