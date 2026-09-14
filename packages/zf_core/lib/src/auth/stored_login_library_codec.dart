import 'dart:convert';

import 'account_scope.dart';
import 'auth_repository.dart';
import 'login_models.dart';
import 'school_connection.dart';
import 'school_connection_codec.dart';
import 'stored_login_codec.dart';

/// Encrypted-vault payload only. It must never be included in diagnostics.
abstract final class StoredLoginLibraryCodec {
  static String encode(StoredLoginLibrary library) {
    _validate(library);
    return jsonEncode({
      'version': 2,
      'schools': [
        for (final school in library.schools)
          {
            'profile': SchoolConnectionCodec.toMap(school.profile),
            'lastAccountId': school.lastAccountId,
          },
      ],
      'selectedSchoolId': library.selectedSchoolId,
      'selected': library.selectedScope == null
          ? null
          : {
              'schoolId': library.selectedScope!.schoolId,
              'accountId': library.selectedScope!.accountId,
            },
      'accounts': [
        for (final record in library.accounts)
          {
            'schoolId': record.scope.schoolId,
            if (record.login case final login?)
              'login': _loginData(login)
            else
              'account': {
                'id': record.account.id,
                'displayName': record.account.displayName,
                'loginName': record.account.loginName,
                'studentId': record.account.studentId,
              },
          },
      ],
    });
  }

  static Map<String, Object?> _loginData(StoredLogin login) =>
      _map(jsonDecode(StoredLoginCodec.encode(login)))..remove('profile');

  static StoredLoginLibrary decode(String payload) {
    final root = _map(jsonDecode(payload));
    final version = root['version'];
    if ((version != 1 && version != 2) || root['accounts'] is! List<Object?>) {
      throw const FormatException('Invalid saved account library.');
    }
    final List<StoredSchool>? schools;
    if (version == 2) {
      final entries = root['schools'];
      if (entries is! List<Object?>) {
        throw const FormatException('Missing saved school directory.');
      }
      schools = [for (final entry in entries) _school(_map(entry))];
    } else {
      schools = null;
    }
    final profiles = {
      for (final school in schools ?? const <StoredSchool>[])
        school.profile.school.id: school.profile,
    };
    final selected = root['selected'] == null ? null : _map(root['selected']);
    if (version == 2 && selected != null && root['selectedSchoolId'] == null) {
      throw const FormatException('Selected school is missing.');
    }
    final library = StoredLoginLibrary(
      schools: schools,
      selectedSchoolId: version == 2
          ? _optionalString(root, 'selectedSchoolId')
          : null,
      accounts: [
        for (final value in root['accounts']! as List<Object?>)
          _account(_map(value), profiles: version == 2 ? profiles : null),
      ],
      selectedScope: selected == null
          ? null
          : AccountScope(
              schoolId: _string(selected, 'schoolId'),
              accountId: _string(selected, 'accountId'),
            ),
    );
    _validate(library);
    return library;
  }

  static StoredSchool _school(Map<String, Object?> data) => StoredSchool(
    profile: SchoolConnectionCodec.fromMap(data['profile']),
    lastAccountId: _optionalString(data, 'lastAccountId'),
  );

  static StoredAuthAccount _account(
    Map<String, Object?> data, {
    Map<String, SchoolConnection>? profiles,
  }) {
    SchoolConnection? profile;
    if (profiles != null) {
      profile = profiles[_string(data, 'schoolId')];
      if (profile == null) {
        throw const FormatException('Saved account school is missing.');
      }
    }
    if (data['login'] case final login?) {
      return StoredAuthAccount.fromLogin(
        StoredLoginCodec.decode(
          jsonEncode({
            ..._map(login),
            if (profile != null)
              'profile': SchoolConnectionCodec.toMap(profile),
          }),
        ),
      );
    }
    final account = _map(data['account']);
    final studentId = account['studentId'];
    if (studentId != null && studentId is! String) {
      throw const FormatException('Invalid saved student identity.');
    }
    return StoredAuthAccount(
      profile: profile ?? SchoolConnectionCodec.fromMap(data['profile']),
      account: LoginAccount(
        id: _string(account, 'id'),
        displayName: _string(account, 'displayName'),
        loginName: _string(account, 'loginName'),
        studentId: studentId as String?,
      ),
    );
  }

  static void _validate(StoredLoginLibrary library) {
    final schools = <String>{};
    for (final school in library.schools) {
      if (!schools.add(school.profile.school.id)) {
        throw const FormatException('Duplicate saved school.');
      }
    }
    final scopes = <AccountScope>{};
    for (final record in library.accounts) {
      if (!schools.contains(record.scope.schoolId) ||
          !scopes.add(record.scope)) {
        throw const FormatException('Invalid or duplicate saved account.');
      }
      final login = record.login;
      if (login != null &&
          (login.profile.school.id != record.scope.schoolId ||
              login.session.account.id != record.scope.accountId)) {
        throw const FormatException('Saved account and session do not match.');
      }
    }
    for (final school in library.schools) {
      if (school.lastAccountId != null &&
          !scopes.contains(
            AccountScope(
              schoolId: school.profile.school.id,
              accountId: school.lastAccountId!,
            ),
          )) {
        throw const FormatException('Last selected school account is missing.');
      }
    }
    if (library.selectedSchoolId != null &&
        !schools.contains(library.selectedSchoolId)) {
      throw const FormatException('Selected saved school is missing.');
    }
    if (library.selectedScope != null &&
        (!scopes.contains(library.selectedScope) ||
            library.selectedScope!.schoolId != library.selectedSchoolId)) {
      throw const FormatException(
        'Selected saved account does not match school.',
      );
    }
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('Invalid saved account structure.');
    }
    return value;
  }

  static String _string(Map<String, Object?> data, String key) {
    final value = data[key];
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException('Invalid saved account field.');
    }
    return value;
  }

  static String? _optionalString(Map<String, Object?> data, String key) =>
      data[key] == null ? null : _string(data, key);
}
