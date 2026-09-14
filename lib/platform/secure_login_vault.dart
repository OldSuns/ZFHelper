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
  static const _accountsKey = 'zfhelper.accounts.v1';
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
  Future<StoredLoginLibrary> readAccounts() async {
    try {
      final accounts = await _storage.read(key: _accountsKey);
      if (accounts != null) return StoredLoginLibraryCodec.decode(accounts);
      final payload = await _storage.read(key: _key);
      if (payload == null) return StoredLoginLibrary();
      final library = StoredLoginLibrary.fromLogin(
        StoredLoginCodec.decode(payload),
      );
      // Establish the new library before deleting the old single-account key.
      // A failed migration leaves the original encrypted record available.
      await writeAccounts(library);
      return library;
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
  Future<void> writeAccounts(StoredLoginLibrary library) async {
    try {
      await _storage.write(
        key: _accountsKey,
        value: StoredLoginLibraryCodec.encode(library),
      );
      await _storage.delete(key: _key);
    } on PlatformException {
      throw const LoginFailure(
        LoginFailureCode.storage,
        '账号信息未能完整写入安全存储，请重试；重启后仍可能读取此前保存的信息',
      );
    } on FormatException {
      throw const LoginFailure(LoginFailureCode.storage, '账号信息格式异常，无法写入安全存储');
    }
  }

  @override
  Future<StoredLogin?> read() async => (await readAccounts()).selected?.login;

  @override
  Future<void> write(StoredLogin login) async {
    final library = await readAccounts();
    final account = StoredAuthAccount.fromLogin(login);
    await writeAccounts(
      StoredLoginLibrary(
        accounts: [
          for (final saved in library.accounts)
            if (saved.scope != account.scope) saved,
          account,
        ],
        selectedScope: account.scope,
      ),
    );
  }

  @override
  Future<void> clear() async {
    final library = await readAccounts();
    await writeAccounts(
      StoredLoginLibrary(
        accounts: [
          for (final saved in library.accounts)
            saved.scope == library.selectedScope ? saved.withoutLogin() : saved,
        ],
        selectedScope: library.selectedScope,
      ),
    );
  }
}
