import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:zf_core/src/auth/login_models.dart';
import 'package:zf_core/src/auth/school_connection.dart';

import 'login_test_support.dart';

void main() {
  Matcher failureCode(LoginFailureCode code) => throwsA(
    isA<LoginFailure>().having((failure) => failure.code, 'code', code),
  );

  test(
    'submits encrypted fields and independently verifies a 302 response',
    () async {
      final cipher = RecordingPasswordCipher();
      final transport = ScriptedAuthTransport([
        (request) => textResponse(
          request,
          loginPage(
            duplicatePassword: true,
            extraHidden:
                '<input type="hidden" name="execution" value="flow-one">',
          ),
        ),
        (request) {
          expect(request.method, 'GET');
          expect(request.headers['X-Requested-With'], 'XMLHttpRequest');
          return keyResponse(request);
        },
        (request) {
          expect(request.method, 'POST');
          expect(request.uri.path, '/jwglxt/xtgl/login_slogin.html');
          expect(formValues(request, 'yhm'), ['20260001']);
          expect(formValues(request, 'csrftoken'), ['csrf-one']);
          expect(formValues(request, 'execution'), ['flow-one']);
          expect(formValues(request, 'mm'), [
            'synthetic-encrypted-1',
            'synthetic-encrypted-1',
          ]);
          expect(
            request.form.any((field) => field.value == credentials.password),
            isFalse,
          );
          expect(request.headers['Origin'], defaultProfile.baseUri.origin);
          return successRedirect(request);
        },
        (request) {
          expect(request.method, 'GET');
          expect(request.uri.path, defaultProfile.accountUri.path);
          expect(request.uri.queryParameters, {
            'xt': 'jw',
            'localeKey': 'zh_CN',
            'gnmkdm': 'index',
            '_': fixedTime.millisecondsSinceEpoch.toString(),
          });
          return accountResponse(request);
        },
      ]);

      final result = await gatewayFor(
        transport,
        cipher: cipher,
      ).loginPassword(credentials) as LoginSuccess;

      expect(result.session.account.id, '20260001');
      expect(result.session.account.displayName, '测试同学');
      expect(result.session.account.loginName, '20260001');
      expect(result.session.verifiedAt, fixedTime);
      expect(result.session.cookies.single.value, 'synthetic-test-session');
      expect(transport.replacements.single.cookies, isEmpty);
      expect(transport.cookieReads, [defaultProfile.accountUri]);
      expect(cipher.calls.single.password, credentials.password);
    },
  );

  test(
    'submits plaintext fields when the school disables password encryption',
    () async {
      final cipher = RecordingPasswordCipher();
      final transport = ScriptedAuthTransport([
        (request) => textResponse(
          request,
          loginPage(token: '', passwordMode: '0', duplicatePassword: true),
        ),
        (request) {
          expect(request.method, 'POST');
          expect(formValues(request, 'csrftoken'), ['']);
          expect(formValues(request, 'mm'), [
            credentials.password,
            credentials.password,
          ]);
          return successRedirect(request);
        },
        accountResponse,
      ]);

      final result = await gatewayFor(
        transport,
        cipher: cipher,
      ).loginPassword(credentials) as LoginSuccess;

      expect(result.session.account.id, '20260001');
      expect(cipher.calls, isEmpty);
    },
  );

  test('falls back to the authenticated menu for the student id', () async {
    final transport = ScriptedAuthTransport([
      (request) => textResponse(request, '<h4 class="media-heading">示例用户</h4>'),
      (request) {
        expect(request.uri.path, '/jwglxt/xtgl/index_initMenu.html');
        expect(request.uri.queryParameters['jsdm'], 'xs');
        return textResponse(
          request,
          '<input type="hidden" id="sessionUserKey" value="student-fixture">',
        );
      },
    ]);

    final session = await gatewayFor(transport).verifySession();

    expect(session.account.id, 'student-fixture');
    expect(session.account.studentId, 'student-fixture');
    expect(session.account.displayName, '示例用户');
  });

  test(
    'loads an initially visible captcha before sending any password',
    () async {
      final transport = ScriptedAuthTransport([
        (request) => textResponse(request, loginPage(visibleCaptcha: true)),
        captchaResponse,
        captchaResponse,
        keyResponse,
        successRedirect,
        accountResponse,
      ]);
      final gateway = gatewayFor(transport);

      final challenge =
          await gateway.loginPassword(credentials) as CaptchaRequired;
      expect(challenge.image, pngImage);
      expect(challenge.rejected, isFalse);
      expect(transport.requests.map((request) => request.method), [
        'GET',
        'GET',
      ]);
      expect(await gateway.refreshCaptcha(), pngImage);
      expect(await gateway.submitCaptcha('1234'), isA<LoginSuccess>());
      expect(transport.replacements, hasLength(1));
      expect(formValues(transport.requests[4], 'yzm'), ['1234']);
    },
  );

  test(
    'updates csrf and hidden fields across rejected captcha submissions',
    () async {
      final cipher = RecordingPasswordCipher();
      final transport = ScriptedAuthTransport([
        (request) => textResponse(
          request,
          loginPage(
            extraHidden: '<input type="hidden" name="obsolete" value="old">',
          ),
        ),
        keyResponse,
        (request) => textResponse(
          request,
          loginPage(
            token: 'csrf-two',
            notice: '请输入验证码',
            visibleCaptcha: true,
            extraHidden:
                '<input type="hidden" name="execution" value="flow-two">',
          ),
        ),
        captchaResponse,
        keyResponse,
        (request) {
          expect(formValues(request, 'csrftoken'), ['csrf-two']);
          expect(formValues(request, 'execution'), ['flow-two']);
          expect(formValues(request, 'obsolete'), isEmpty);
          expect(formValues(request, 'mm'), ['synthetic-encrypted-2']);
          expect(formValues(request, 'yzm'), ['bad']);
          return textResponse(
            request,
            loginPage(
              token: 'csrf-three',
              notice: '验证码不正确',
              visibleCaptcha: true,
            ),
          );
        },
        captchaResponse,
        keyResponse,
        (request) {
          expect(formValues(request, 'csrftoken'), ['csrf-three']);
          expect(formValues(request, 'execution'), isEmpty);
          expect(formValues(request, 'mm'), ['synthetic-encrypted-3']);
          return successRedirect(request);
        },
        accountResponse,
      ]);
      final gateway = gatewayFor(transport, cipher: cipher);

      expect(await gateway.loginPassword(credentials), isA<CaptchaRequired>());
      final rejected = await gateway.submitCaptcha('bad') as CaptchaRequired;
      expect(rejected.rejected, isTrue);
      expect(await gateway.submitCaptcha('correct'), isA<LoginSuccess>());
      expect(cipher.calls, hasLength(3));
      expect(transport.replacements, hasLength(1));
    },
  );

  for (final scenario in [
    (message: '用户名或密码不正确，请输入验证码', code: LoginFailureCode.invalidCredentials),
    (message: '账号已锁定，请输入验证码', code: LoginFailureCode.accountLocked),
  ]) {
    test('classifies ${scenario.code.name} before captcha notices', () async {
      final transport = ScriptedAuthTransport([
        (request) => textResponse(request, loginPage()),
        keyResponse,
        (request) => textResponse(
          request,
          loginPage(notice: scenario.message, visibleCaptcha: true),
        ),
      ]);
      final gateway = gatewayFor(transport);

      await expectLater(
        gateway.loginPassword(credentials),
        failureCode(scenario.code),
      );
      expect(transport.requests, hasLength(3));
      await expectLater(
        gateway.submitCaptcha('1234'),
        failureCode(LoginFailureCode.expired),
      );
    });
  }

  test(
    'does not treat generic captcha labels or script strings as a challenge',
    () async {
      final transport = ScriptedAuthTransport([
        (request) => textResponse(request, loginPage()),
        keyResponse,
        (request) => textResponse(request, '${loginPage()}<p>本页面支持验证码。</p>'),
      ]);

      await expectLater(
        gatewayFor(transport).loginPassword(credentials),
        failureCode(LoginFailureCode.protocol),
      );
      expect(transport.requests, hasLength(3));
    },
  );

  test(
    'does not classify ordinary password help as an active rejection',
    () async {
      final transport = ScriptedAuthTransport([
        (request) => textResponse(
          request,
          '${loginPage()}<p>连续密码错误可能导致账号锁定，请确认验证码输入规范。</p>',
        ),
        keyResponse,
        successRedirect,
        accountResponse,
      ]);

      expect(
        await gatewayFor(transport).loginPassword(credentials),
        isA<LoginSuccess>(),
      );
    },
  );

  for (final body in [
    <int>[],
    utf8.encode('<html>登录页面</html>'),
    <int>[1, 2, 3],
  ]) {
    test(
      'reports invalid captcha bytes (${body.length}) and allows refresh',
      () async {
        final transport = ScriptedAuthTransport([
          (request) => textResponse(request, loginPage(visibleCaptcha: true)),
          (request) => AuthHttpResponse(
            uri: request.uri,
            statusCode: 200,
            body: body,
            headers: {
              'content-type': ['image/png'],
            },
          ),
          captchaResponse,
        ]);
        final gateway = gatewayFor(transport);

        await expectLater(
          gateway.loginPassword(credentials),
          failureCode(LoginFailureCode.captcha),
        );
        expect(await gateway.refreshCaptcha(), pngImage);
        expect(
          transport.requests.every((request) => request.method == 'GET'),
          isTrue,
        );
        expect(transport.replacements, hasLength(1));
      },
    );
  }

  test('does not submit an empty captcha', () async {
    final transport = ScriptedAuthTransport([
      (request) => textResponse(request, loginPage(visibleCaptcha: true)),
      captchaResponse,
    ]);
    final gateway = gatewayFor(transport);
    await gateway.loginPassword(credentials);

    await expectLater(
      gateway.submitCaptcha('  '),
      failureCode(LoginFailureCode.captcha),
    );
    expect(transport.requests, hasLength(2));
  });

  test(
    'requires the browser when the page has no standard csrf token',
    () async {
      final transport = ScriptedAuthTransport([
        (request) => textResponse(
          request,
          '<form><input name="yhm"><input name="mm"></form>',
        ),
      ]);

      await expectLater(
        gatewayFor(transport).loginPassword(credentials),
        failureCode(LoginFailureCode.browserRequired),
      );
      expect(transport.requests, hasLength(1));
    },
  );

  test('rejects a cross-origin password form before fetching a key', () async {
    final transport = ScriptedAuthTransport([
      (request) => textResponse(
        request,
        loginPage(action: 'https://sso.other.example/login'),
      ),
    ]);

    await expectLater(
      gatewayFor(transport).loginPassword(credentials),
      failureCode(LoginFailureCode.browserRequired),
    );
    expect(transport.requests, hasLength(1));
  });

  test('refuses to follow a cross-origin GET redirect', () async {
    final transport = ScriptedAuthTransport([
      (request) => textResponse(
        request,
        '',
        status: 302,
        headers: {
          'location': ['https://sso.other.example/login'],
        },
      ),
    ]);

    await expectLater(
      gatewayFor(transport).loginPassword(credentials),
      failureCode(LoginFailureCode.browserRequired),
    );
    expect(transport.requests, hasLength(1));
  });

  test('classifies an account redirect to external SSO as expired without following it', () async {
    final transport = ScriptedAuthTransport([
      (request) => textResponse(
        request,
        '',
        status: 302,
        headers: {
          'location': ['https://sso.other.example/authenticate'],
        },
      ),
    ]);

    await expectLater(
      gatewayFor(transport).verifySession(usernameHint: '20260001'),
      failureCode(LoginFailureCode.expired),
    );
    expect(transport.requests, hasLength(1));
    expect(transport.requests.single.uri.origin, defaultProfile.baseUri.origin);
    expect(transport.cookieReads, isEmpty);
  });

  test('bounds ordinary same-origin GET redirects', () async {
    final transport = ScriptedAuthTransport(
      List<RequestHandler>.generate(
        4,
        (_) =>
            (request) => textResponse(
              request,
              '',
              status: 302,
              headers: {
                'location': ['loop'],
              },
            ),
      ),
    );

    await expectLater(
      gatewayFor(transport).loginPassword(credentials),
      failureCode(LoginFailureCode.protocol),
    );
    expect(transport.requests, hasLength(4));
  });

  test(
    'follows a same-origin GET redirect and resolves the returned form action',
    () async {
      final transport = ScriptedAuthTransport([
        (request) => textResponse(
          request,
          '',
          status: 302,
          headers: {
            'location': ['../auth/page.html'],
          },
        ),
        (request) => textResponse(request, loginPage(action: 'submit.html')),
        keyResponse,
        (request) {
          expect(request.uri.path, '/jwglxt/auth/submit.html');
          return successRedirect(request);
        },
        accountResponse,
      ]);

      expect(
        await gatewayFor(transport).loginPassword(credentials),
        isA<LoginSuccess>(),
      );
    },
  );

  for (final address in [
    'https://one.example/',
    'https://two.example/teaching/system/',
    'https://three.example/login/teaching/',
  ]) {
    test('uses the configured origin and base path: $address', () async {
      final profile = SchoolConnection(
        name: '另一所学校',
        baseUri: Uri.parse(address),
      );
      final transport = ScriptedAuthTransport([
        (request) => textResponse(request, loginPage()),
        keyResponse,
        successRedirect,
        accountResponse,
      ]);

      expect(
        await gatewayFor(
          transport,
          profile: profile,
        ).loginPassword(credentials),
        isA<LoginSuccess>(),
      );
      expect(
        transport.requests.every(
          (request) => request.uri.origin == profile.baseUri.origin,
        ),
        isTrue,
      );
      expect(
        transport.requests[0].uri.path,
        '${profile.baseUri.path}xtgl/login_slogin.html',
      );
      expect(
        transport.requests[3].uri.path,
        '${profile.baseUri.path}xtgl/index_cxYhxxIndex.html',
      );
    });
  }

  test('never follows a POST 307 with the password payload', () async {
    final transport = ScriptedAuthTransport([
      (request) => textResponse(request, loginPage()),
      keyResponse,
      (request) => textResponse(
        request,
        '',
        status: 307,
        headers: {
          'location': ['elsewhere'],
        },
      ),
    ]);

    await expectLater(
      gatewayFor(transport).loginPassword(credentials),
      failureCode(LoginFailureCode.browserRequired),
    );
    expect(transport.requests, hasLength(3));
  });

  test(
    'rejects a 302 login response when account verification redirects to login',
    () async {
      final transport = ScriptedAuthTransport([
        (request) => textResponse(request, loginPage()),
        keyResponse,
        successRedirect,
        (request) => textResponse(
          request,
          '',
          status: 302,
          headers: {
            'location': ['login_slogin.html'],
          },
        ),
      ]);

      await expectLater(
        gatewayFor(transport).loginPassword(credentials),
        failureCode(LoginFailureCode.expired),
      );
      expect(transport.requests, hasLength(4));
    },
  );

  test(
    'rejects a 200 login page even if it also contains a name element',
    () async {
      final transport = ScriptedAuthTransport([
        (request) => textResponse(
          request,
          '${loginPage()}<h4 class="media-heading">学生</h4>',
        ),
      ]);

      await expectLater(
        gatewayFor(transport).verifySession(usernameHint: '20260001'),
        failureCode(LoginFailureCode.expired),
      );
    },
  );

  test('rejects an error page containing identity-like elements', () async {
    final transport = ScriptedAuthTransport([
      (request) => textResponse(
        request,
        '<title>系统错误</title><input name="xm" value="学生"><input name="xh" value="20260001">',
      ),
    ]);

    await expectLater(
      gatewayFor(transport).verifySession(),
      failureCode(LoginFailureCode.protocol),
    );
  });

  test('accepts authenticated identity alongside hidden login templates and password guidance', () async {
    final transport = ScriptedAuthTransport([
      (request) => textResponse(request, '''
        <input name="xm" value="李明"><input name="xh" value="20260002">
        <div hidden><form><input name="yhm"><input name="mm" type="password"></form></div>
        <p>修改密码后请重新登录。</p>
      '''),
    ]);

    final session = await gatewayFor(transport).verifySession();

    expect(session.account.id, '20260002');
    expect(session.account.studentId, '20260002');
    expect(session.account.displayName, '李明');
    expect(transport.cookieReads, [defaultProfile.accountUri]);
  });

  test('rejects an anonymous login form without explicit identity', () async {
    final transport = ScriptedAuthTransport([
      (request) => textResponse(
        request,
        '<form><input name="yhm"><input name="mm" type="password"></form>',
      ),
    ]);

    await expectLater(
      gatewayFor(transport).verifySession(usernameHint: '20260002'),
      failureCode(LoginFailureCode.expired),
    );
    expect(transport.cookieReads, isEmpty);
  });

  test('imports cookies before checking identity and prefers the returned student id', () async {
    final transport = ScriptedAuthTransport([accountResponse]);
    final gateway = gatewayFor(transport);
    const imported = [
      LoginCookie(name: 'JSESSIONID', value: 'manual-test-cookie'),
    ];

    final session = await gateway.importCookies(
      imported,
      usernameHint: 'login-alias',
    );

    expect(transport.replacements.single.cookies, imported);
    expect(session.account.id, '20260001');
    expect(session.account.studentId, '20260001');
    expect(session.account.loginName, 'login-alias');
  });

  test(
    'requires a student id hint for authenticated name-only pages',
    () async {
      AuthHttpResponse nameOnly(AuthHttpRequest request) =>
          textResponse(request, '<h4 class="media-heading">李明 学生</h4>');
      final transport = ScriptedAuthTransport([nameOnly, nameOnly, nameOnly]);
      final gateway = gatewayFor(transport);

      await expectLater(
        gateway.importCookies(transport.availableCookies),
        failureCode(LoginFailureCode.missingIdentity),
      );
      final session = await gateway.verifySession(usernameHint: '20260002');

      expect(session.account.id, '20260002');
      expect(session.account.displayName, '李明');
      expect(session.account.studentId, isNull);
      expect(transport.replacements, hasLength(1));
    },
  );

  test(
    'does not treat a username hint alone as evidence of authentication',
    () async {
      final transport = ScriptedAuthTransport([
        (request) => textResponse(request, '<p>欢迎访问教务系统</p>'),
      ]);

      await expectLater(
        gatewayFor(transport).verifySession(usernameHint: '20260001'),
        failureCode(LoginFailureCode.protocol),
      );
    },
  );

  test('requires usable cookies even when identity was returned', () async {
    final transport = ScriptedAuthTransport([accountResponse])
      ..availableCookies = [];

    await expectLater(
      gatewayFor(transport).verifySession(),
      failureCode(LoginFailureCode.expired),
    );
  });

  test('ignores late login page responses after close', () async {
    final started = Completer<AuthHttpRequest>();
    final response = Completer<AuthHttpResponse>();
    final transport = ScriptedAuthTransport([
      (request) {
        started.complete(request);
        return response.future;
      },
    ]);
    final gateway = gatewayFor(transport);
    final result = gateway.loginPassword(credentials);
    final assertion = expectLater(
      result,
      failureCode(LoginFailureCode.cancelled),
    );
    final request = await started.future;

    gateway.close();
    response.complete(textResponse(request, loginPage()));
    await assertion;

    expect(transport.closed, isTrue);
    expect(transport.requests, hasLength(1));
    await expectLater(
      gateway.submitCaptcha('1234'),
      failureCode(LoginFailureCode.cancelled),
    );
  });

  test(
    'rejects a late cookie read instead of returning a verified session',
    () async {
      final reading = Completer<void>();
      final cookieResult = Completer<List<LoginCookie>>();
      final transport = ScriptedAuthTransport([accountResponse])
        ..cookieReader = (uri) {
          reading.complete();
          return cookieResult.future;
        };
      final gateway = gatewayFor(transport);
      final assertion = expectLater(
        gateway.verifySession(),
        failureCode(LoginFailureCode.cancelled),
      );
      await reading.future;

      gateway.close();
      cookieResult.complete(transport.availableCookies);
      await assertion;
      expect(transport.closed, isTrue);
    },
  );

  test(
    'does not allow simultaneous operations to overwrite an attempt',
    () async {
      final started = Completer<AuthHttpRequest>();
      final response = Completer<AuthHttpResponse>();
      final transport = ScriptedAuthTransport([
        (request) {
          started.complete(request);
          return response.future;
        },
      ]);
      final gateway = gatewayFor(transport);
      final assertion = expectLater(
        gateway.loginPassword(credentials),
        failureCode(LoginFailureCode.cancelled),
      );
      final request = await started.future;

      await expectLater(
        gateway.loginPassword(credentials),
        failureCode(LoginFailureCode.protocol),
      );
      expect(transport.replacements, hasLength(1));
      gateway.close();
      response.complete(textResponse(request, loginPage()));
      await assertion;
    },
  );
}
