import 'dart:convert';

import 'school_connection.dart';

/// Stores the selected school independently of its account's login session.
abstract final class SchoolConnectionCodec {
  static String encode(SchoolConnection profile) =>
      jsonEncode({'version': 1, 'profile': toMap(profile)});

  static SchoolConnection decode(String payload) {
    final data = jsonDecode(payload);
    if (data is! Map<String, Object?> || data['version'] != 1) {
      throw const FormatException('Invalid saved school version.');
    }
    return fromMap(data['profile']);
  }

  static Map<String, Object?> toMap(SchoolConnection profile) => {
    'name': profile.name,
    'baseUri': profile.baseUri.toString(),
    'loginPath': profile.loginPath,
    'publicKeyPath': profile.publicKeyPath,
    'captchaPath': profile.captchaPath,
    'accountPath': profile.accountPath,
    'schedulePagePath': profile.schedulePagePath,
    'scheduleQueryPath': profile.scheduleQueryPath,
    'schedulePeriodsPath': profile.schedulePeriodsPath,
    'webLoginUri': profile.webLoginUri?.toString(),
  };

  static SchoolConnection fromMap(Object? value, {bool legacyLogin = false}) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('Invalid saved school structure.');
    }
    final webLogin = _optionalString(value, 'webLoginUri');
    return SchoolConnection(
      name: _string(value, 'name'),
      baseUri: Uri.parse(_string(value, 'baseUri')),
      loginPath: _string(value, 'loginPath'),
      publicKeyPath: _string(value, 'publicKeyPath'),
      captchaPath: _string(value, 'captchaPath'),
      accountPath: _string(value, 'accountPath'),
      schedulePagePath: legacyLogin
          ? SchoolConnection.defaultSchedulePath
          : _string(value, 'schedulePagePath'),
      scheduleQueryPath: legacyLogin
          ? SchoolConnection.defaultSchedulePath
          : _string(value, 'scheduleQueryPath'),
      schedulePeriodsPath: legacyLogin
          ? null
          : _optionalString(value, 'schedulePeriodsPath'),
      webLoginUri: webLogin == null ? null : Uri.parse(webLogin),
    );
  }

  static String _string(Map<String, Object?> data, String key) {
    final value = _optionalString(data, key);
    if (value == null || value.trim().isEmpty) {
      throw FormatException('Invalid saved school field: $key.');
    }
    return value;
  }

  static String? _optionalString(Map<String, Object?> data, String key) {
    final value = data[key];
    if (value != null && value is! String) {
      throw FormatException('Invalid saved school field: $key.');
    }
    return value as String?;
  }
}
