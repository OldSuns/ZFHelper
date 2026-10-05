import 'dart:typed_data';

import 'package:zf_core/zf_core.dart';

final testProfile = SchoolConnection(
  name: '示例大学',
  baseUri: Uri.parse('https://jw.example.test/jwglxt/'),
);

LoginSession testSession({String id = '20260001', String name = '测试同学'}) =>
    LoginSession(
      account: LoginAccount(
        id: id,
        displayName: name,
        loginName: id,
        studentId: id,
      ),
      cookies: const [LoginCookie(name: 'JSESSIONID', value: 'test-session')],
      verifiedAt: DateTime(2026, 9, 12, 13),
    );

AuthRepository testAuth({
  SchoolConnection? profile,
  LoginGatewayFactory? gatewayFactory,
  TestLoginVault? vault,
}) => AuthRepository(
  initialProfile: profile ?? testProfile,
  gatewayFactory:
      gatewayFactory ??
      (_) => throw StateError('Unexpected authentication request.'),
  vault: vault ?? TestLoginVault(),
);

final class TestLoginVault implements LoginVault {
  StoredLogin? saved;
  StoredLoginLibrary? library;
  SchoolConnection? school;
  LoginFailure? writeFailure;
  LoginFailure? schoolWriteFailure;
  int writes = 0;
  int clears = 0;

  @override
  Future<SchoolConnection?> readSchool() async => school;

  @override
  Future<StoredLoginLibrary> readAccounts() async =>
      library ??
      (saved != null
          ? StoredLoginLibrary.fromLogin(saved)
          : StoredLoginLibrary(
              schools: school == null ? [] : [StoredSchool(profile: school!)],
              selectedSchoolId: school?.school.id,
            ));

  @override
  Future<void> writeAccounts(StoredLoginLibrary value) async {
    if (schoolWriteFailure case final failure?) throw failure;
    final selected = value.selected?.login;
    if (selected == null) {
      await clear();
    } else {
      await write(selected);
    }
    library = value;
    school = value.selectedSchool?.profile;
  }

  @override
  Future<void> writeSchool(SchoolConnection profile) async {
    if (schoolWriteFailure case final failure?) throw failure;
    school = profile;
  }

  @override
  Future<StoredLogin?> read() async => saved;

  @override
  Future<void> write(StoredLogin login) async {
    if (writeFailure case final failure?) throw failure;
    writes++;
    saved = login;
  }

  @override
  Future<void> clear() async {
    clears++;
    saved = null;
  }
}

final class TestLoginGateway implements LoginGateway {
  Future<LoginStep> Function(LoginCredentials)? onPassword;
  Future<LoginStep> Function(String)? onCaptcha;
  Future<Uint8List> Function()? onRefreshCaptcha;
  Future<LoginSession> Function(List<LoginCookie>, String)? onImport;
  Future<LoginSession> Function(String)? onVerify;
  LoginCredentials? credentials;
  List<LoginCookie>? importedCookies;
  int passwordCalls = 0;
  int verifyCalls = 0;
  bool closed = false;
  LoginSession? _session;

  @override
  Future<LoginStep> loginPassword(LoginCredentials credentials) async {
    passwordCalls++;
    this.credentials = credentials;
    final handler =
        onPassword ?? (throw StateError('Unexpected password login.'));
    return _recordStep(await handler(credentials));
  }

  @override
  Future<LoginStep> submitCaptcha(String captcha) async {
    final handler =
        onCaptcha ?? (throw StateError('Unexpected captcha submit.'));
    return _recordStep(await handler(captcha));
  }

  @override
  Future<Uint8List> refreshCaptcha() =>
      onRefreshCaptcha?.call() ??
      (throw StateError('Unexpected captcha refresh.'));

  @override
  Future<LoginSession> importCookies(
    List<LoginCookie> cookies, {
    String usernameHint = '',
  }) async {
    importedCookies = cookies;
    final handler = onImport ?? (throw StateError('Unexpected cookie import.'));
    return _session = await handler(cookies, usernameHint);
  }

  @override
  Future<LoginSession> verifySession({String usernameHint = ''}) async {
    verifyCalls++;
    final handler = onVerify ?? (throw StateError('Unexpected session check.'));
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
  void close() => closed = true;
}
