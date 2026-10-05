import 'dart:convert';

import 'auth_repository.dart';
import 'login_models.dart';
import 'school_connection_codec.dart';

/// Serialization for an encrypted vault only; callers must not log the payload.
abstract final class StoredLoginCodec {
  static String encode(StoredLogin login) => jsonEncode({
    'version': 2,
    'profile': SchoolConnectionCodec.toMap(login.profile),
    'account': {
      'id': login.session.account.id,
      'displayName': login.session.account.displayName,
      'loginName': login.session.account.loginName,
      'studentId': login.session.account.studentId,
    },
    'cookies': [
      for (final cookie in login.session.cookies)
        {
          'name': cookie.name,
          'value': cookie.value,
          'domain': cookie.domain,
          'path': cookie.path,
          'secure': cookie.secure,
          'httpOnly': cookie.httpOnly,
          'expiresAt': cookie.expiresAt?.millisecondsSinceEpoch,
        },
    ],
    'verifiedAt': login.session.verifiedAt.millisecondsSinceEpoch,
    'method': login.method.name,
    'credentials': login.credentials == null
        ? null
        : {
            'username': login.credentials!.username,
            'password': login.credentials!.password,
          },
  });

  static StoredLogin decode(String payload) {
    final data = _map(jsonDecode(payload));
    final version = data['version'];
    if (version != 1 && version != 2) {
      throw const FormatException('Unsupported saved login version.');
    }
    final account = _map(data['account']);
    final cookieData = data['cookies'];
    if (cookieData is! List<Object?>) {
      throw const FormatException('Invalid saved cookies.');
    }
    final methodName = _string(data, 'method');
    final matchingMethods = LoginMethod.values.where(
      (m) => m.name == methodName,
    );
    if (matchingMethods.length != 1) {
      throw const FormatException('Invalid saved login method.');
    }
    final credentials = data['credentials'] == null
        ? null
        : _map(data['credentials']);
    return StoredLogin(
      profile: SchoolConnectionCodec.fromMap(
        data['profile'],
        legacyLogin: version == 1,
      ),
      session: LoginSession(
        account: LoginAccount(
          id: _string(account, 'id'),
          displayName: _string(account, 'displayName'),
          loginName: _string(account, 'loginName'),
          studentId: _optionalString(account, 'studentId'),
        ),
        cookies: [for (final value in cookieData) _cookie(_map(value))],
        verifiedAt: _date(_integer(data, 'verifiedAt')),
      ),
      method: matchingMethods.single,
      credentials: credentials == null
          ? null
          : LoginCredentials(
              username: _string(credentials, 'username'),
              password: _string(credentials, 'password', allowEmpty: true),
            ),
    );
  }

  static LoginCookie _cookie(Map<String, Object?> data) {
    final expires = data['expiresAt'];
    if (expires != null && expires is! int) {
      throw const FormatException('Invalid cookie expiry.');
    }
    return LoginCookie(
      name: _string(data, 'name'),
      value: _string(data, 'value', allowEmpty: true),
      domain: _optionalString(data, 'domain'),
      path: _optionalString(data, 'path'),
      secure: _boolean(data, 'secure'),
      httpOnly: _boolean(data, 'httpOnly'),
      expiresAt: expires == null ? null : _date(expires as int),
    );
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('Invalid saved login structure.');
    }
    return value;
  }

  static DateTime _date(int milliseconds) {
    try {
      return DateTime.fromMillisecondsSinceEpoch(milliseconds);
    } on RangeError {
      throw const FormatException('Invalid saved timestamp.');
    }
  }

  static String _string(
    Map<String, Object?> data,
    String key, {
    bool allowEmpty = false,
  }) {
    final value = data[key];
    if (value is! String || (!allowEmpty && value.trim().isEmpty)) {
      throw FormatException('Invalid saved field: $key.');
    }
    return value;
  }

  static String? _optionalString(Map<String, Object?> data, String key) {
    final value = data[key];
    if (value != null && value is! String) {
      throw FormatException('Invalid saved field: $key.');
    }
    return value as String?;
  }

  static int _integer(Map<String, Object?> data, String key) {
    final value = data[key];
    if (value is! int) throw FormatException('Invalid saved field: $key.');
    return value;
  }

  static bool _boolean(Map<String, Object?> data, String key) {
    final value = data[key];
    if (value is! bool) throw FormatException('Invalid saved field: $key.');
    return value;
  }
}
