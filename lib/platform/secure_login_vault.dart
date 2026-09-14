import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:zf_core/zf_core.dart';

final class SecureLoginVault implements LoginVault {
  SecureLoginVault({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              resetOnError: false,
              storageNamespace: 'zfhelper_login',
            ),
          );

  static const _key = 'zfhelper.active_login.v1';
  static const _schoolKey = 'zfhelper.selected_school.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<SchoolConnection?> readSchool() async {
    try {
      final payload = await _storage.read(key: _schoolKey);
      return payload == null ? null : SchoolConnectionCodec.decode(payload);
    } on PlatformException {
      throw const LoginFailure(LoginFailureCode.storage, '无法读取本机保存的学校设置，请重试');
    } on FormatException {
      throw const LoginFailure(LoginFailureCode.storage, '保存的学校设置格式异常，请重新设置学校');
    }
  }

  @override
  Future<void> writeSchool(SchoolConnection profile) async {
    try {
      await _storage.write(
        key: _schoolKey,
        value: SchoolConnectionCodec.encode(profile),
      );
    } on PlatformException {
      throw const LoginFailure(LoginFailureCode.storage, '学校设置未能保存到本机，请重试');
    }
  }

  @override
  Future<StoredLogin?> read() async {
    try {
      final payload = await _storage.read(key: _key);
      return payload == null ? null : StoredLoginCodec.decode(payload);
    } on PlatformException {
      throw const LoginFailure(
        LoginFailureCode.storage,
        '无法读取本机保存的登录信息，请重试或清除保存的信息',
      );
    } on FormatException {
      throw const LoginFailure(
        LoginFailureCode.storage,
        '本机保存的登录信息格式异常，请重新登录或清除保存的信息',
      );
    }
  }

  @override
  Future<void> write(StoredLogin login) async {
    try {
      await _storage.write(key: _key, value: StoredLoginCodec.encode(login));
    } on PlatformException {
      throw const LoginFailure(
        LoginFailureCode.storage,
        '登录已验证，但未能保存到本机；本次连接可用，请在设置中重试',
      );
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } on PlatformException {
      throw const LoginFailure(
        LoginFailureCode.storage,
        '本次连接已停止，但保存的登录信息未能清除，请重试清除',
      );
    }
  }
}
