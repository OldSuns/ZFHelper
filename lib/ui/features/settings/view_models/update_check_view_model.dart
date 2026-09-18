import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../data/repositories/release_repository.dart';

typedef VersionReader = Future<String> Function();

final class UpdateCheckViewModel extends ChangeNotifier {
  UpdateCheckViewModel({required this.repository, VersionReader? readVersion})
    : _readVersion = readVersion ?? _platformVersion;

  final ReleaseRepository repository;
  final VersionReader _readVersion;

  bool isBusy = false;
  bool? updateAvailable;
  String? currentVersion;
  ReleaseInfo? latest;
  ReleaseInfo? currentRelease;
  String? failure;

  Future<void> check() async {
    if (isBusy) return;
    isBusy = true;
    failure = null;
    updateAvailable = null;
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
      failure = error is ReleaseException ? error.message : '检查更新失败，请稍后重试';
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  static Future<String> _platformVersion() async =>
      (await PackageInfo.fromPlatform()).version;
}
