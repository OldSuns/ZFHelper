import 'dart:async';
import 'dart:typed_data';

import 'package:zf_core/src/auth/auth_repository.dart';
import 'package:zf_core/src/auth/login_gateway.dart';
import 'package:zf_core/src/auth/login_models.dart';
import 'package:zf_core/src/auth/school_connection.dart';

/// Explicit test gateway: unconfigured operations fail instead of succeeding.
final class StateTestGateway implements LoginGateway {
  FutureOr<LoginStep> Function(LoginCredentials)? onPassword;
  FutureOr<LoginStep> Function(String)? onCaptcha;
  FutureOr<Uint8List> Function()? onRefreshCaptcha;
  FutureOr<LoginSession> Function(List<LoginCookie>, String)? onImportCookies;
  FutureOr<LoginSession> Function(String)? onVerify;

  final List<LoginCredentials> passwordCalls = [];
  final List<String> captchaCalls = [];
  final List<({List<LoginCookie> cookies, String hint})> importCalls = [];
  final List<String> verificationCalls = [];
  int refreshCalls = 0;
  int closeCalls = 0;
  LoginSession? _session;

  bool get closed => closeCalls > 0;

  @override
  Future<LoginStep> loginPassword(LoginCredentials credentials) async {
    passwordCalls.add(credentials);
    final handler = onPassword;
    if (handler == null) throw StateError('Unexpected password login.');
    return _recordStep(await handler(credentials));
  }

  @override
  Future<LoginStep> submitCaptcha(String captcha) async {
    captchaCalls.add(captcha);
    final handler = onCaptcha;
    if (handler == null) throw StateError('Unexpected captcha submission.');
    return _recordStep(await handler(captcha));
  }

  @override
  Future<Uint8List> refreshCaptcha() async {
    refreshCalls++;
    final handler = onRefreshCaptcha;
    if (handler == null) throw StateError('Unexpected captcha refresh.');
    return handler();
  }

  @override
  Future<LoginSession> importCookies(
    List<LoginCookie> cookies, {
    String usernameHint = '',
  }) async {
    importCalls.add((cookies: List.unmodifiable(cookies), hint: usernameHint));
    final handler = onImportCookies;
    if (handler == null) throw StateError('Unexpected cookie import.');
    return _session = await handler(cookies, usernameHint);
  }

  @override
  Future<LoginSession> verifySession({String usernameHint = ''}) async {
    verificationCalls.add(usernameHint);
    final handler = onVerify;
    if (handler == null) throw StateError('Unexpected session verification.');
    return _session = await handler(usernameHint);
  }

  LoginStep _recordStep(LoginStep step) {
    if (step is LoginSuccess) _session = step.session;
    return step;
  }

  @override
  Future<List<LoginCookie>> exportCookies() async =>
      _session?.cookies ?? (throw StateError('No test session to export.'));

  @override
  void close() => closeCalls++;
}

final class StateTestGatewayFactory {
  StateTestGatewayFactory(this.gateways);

  final List<StateTestGateway> gateways;
  final List<SchoolConnection> profiles = [];

  LoginGateway call(SchoolConnection profile) {
    final index = profiles.length;
    profiles.add(profile);
    if (index >= gateways.length) {
      throw StateError('Unexpected gateway creation.');
    }
    return gateways[index];
  }
}

/// An in-memory vault with controllable completion and explicit failures.
final class StateTestVault implements LoginVault {
  StateTestVault({this.record, this.school});

  StoredLogin? record;
  SchoolConnection? school;
  FutureOr<void> Function(SchoolConnection)? beforeWriteSchool;
  FutureOr<StoredLogin?> Function()? onRead;
  FutureOr<void> Function(StoredLogin)? beforeWrite;
  FutureOr<void> Function()? beforeClear;
  final List<String> events = [];
  final List<StoredLogin> writes = [];
  int readCalls = 0;
  int clearCalls = 0;

  @override
  Future<SchoolConnection?> readSchool() async => school;

  @override
  Future<void> writeSchool(SchoolConnection profile) async {
    if (beforeWriteSchool != null) await beforeWriteSchool!(profile);
    school = profile;
  }

  @override
  Future<StoredLogin?> read() async {
    readCalls++;
    events.add('read:start');
    final result = onRead == null ? record : await onRead!();
    events.add('read:complete');
    return result;
  }

  @override
  Future<void> write(StoredLogin login) async {
    events.add('write:start');
    writes.add(login);
    if (beforeWrite != null) await beforeWrite!(login);
    record = login;
    events.add('write:complete');
  }

  @override
  Future<void> clear() async {
    clearCalls++;
    events.add('clear:start');
    if (beforeClear != null) await beforeClear!();
    record = null;
    events.add('clear:complete');
  }
}

final stateTestProfile = SchoolConnection(
  name: '测试学校甲',
  baseUri: Uri.parse('https://first.example/teaching/'),
);
final stateTestOtherProfile = SchoolConnection(
  name: '测试学校乙',
  baseUri: Uri.parse('https://second.example/jwglxt/'),
);
final stateTestCredentials = LoginCredentials(
  username: 'student-a',
  password: '  synthetic password  ',
);
final stateTestTime = DateTime.utc(2026, 9, 12, 12);

LoginSession stateTestSession({
  String id = 'student-a',
  String displayName = '测试甲',
  DateTime? verifiedAt,
  List<LoginCookie>? cookies,
}) => LoginSession(
  account: LoginAccount(
    id: id,
    displayName: displayName,
    loginName: id,
    studentId: id,
  ),
  cookies:
      cookies ??
      [LoginCookie(name: 'JSESSIONID', value: 'synthetic-session-$id')],
  verifiedAt: verifiedAt ?? stateTestTime,
);

StoredLogin stateTestStored({
  SchoolConnection? profile,
  LoginSession? session,
  LoginMethod method = LoginMethod.password,
  LoginCredentials? credentials,
}) => StoredLogin(
  profile: profile ?? stateTestProfile,
  session: session ?? stateTestSession(),
  method: method,
  credentials: credentials,
);
