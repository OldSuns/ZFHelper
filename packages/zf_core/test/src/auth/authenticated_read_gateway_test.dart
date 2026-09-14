import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:zf_core/src/auth/auth_repository.dart';
import 'package:zf_core/src/auth/login_models.dart';
import 'package:zf_core/src/auth/zhengfang_login_gateway.dart';

import 'auth_state_test_support.dart';
import 'login_test_support.dart';

void main() {
  test(
    'rotated session cookies from a query are saved before restart',
    () async {
      final transport = ScriptedAuthTransport([accountResponse]);
      transport.handlers.add((request) {
        transport.availableCookies = const [
          LoginCookie(name: 'JSESSIONID', value: 'synthetic-rotated-session'),
        ];
        return textResponse(request, '{"kbList":[]}');
      });
      final vault = StateTestVault();
      final repository = AuthRepository(
        gatewayFactory: (_) => gatewayFor(transport),
        vault: vault,
      );
      addTearDown(repository.dispose);
      await repository.signInCookies(
        defaultProfile,
        _cookies,
        method: LoginMethod.web,
      );

      await repository.runRead(
        repository.state.knownIdentity!.scope,
        (client) => client.sendRead(_postQuery),
      );

      expect(
        vault.record!.session.cookies.single.value,
        'synthetic-rotated-session',
      );
      expect(vault.record!.credentials, isNull);
    },
  );

  test('login and a business query share the exact same transport', () async {
    final transport = ScriptedAuthTransport([
      accountResponse,
      (request) => textResponse(request, '{"kbList":[]}'),
    ]);
    var creations = 0;
    final repository = AuthRepository(
      initialProfile: defaultProfile,
      gatewayFactory: (_) {
        creations++;
        return gatewayFor(transport);
      },
      vault: StateTestVault(),
    );
    addTearDown(repository.dispose);
    expect(
      await repository.signInCookies(
        defaultProfile,
        _cookies,
        method: LoginMethod.cookie,
      ),
      isTrue,
    );

    final result = await repository.runRead(
      repository.state.knownIdentity!.scope,
      (client) => client.sendRead(_postQuery),
    );

    expect(result.text, '{"kbList":[]}');
    expect(creations, 1);
    expect(transport.requests.map((request) => request.uri.path), [
      defaultProfile.accountUri.path,
      _postQuery.uri.path,
    ]);
    expect(transport.requests.last.form, _postQuery.form);
    expect(transport.replacements, hasLength(1));
    expect(transport.cookieReads, everyElement(defaultProfile.accountUri));
  });

  test('a read requires a previously verified identity', () async {
    final transport = ScriptedAuthTransport([]);
    final gateway = gatewayFor(transport);
    addTearDown(gateway.close);

    await expectLater(
      gateway.sendRead(_postQuery),
      throwsA(_failure(LoginFailureCode.expired)),
    );
    expect(transport.requests, isEmpty);
  });

  for (final status in [307, 308]) {
    test(
      'an explicitly read-only POST follows same-origin $status with its fields',
      () async {
        final transport = ScriptedAuthTransport([
          accountResponse,
          (request) => textResponse(
            request,
            '',
            status: status,
            headers: {
              'location': ['updated-query.html'],
            },
          ),
          (request) => textResponse(request, '{"kbList":[]}'),
        ]);
        final gateway = await _verified(transport);

        expect((await gateway.sendRead(_postQuery)).text, '{"kbList":[]}');

        final forwarded = transport.requests.last;
        expect(forwarded.method, 'POST');
        expect(forwarded.uri, _postQuery.uri.resolve('updated-query.html'));
        expect(forwarded.form, _postQuery.form);
        expect(forwarded.headers, _postQuery.headers);

        transport.handlers.add(
          (request) => textResponse(
            request,
            '',
            status: status,
            headers: {
              'location': ['updated-submit.html'],
            },
          ),
        );
        final beforeSubmission = transport.requests.length;
        expect((await gateway.sendMutation(_postQuery)).statusCode, status);
        expect(transport.requests.length, beforeSubmission + 1);
      },
    );
  }

  test('a query 303 follows as a GET without replaying its form', () async {
    final transport = ScriptedAuthTransport([
      accountResponse,
      (request) => textResponse(
        request,
        '',
        status: 303,
        headers: {
          'location': ['query-result.html'],
        },
      ),
      (request) => textResponse(request, '{"kbList":[]}'),
    ]);
    final gateway = await _verified(transport);

    await gateway.sendRead(_postQuery);

    expect(transport.requests.last.method, 'GET');
    expect(transport.requests.last.form, isEmpty);
  });

  for (final target in [
    'https://identity.example/sso/login',
    '../xtgl/login_slogin.html',
  ]) {
    test(
      'a session redirect to $target is never followed as business data',
      () async {
        final transport = ScriptedAuthTransport([
          accountResponse,
          (request) => textResponse(
            request,
            '',
            status: 302,
            headers: {
              'location': [target],
            },
          ),
        ]);
        final gateway = await _verified(transport);

        await expectLater(
          gateway.sendRead(_postQuery),
          throwsA(_failure(LoginFailureCode.expired)),
        );
        expect(transport.requests, hasLength(2));
      },
    );
  }

  test(
    'query endpoints cannot send authenticated requests to another origin',
    () async {
      final transport = ScriptedAuthTransport([accountResponse]);
      final gateway = await _verified(transport);

      await expectLater(
        gateway.sendRead(
          AuthHttpRequest.get(Uri.parse('https://other.example/query')),
        ),
        throwsA(_failure(LoginFailureCode.browserRequired)),
      );
      expect(transport.requests, hasLength(1));
    },
  );

  test('an adapter cannot smuggle a response from another origin', () async {
    final transport = ScriptedAuthTransport([
      accountResponse,
      (_) => AuthHttpResponse(
        uri: Uri.parse('https://other.example/query'),
        statusCode: 200,
        body: utf8.encode('untrusted data'),
      ),
    ]);
    final gateway = await _verified(transport);

    await expectLater(
      gateway.sendRead(_postQuery),
      throwsA(_failure(LoginFailureCode.browserRequired)),
    );
  });

  test('HTTP 401 reports session expiration to the owner', () async {
    final transport = ScriptedAuthTransport([
      accountResponse,
      (request) =>
          textResponse(request, 'authentication required', status: 401),
    ]);
    final gateway = await _verified(transport);

    await expectLater(
      gateway.sendRead(_postQuery),
      throwsA(_failure(LoginFailureCode.expired)),
    );
    expect(transport.requests, hasLength(2));
  });

  test(
    'a late expiration cannot revoke a transport already verified again',
    () async {
      final lateResponse = Completer<AuthHttpResponse>();
      final transport = ScriptedAuthTransport([
        accountResponse,
        (request) => textResponse(request, 'expired', status: 401),
        (_) => lateResponse.future,
        accountResponse,
        (request) => textResponse(request, 'first schedule'),
        (request) => textResponse(request, 'second schedule'),
      ]);
      final repository = AuthRepository(
        initialProfile: defaultProfile,
        gatewayFactory: (_) => gatewayFor(transport),
        vault: StateTestVault(),
      );
      addTearDown(repository.dispose);
      await repository.signInCookies(
        defaultProfile,
        _cookies,
        method: LoginMethod.cookie,
      );
      final scope = repository.state.knownIdentity!.scope;
      final first = repository.runRead(
        scope,
        (client) => client.sendRead(_postQuery),
      );
      final second = repository.runRead(
        scope,
        (client) => client.sendRead(_postQuery),
      );

      expect((await first).text, 'first schedule');
      lateResponse.complete(
        textResponse(_postQuery, 'late expiration', status: 401),
      );

      expect((await second).text, 'second schedule');
      expect(repository.state.isSignedIn, isTrue);
      expect(
        transport.requests.where(
          (request) => request.uri.path == defaultProfile.accountUri.path,
        ),
        hasLength(2),
      );
      expect(transport.requests, hasLength(6));
    },
  );

  test(
    'business denial and HTML bodies remain available to the business parser',
    () async {
      final loginHtml = loginPage();
      final transport = ScriptedAuthTransport([
        accountResponse,
        (request) =>
            textResponse(request, 'no timetable permission', status: 403),
        (request) => textResponse(request, loginHtml),
      ]);
      final gateway = await _verified(transport);

      final denied = await gateway.sendRead(_postQuery);
      final html = await gateway.sendRead(_postQuery);

      expect(denied.statusCode, 403);
      expect(denied.text, 'no timetable permission');
      expect(html.text, loginHtml);
    },
  );

  test('business queries use the existing redirect limit', () async {
    AuthHttpResponse redirect(AuthHttpRequest request) => textResponse(
      request,
      '',
      status: 302,
      headers: {
        'location': ['query-again.html'],
      },
    );
    final transport = ScriptedAuthTransport([
      accountResponse,
      redirect,
      redirect,
      redirect,
      redirect,
    ]);
    final gateway = await _verified(transport);

    await expectLater(
      gateway.sendRead(_postQuery),
      throwsA(_failure(LoginFailureCode.protocol)),
    );
    expect(transport.requests, hasLength(5));
  });

  test('closing the owner rejects a late business response', () async {
    final response = Completer<AuthHttpResponse>();
    final transport = ScriptedAuthTransport([
      accountResponse,
      (_) => response.future,
    ]);
    final gateway = await _verified(transport);
    final result = expectLater(
      gateway.sendRead(_postQuery),
      throwsA(_failure(LoginFailureCode.cancelled)),
    );

    gateway.close();
    response.complete(textResponse(_postQuery, '{"kbList":[]}'));
    await result;

    expect(transport.closed, isTrue);
  });

  test(
    'independent queries can run concurrently on the verified transport',
    () async {
      final first = Completer<AuthHttpResponse>();
      final second = Completer<AuthHttpResponse>();
      final transport = ScriptedAuthTransport([
        accountResponse,
        (_) => first.future,
        (_) => second.future,
      ]);
      final gateway = await _verified(transport);
      final requests = Future.wait([
        gateway.sendRead(_postQuery),
        gateway.sendRead(_postQuery),
      ]);

      expect(transport.requests, hasLength(3));
      second.complete(textResponse(_postQuery, 'second'));
      first.complete(textResponse(_postQuery, 'first'));

      expect((await requests).map((response) => response.text), [
        'first',
        'second',
      ]);
    },
  );
}

const _cookies = [
  LoginCookie(name: 'JSESSIONID', value: 'synthetic-query-session'),
];

final _postQuery = AuthHttpRequest.form(
  defaultProfile.baseUri.resolve('kbcx/xskbcx_cxXsKb.html'),
  fields: [const MapEntry('xnm', '2026'), const MapEntry('xqm', '3')],
  headers: {'X-Requested-With': 'XMLHttpRequest'},
);

Future<ZhengfangLoginGateway> _verified(ScriptedAuthTransport transport) async {
  final gateway = gatewayFor(transport);
  addTearDown(gateway.close);
  await gateway.importCookies(_cookies);
  return gateway;
}

Matcher _failure(LoginFailureCode code) =>
    isA<LoginFailure>().having((failure) => failure.code, 'code', code);
