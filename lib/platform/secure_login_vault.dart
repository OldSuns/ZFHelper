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
  static const _accountsKey = 'zfhelper.accounts.v2';
  static const _legacyAccountsKey = 'zfhelper.accounts.v1';
  static const _schoolKey = 'zfhelper.selected_school.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<SchoolConnection?> readSchool() async =>
      (await readAccounts()).selectedSchool?.profile;

  @override
  Future<void> writeSchool(SchoolConnection profile) async {
    final library = await readAccounts();
    final id = profile.school.id;
    final previous = library.schools
        .where((school) => school.profile.school.id == id)
        .firstOrNull;
    await writeAccounts(
      StoredLoginLibrary(
        schools: [
          for (final school in library.schools)
            if (school.profile.school.id != id) school,
          StoredSchool(
            profile: profile,
            lastAccountId: previous?.lastAccountId,
          ),
        ],
        accounts: [
          for (final account in library.accounts)
            account.scope.schoolId == id
                ? account.withProfile(profile)
                : account,
        ],
        selectedSchoolId: id,
        selectedScope: library.selectedScope?.schoolId == id
            ? library.selectedScope
            : null,
      ),
    );
  }

  @override
  Future<StoredLoginLibrary> readAccounts() async {
    try {
      final accounts = await _storage.read(key: _accountsKey);
      if (accounts != null) return StoredLoginLibraryCodec.decode(accounts);
      final legacyAccounts = await _storage.read(key: _legacyAccountsKey);
      final payload = legacyAccounts == null
          ? await _storage.read(key: _key)
          : null;
      final schoolPayload = await _storage.read(key: _schoolKey);
      if (legacyAccounts == null && payload == null && schoolPayload == null) {
        return StoredLoginLibrary();
      }
      final old = legacyAccounts != null
          ? StoredLoginLibraryCodec.decode(legacyAccounts)
          : StoredLoginLibrary.fromLogin(
              payload == null ? null : StoredLoginCodec.decode(payload),
            );
      final schools = {
        for (final school in old.schools) school.profile.school.id: school,
      };
      final school = schoolPayload == null
          ? null
          : SchoolConnectionCodec.decode(schoolPayload);
      if (school != null) {
        schools[school.school.id] = StoredSchool(
          profile: school,
          lastAccountId: schools[school.school.id]?.lastAccountId,
        );
      }
      final library = StoredLoginLibrary(
        accounts: [
          for (final account in old.accounts)
            account.withProfile(schools[account.scope.schoolId]!.profile),
        ],
        schools: schools.values.toList(),
        selectedScope: old.selectedScope,
        selectedSchoolId:
            old.selectedScope?.schoolId ??
            school?.school.id ??
            old.selectedSchoolId,
      );
      // Commit the whole directory before removing any legacy encrypted keys.
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
      await _storage.delete(key: _legacyAccountsKey);
      await _storage.delete(key: _schoolKey);
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
        schools: [
          for (final school in library.schools)
            if (school.profile.school.id != account.scope.schoolId) school,
          StoredSchool(
            profile: login.profile,
            lastAccountId: account.account.id,
          ),
        ],
        selectedSchoolId: account.scope.schoolId,
        accounts: [
          for (final saved in library.accounts)
            if (saved.scope != account.scope)
              saved.scope.schoolId == account.scope.schoolId
                  ? saved.withProfile(login.profile)
                  : saved,
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
        schools: library.schools,
        selectedSchoolId: library.selectedSchoolId,
        accounts: [
          for (final saved in library.accounts)
            saved.scope == library.selectedScope ? saved.withoutLogin() : saved,
        ],
        selectedScope: library.selectedScope,
      ),
    );
  }
}
