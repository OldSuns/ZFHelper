import 'dart:convert';

import 'account_scope.dart';
import 'auth_repository.dart';
import 'login_models.dart';
import 'school_connection_codec.dart';
import 'stored_login_codec.dart';

/// Encrypted-vault payload only. It must never be included in diagnostics.
abstract final class StoredLoginLibraryCodec {
  static String encode(StoredLoginLibrary library) {
    _validate(library);
    return jsonEncode({
      'version': 1,
      'selected': library.selectedScope == null
          ? null
          : {
              'schoolId': library.selectedScope!.schoolId,
              'accountId': library.selectedScope!.accountId,
            },
      'accounts': [
        for (final record in library.accounts)
          if (record.login case final login?)
            {'login': jsonDecode(StoredLoginCodec.encode(login))}
          else
            {
              'profile': SchoolConnectionCodec.toMap(record.profile),
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

  static StoredLoginLibrary decode(String payload) {
    final root = _map(jsonDecode(payload));
    if (root['version'] != 1 || root['accounts'] is! List<Object?>) {
      throw const FormatException('Invalid saved account library.');
    }
    final selected = root['selected'] == null ? null : _map(root['selected']);
    final library = StoredLoginLibrary(
      accounts: [
        for (final value in root['accounts']! as List<Object?>)
          _account(_map(value)),
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

  static StoredAuthAccount _account(Map<String, Object?> data) {
    if (data['login'] case final login?) {
      return StoredAuthAccount.fromLogin(
        StoredLoginCodec.decode(jsonEncode(login)),
      );
    }
    final account = _map(data['account']);
    final studentId = account['studentId'];
    if (studentId != null && studentId is! String) {
      throw const FormatException('Invalid saved student identity.');
    }
    return StoredAuthAccount(
      profile: SchoolConnectionCodec.fromMap(data['profile']),
      account: LoginAccount(
        id: _string(account, 'id'),
        displayName: _string(account, 'displayName'),
        loginName: _string(account, 'loginName'),
        studentId: studentId as String?,
      ),
    );
  }

  static void _validate(StoredLoginLibrary library) {
    final scopes = <AccountScope>{};
    for (final record in library.accounts) {
      if (!scopes.add(record.scope)) {
        throw const FormatException('Duplicate saved account.');
      }
      final login = record.login;
      if (login != null &&
          (login.profile.school.id != record.scope.schoolId ||
              login.session.account.id != record.scope.accountId)) {
        throw const FormatException('Saved account and session do not match.');
      }
    }
    if (library.selectedScope != null &&
        !scopes.contains(library.selectedScope)) {
      throw const FormatException('Selected saved account is missing.');
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
}
