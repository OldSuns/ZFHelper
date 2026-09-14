import 'dart:convert';

import 'package:test/test.dart';
import 'package:zf_core/src/auth/auth_repository.dart';
import 'package:zf_core/src/auth/login_models.dart';
import 'package:zf_core/src/auth/school_connection.dart';
import 'package:zf_core/src/auth/stored_login_codec.dart';

import 'auth_state_test_support.dart';

void main() {
  const beyondDateTimeRange = 8640000000000001;
  final expiry = DateTime.utc(2027, 1, 2, 3, 4, 5);
  final profile = SchoolConnection(
    name: '保存配置测试',
    baseUri: Uri.parse('https://school.example/department/newzf/'),
    loginPath: 'auth/form.html',
    publicKeyPath: 'auth/public-key',
    captchaPath: 'images/code',
    accountPath: 'account/info.html',
    schedulePagePath: 'schedule/index?gnmkdm=N2151',
    scheduleQueryPath: 'schedule/query?gnmkdm=N2151',
    schedulePeriodsPath: 'schedule/periods',
    webLoginUri: Uri.parse(
      'https://identity.example/cas/login?service=teaching',
    ),
  );
  final record = StoredLogin(
    profile: profile,
    session: stateTestSession(
      cookies: [
        LoginCookie(
          name: 'JSESSIONID',
          value: 'synthetic-value',
          domain: '.school.example',
          path: '/department/newzf/',
          secure: true,
          httpOnly: true,
          expiresAt: expiry,
        ),
        const LoginCookie(
          name: 'route',
          value: '',
          secure: false,
          httpOnly: false,
        ),
      ],
    ),
    method: LoginMethod.password,
    credentials: LoginCredentials(
      username: ' student-a ',
      password: '  测试 密码\t!  ',
    ),
  );

  test('preserves cookie scope, security flags, and expiry through vault serialization', () {
    final restored = StoredLoginCodec.decode(StoredLoginCodec.encode(record));

    expect(
      restored.session.cookies.map(
        (cookie) => (
          cookie.name,
          cookie.value,
          cookie.domain,
          cookie.path,
          cookie.secure,
          cookie.httpOnly,
          cookie.expiresAt?.millisecondsSinceEpoch,
        ),
      ),
      [
        (
          'JSESSIONID',
          'synthetic-value',
          '.school.example',
          '/department/newzf/',
          true,
          true,
          expiry.millisecondsSinceEpoch,
        ),
        ('route', '', null, null, false, false, null),
      ],
    );
    expect(
      restored.session.verifiedAt.millisecondsSinceEpoch,
      stateTestTime.millisecondsSinceEpoch,
    );
    expect(() => restored.session.cookies.clear(), throwsUnsupportedError);
  });

  test(
    'preserves native deployment paths and the separate external browser entry',
    () {
      final restored = StoredLoginCodec.decode(StoredLoginCodec.encode(record));

      expect(restored.profile.baseUri, profile.baseUri);
      expect(restored.profile.loginUri, profile.loginUri);
      expect(restored.profile.publicKeyUri, profile.publicKeyUri);
      expect(restored.profile.captchaUri, profile.captchaUri);
      expect(restored.profile.accountUri, profile.accountUri);
      expect(restored.profile.schedulePageUri, profile.schedulePageUri);
      expect(restored.profile.scheduleQueryUri, profile.scheduleQueryUri);
      expect(restored.profile.schedulePeriodsUri, profile.schedulePeriodsUri);
      expect(restored.profile.browserUri, profile.browserUri);
      expect(restored.profile.browserUri.origin, 'https://identity.example');
      expect(restored.profile.accountUri.origin, 'https://school.example');
    },
  );

  test('never trims password whitespace while normalizing the login name', () {
    final restored = StoredLoginCodec.decode(StoredLoginCodec.encode(record));

    expect(restored.credentials?.password, '  测试 密码\t!  ');
    expect(restored.credentials?.username, 'student-a');
    expect(restored.session.account.id, 'student-a');
    expect(restored.method, LoginMethod.password);
  });

  test('keeps password-free records password-free', () {
    final stored = stateTestStored(method: LoginMethod.cookie);
    final restored = StoredLoginCodec.decode(StoredLoginCodec.encode(stored));

    expect(restored.credentials, isNull);
    expect(restored.method, LoginMethod.cookie);
    expect(restored.session.account.loginName, 'student-a');
  });

  test('migrates a version one login without changing its identity', () {
    final data = jsonDecode(StoredLoginCodec.encode(record))
        as Map<String, dynamic>;
    data['version'] = 1;
    final oldProfile = _object(data, 'profile')
      ..remove('schedulePagePath')
      ..remove('scheduleQueryPath')
      ..remove('schedulePeriodsPath');
    expect(oldProfile.containsKey('scheduleQueryPath'), isFalse);

    final restored = StoredLoginCodec.decode(jsonEncode(data));
    expect(restored.session.account.id, record.session.account.id);
    expect(restored.profile.schedulePagePath, SchoolConnection.defaultSchedulePath);
    expect(restored.profile.scheduleQueryPath, SchoolConnection.defaultSchedulePath);
    expect(restored.profile.schedulePeriodsPath, isNull);
    expect(restored.profile.loginUri, profile.loginUri);
  });

  test('rejects invalid JSON and non-object roots', () {
    for (final payload in ['{', 'null', '[]', '"login"']) {
      expect(() => StoredLoginCodec.decode(payload), throwsFormatException);
    }
  });

  final corruptions =
      <({String name, void Function(Map<String, dynamic>) mutate})>[
        (name: 'unsupported version', mutate: (data) => data['version'] = 3),
        (name: 'missing profile', mutate: (data) => data.remove('profile')),
        (
          name: 'blank account identity',
          mutate: (data) => _object(data, 'account')['id'] = '  ',
        ),
        (
          name: 'missing login name',
          mutate: (data) => _object(data, 'account').remove('loginName'),
        ),
        (
          name: 'cookies are not a list',
          mutate: (data) => data['cookies'] = <String, Object?>{},
        ),
        (
          name: 'cookie security flag is not boolean',
          mutate: (data) => _firstCookie(data)['secure'] = 'true',
        ),
        (
          name: 'cookie expiry is not an integer',
          mutate: (data) => _firstCookie(data)['expiresAt'] = 'tomorrow',
        ),
        (
          name: 'verification time is missing',
          mutate: (data) => data.remove('verifiedAt'),
        ),
        (
          name: 'verification time exceeds the supported date range',
          mutate: (data) => data['verifiedAt'] = beyondDateTimeRange,
        ),
        (
          name: 'cookie expiry exceeds the supported date range',
          mutate: (data) =>
              _firstCookie(data)['expiresAt'] = beyondDateTimeRange,
        ),
        (
          name: 'unknown login method',
          mutate: (data) => data['method'] = 'unrecognized',
        ),
        (
          name: 'password has the wrong type',
          mutate: (data) => _object(data, 'credentials')['password'] = 123,
        ),
        (
          name: 'invalid school base URI',
          mutate: (data) =>
              _object(data, 'profile')['baseUri'] = 'ftp://school.example/',
        ),
        (
          name: 'invalid browser entry',
          mutate: (data) =>
              _object(data, 'profile')['webLoginUri'] = 'javascript:invalid',
        ),
      ];
  for (final corruption in corruptions) {
    test('rejects damaged schema: ${corruption.name}', () {
      final data =
          jsonDecode(StoredLoginCodec.encode(record)) as Map<String, dynamic>;
      corruption.mutate(data);

      expect(
        () => StoredLoginCodec.decode(jsonEncode(data)),
        throwsFormatException,
      );
    });
  }
}

Map<String, dynamic> _object(Map<String, dynamic> data, String key) =>
    data[key] as Map<String, dynamic>;

Map<String, dynamic> _firstCookie(Map<String, dynamic> data) =>
    (data['cookies'] as List<Object?>).first as Map<String, dynamic>;
