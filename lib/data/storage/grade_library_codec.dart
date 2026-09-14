import 'dart:convert';

import 'package:zf_core/zf_core.dart';

import 'academic_account.dart';
import 'grade_store.dart';

abstract final class GradeLibraryCodec {
  static String encode(GradeLibrary library) {
    _validate(library);
    return jsonEncode({
      'version': 1,
      'selected': library.selectedAccount == null
          ? null
          : _writeScope(library.selectedAccount!),
      'accounts': [
        for (final stored in library.accounts)
          {
            'scope': _writeScope(stored.account.scope),
            'schoolName': stored.account.schoolName,
            'accountName': stored.account.accountName,
            'loginName': stored.account.loginName,
            'selectedTermKey': stored.selectedTermKey,
            'snapshot': stored.snapshot == null
                ? null
                : jsonDecode(GradeSnapshotCodec.encode(stored.snapshot!)),
          },
      ],
    });
  }

  static GradeLibrary decode(String source) {
    final data = _map(jsonDecode(source));
    if (data['version'] != 1 || data['accounts'] is! List<Object?>) {
      throw const FormatException('Unsupported grade library.');
    }
    final library = GradeLibrary(
      selectedAccount: data['selected'] == null
          ? null
          : _readScope(data['selected']),
      accounts: [
        for (final value in data['accounts']! as List<Object?>)
          _readAccount(value),
      ],
    );
    _validate(library);
    return library;
  }

  static StoredGradeAccount _readAccount(Object? value) {
    final data = _map(value);
    return StoredGradeAccount(
      account: AcademicAccountRecord(
        scope: _readScope(data['scope']),
        schoolName: _string(data['schoolName']),
        accountName: _string(data['accountName']),
        loginName: _string(data['loginName']),
      ),
      selectedTermKey: data['selectedTermKey'] == null
          ? null
          : _string(data['selectedTermKey']),
      snapshot: data['snapshot'] == null
          ? null
          : GradeSnapshotCodec.decode(jsonEncode(data['snapshot'])),
    );
  }

  static void _validate(GradeLibrary library) {
    final scopes = <AccountScope>{};
    for (final stored in library.accounts) {
      final account = stored.account;
      _string(account.scope.schoolId);
      _string(account.scope.accountId);
      _string(account.schoolName);
      _string(account.accountName);
      _string(account.loginName);
      if (!scopes.add(account.scope)) {
        throw const FormatException('Duplicate saved grade account.');
      }
    }
    if (library.selectedAccount != null &&
        !scopes.contains(library.selectedAccount)) {
      throw const FormatException('Selected grade account is missing.');
    }
  }

  static Map<String, Object?> _writeScope(AccountScope scope) => {
    'schoolId': scope.schoolId,
    'accountId': scope.accountId,
  };

  static AccountScope _readScope(Object? value) {
    final data = _map(value);
    return AccountScope(
      schoolId: _string(data['schoolId']),
      accountId: _string(data['accountId']),
    );
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('Invalid saved grades.');
    }
    return value;
  }

  static String _string(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException('Invalid saved grade field.');
    }
    return value;
  }
}
