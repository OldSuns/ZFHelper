import 'package:test/test.dart';
import 'package:zf_core/src/auth/login_models.dart';

import 'login_test_support.dart';

void main() {
  group('account verification identity boundary', () {
    for (final heading in ['欢迎登录', '未登录用户']) {
      test('rejects a visible login form with the heading $heading', () async {
        final transport =
            ScriptedAuthTransport([
                (request) => textResponse(
                  request,
                  '${loginPage()}<h4 class="media-heading">$heading</h4>',
                ),
              ])
              ..availableCookies = const [
                LoginCookie(
                  name: 'JSESSIONID',
                  value: 'synthetic-anonymous-cookie',
                ),
              ];
        final gateway = gatewayFor(transport);
        addTearDown(gateway.close);

        await expectLater(
          gateway.verifySession(usernameHint: '20260001'),
          throwsA(
            isA<LoginFailure>().having(
              (failure) => failure.code,
              'code',
              LoginFailureCode.expired,
            ),
          ),
        );
        expect(transport.cookieReads, isEmpty);
      });
    }

    test(
      'accepts account metadata stored in hidden login-named fields',
      () async {
        final transport = ScriptedAuthTransport([
          (request) => textResponse(request, '''
            <input name="xm" value="李明"><input name="xh" value="20260002">
            <input type="hidden" name="yhm" value="20260002">
            <input type="hidden" name="mm" value="">
          '''),
        ]);
        final gateway = gatewayFor(transport);
        addTearDown(gateway.close);
        final session = await gateway.verifySession();
        expect(session.account.id, '20260002');
      },
    );

    test(
      'accepts verified identity alongside a hidden login template',
      () async {
        final transport = ScriptedAuthTransport([
          (request) => textResponse(request, '''
          <input name="xm" value="李明"><input name="xh" value="20260002">
          <div hidden>
            <form><input name="yhm"><input name="mm" type="password"></form>
          </div>
          <p>修改密码后请重新登录。</p>
        '''),
        ]);
        final gateway = gatewayFor(transport);
        addTearDown(gateway.close);

        final session = await gateway.verifySession();

        expect(session.account.id, '20260002');
        expect(session.account.studentId, '20260002');
        expect(session.account.displayName, '李明');
        expect(transport.cookieReads, [defaultProfile.accountUri]);
      },
    );
  });
}
