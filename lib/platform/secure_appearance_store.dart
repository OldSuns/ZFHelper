import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/storage/appearance_store.dart';

final class SecureAppearanceStore implements AppearanceStore {
  SecureAppearanceStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              resetOnError: false,
              storageNamespace: 'zfhelper_settings',
            ),
          );

  static const _key = 'zfhelper.appearance.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<AppAppearance> read() async {
    try {
      return switch (await _storage.read(key: _key)) {
        null || 'system' => AppAppearance.system,
        'light' => AppAppearance.light,
        'dark' => AppAppearance.dark,
        _ => throw const AppearanceStorageException('保存的外观设置无法识别，请重新选择外观。'),
      };
    } on PlatformException {
      throw const AppearanceStorageException('无法读取外观设置，请重试读取或重新选择。');
    }
  }

  @override
  Future<void> write(AppAppearance appearance) async {
    try {
      await _storage.write(key: _key, value: appearance.name);
    } on PlatformException {
      throw const AppearanceStorageException('外观设置未能保存，请重新选择并重试。');
    }
  }
}
