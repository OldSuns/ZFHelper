import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Triggers the Android system package installer for an already-downloaded
/// APK. Other platforms have no in-app installer and stay on browser downloads.
abstract interface class AppInstallerPlatform {
  /// Requests the Android system installer for [apkPath].
  ///
  /// Throws [AppInstallerException] with code `permission_required` when the
  /// OS "install unknown apps" grant is missing; the host opens the system
  /// settings page and the caller should ask the user to retry after granting.
  Future<void> installApk(String apkPath);
}

final class AppInstallerException implements Exception {
  const AppInstallerException(this.message, {this.permissionRequired = false});

  final String message;
  final bool permissionRequired;

  @override
  String toString() => message;
}

AppInstallerPlatform? createAppInstallerPlatform() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android
    ? AndroidAppInstallerPlatform()
    : null;

final class AndroidAppInstallerPlatform implements AppInstallerPlatform {
  AndroidAppInstallerPlatform({
    this._channel = const MethodChannel('zfhelper/app_installer'),
  });

  final MethodChannel _channel;

  @override
  Future<void> installApk(String apkPath) async {
    try {
      await _channel.invokeMethod<void>('installApk', {'path': apkPath});
    } on PlatformException catch (error) {
      throw AppInstallerException(
        error.message ?? '安装器未能启动（${error.code}）',
        permissionRequired: error.code == 'permission_required',
      );
    } on MissingPluginException {
      throw const AppInstallerException('安装服务不可用，请完整重启新版应用');
    }
  }
}
