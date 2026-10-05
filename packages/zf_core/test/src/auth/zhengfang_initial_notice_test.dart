import 'package:test/test.dart';
import 'package:zf_core/src/auth/login_models.dart';

import 'login_test_support.dart';

void main() {
  test('an anonymous lockout policy notice cannot reject an account before username submission', () async {
    final cipher = RecordingPasswordCipher();
    final transport = ScriptedAuthTransport([
      (request) =>
          textResponse(request, loginPage(notice: '密码错误若干次后账号会锁定，请核对后登录。')),
      keyResponse,
      (request) {
        expect(request.method, 'POST');
        expect(formValues(request, 'yhm'), ['20260001']);
        return successRedirect(request);
      },
      accountResponse,
    ]);

    expect(
      await gatewayFor(transport, cipher: cipher).loginPassword(credentials),
      isA<LoginSuccess>(),
    );
    expect(cipher.calls, hasLength(1));
    expect(transport.requests.map((request) => request.method), [
      'GET',
      'GET',
      'POST',
      'GET',
    ]);
  });
}
