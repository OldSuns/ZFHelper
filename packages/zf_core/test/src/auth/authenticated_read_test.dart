import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zf_core/src/auth/account_scope.dart';
import 'package:zf_core/src/auth/auth_repository.dart';
import 'package:zf_core/src/auth/authenticated_read_client.dart';
import 'package:zf_core/src/auth/login_gateway.dart';
import 'package:zf_core/src/auth/login_models.dart';

import 'auth_state_test_support.dart';

const _expired = LoginFailure(LoginFailureCode.expired, 'synthetic expiration');
const _offline = LoginFailure(LoginFailureCode.network, 'synthetic offline');

void main() {
  test('account keys distinguish schools and stable account identities', () {
    const first = AccountScope(schoolId: 'school-a', accountId: 'student-a');
    final same = AccountScope(
      schoolId: first.schoolId,
      accountId: first.accountId,
    );
    const school = AccountScope(schoolId: 'school-b', accountId: 'student-a');
    const account = AccountScope(schoolId: 'school-a', accountId: 'student-b');

    expect(first, same);
    expect(identical(first, same), isFalse);
    expect(first.hashCode, same.hashCode);
    expect({first, same, school, account}, hasLength(3));
  });

  test('account-bound reads survive selection; mutations never replay and logout revokes identity', () async {
    final late = Completer<AuthHttpResponse>();
    final first = _ReadingGateway()..onRead = (_) => late.future;
    first.login.onPassword = (_) => LoginSuccess(stateTestSession());
    final second = _ReadingGateway();
    second.login.onPassword = (_) =>
        LoginSuccess(stateTestSession(id: 'student-b'));
    final repository = _repository([first, second]);
    await _signIn(repository);
    final identity = repository.state.knownIdentity!;
    final reading = repository.runAccountRead(
      identity,
      (client) => client.sendRead(_query),
    );

    await _signIn(repository);
    expect(repository.isCurrentIdentity(identity), isFalse);
    expect(repository.isAccountIdentityCurrent(identity), isTrue);
    expect(first.login.closed, isFalse);
    late.complete(_response('original account'));
    expect((await reading).text, 'original account');
    expect(await repository.selectAccount(identity.scope), isTrue);
    expect(repository.state.knownIdentity!.generation, identity.generation);

    first.onRead = (_) => throw _expired;
    final before = first.requests.length;
    await expectLater(
      repository.runAccountMutation(
        identity,
        (client) => client.sendRead(_query),
      ),
      throwsA(_failure(LoginFailureCode.expired)),
    );
    expect(first.requests.length, before + 1);
    expect(first.login.verificationCalls, isEmpty);
    expect(first.login.passwordCalls, hasLength(1));
    expect(await repository.signOutAccount(identity.scope), isTrue);
    expect(repository.isAccountIdentityCurrent(identity), isFalse);
    expect(repository.state.accounts, hasLength(2));
    expect(await repository.removeAccount(identity.scope), isTrue);
    expect(repository.state.accounts, hasLength(1));
  });

  test(
    'verified reads reuse the current gateway without another identity check',
    () async {
      final gateway = _ReadingGateway()
        ..onRead = (_) => _response('school schedule');
      gateway.login.onPassword = (_) => LoginSuccess(stateTestSession());
      final repository = _repository([gateway]);
      await _signIn(repository);
      final identity = repository.state.knownIdentity!;

      expect(await _read(repository, identity.scope), 'school schedule');
      expect(gateway.requests.single.method, 'POST');
      expect(gateway.requests.single.form.single.value, '2026');
      expect(gateway.login.passwordCalls, hasLength(1));
      expect(gateway.login.verificationCalls, isEmpty);
      expect(repository.isCurrentIdentity(identity), isTrue);
    },
  );

  test(
    'an adapter without the read capability fails before running a query',
    () async {
      final gateway = StateTestGateway()
        ..onPassword = (_) => LoginSuccess(stateTestSession());
      final repository = _repository([gateway]);
      await _signIn(repository);

      await expectLater(
        _read(repository, repository.state.knownIdentity!.scope),
        throwsA(_failure(LoginFailureCode.protocol)),
      );
      expect(gateway.verificationCalls, isEmpty);
    },
  );

  test('another school or account cannot use the current session', () async {
    final gateway = _ReadingGateway();
    gateway.login.onPassword = (_) => LoginSuccess(stateTestSession());
    final repository = _repository([gateway]);
    await _signIn(repository);
    final scope = repository.state.knownIdentity!.scope;

    for (final other in [
      AccountScope(schoolId: 'another-school', accountId: scope.accountId),
      AccountScope(schoolId: scope.schoolId, accountId: 'another-account'),
    ]) {
      await expectLater(
        _read(repository, other),
        throwsA(_failure(LoginFailureCode.cancelled)),
      );
    }
    expect(gateway.requests, isEmpty);
  });

  test(
    'concurrent expired POST queries share one renewal and retain identity',
    () async {
      final verificationStarted = Completer<void>();
      final expiredReads = Completer<AuthHttpResponse>();
      final verification = Completer<LoginSession>();
      final active = _ReadingGateway()..onRead = (_) => expiredReads.future;
      active.login.onPassword = (_) => LoginSuccess(stateTestSession());
      active.login.onVerify = (_) {
        verificationStarted.complete();
        return verification.future;
      };
      final renewed = _ReadingGateway()..onRead = (_) => _response('renewed');
      renewed.login.onPassword = (_) => LoginSuccess(stateTestSession());
      final repository = _repository([active, renewed]);
      await _signIn(repository);
      final identity = repository.state.knownIdentity!;
      final reads = List.generate(3, (_) => _read(repository, identity.scope));
      final allReads = Future.wait(reads);

      expiredReads.completeError(_expired);
      await verificationStarted.future;
      expect(active.login.verificationCalls, ['student-a']);
      verification.completeError(_expired);

      expect(await allReads, ['renewed', 'renewed', 'renewed']);
      expect(active.requests, hasLength(3));
      expect(renewed.requests, hasLength(3));
      expect(renewed.login.passwordCalls, hasLength(1));
      expect(active.login.closed, isTrue);
      expect(repository.isCurrentIdentity(identity), isTrue);
    },
  );

  test(
    'reads cancelled by renewal and new reads join the same active renewal',
    () async {
      final loginStarted = Completer<void>();
      final renewing = Completer<LoginStep>();
      final lateRead = Completer<AuthHttpResponse>();
      var readCount = 0;
      final active = _ReadingGateway()
        ..onRead = (_) {
          if (++readCount == 1) throw _expired;
          return lateRead.future;
        };
      active.login.onPassword = (_) => LoginSuccess(stateTestSession());
      active.login.onVerify = (_) => throw _expired;
      final renewed = _ReadingGateway()..onRead = (_) => _response('renewed');
      renewed.login.onPassword = (_) {
        loginStarted.complete();
        return renewing.future;
      };
      final repository = _repository([active, renewed]);
      await _signIn(repository);
      final scope = repository.state.knownIdentity!.scope;
      final first = _read(repository, scope);
      final second = _read(repository, scope);
      await loginStarted.future;
      final third = _read(repository, scope);
      final allReads = Future.wait([first, second, third]);

      lateRead.completeError(
        const LoginFailure(LoginFailureCode.cancelled, 'old transport closed'),
      );
      renewing.complete(LoginSuccess(stateTestSession()));

      expect(await allReads, ['renewed', 'renewed', 'renewed']);
      expect(renewed.login.passwordCalls, hasLength(1));
      expect(renewed.requests, hasLength(3));
    },
  );

  test(
    'a read can retry after verification refreshes the same gateway',
    () async {
      var count = 0;
      final gateway = _ReadingGateway()
        ..onRead = (_) {
          if (++count == 1) throw _expired;
          return _response();
        };
      gateway.login.onPassword = (_) => LoginSuccess(stateTestSession());
      gateway.login.onVerify = (_) => stateTestSession(displayName: '已更新姓名');
      final repository = _repository([gateway]);
      await _signIn(repository);
      final identity = repository.state.knownIdentity!;

      expect(await _read(repository, identity.scope), 'schedule');
      expect(gateway.login.verificationCalls, ['student-a']);
      expect(gateway.login.passwordCalls, hasLength(1));
      expect(repository.state.account?.displayName, '已更新姓名');
      expect(repository.isCurrentIdentity(identity), isTrue);
    },
  );

  test('network failures are reported without replaying a query', () async {
    final gateway = _ReadingGateway()..onRead = (_) => throw _offline;
    gateway.login.onPassword = (_) => LoginSuccess(stateTestSession());
    final repository = _repository([gateway]);
    await _signIn(repository);

    await expectLater(
      _read(repository, repository.state.knownIdentity!.scope),
      throwsA(same(_offline)),
    );
    expect(gateway.requests, hasLength(1));
    expect(gateway.login.verificationCalls, isEmpty);
    expect(repository.state.isSignedIn, isTrue);
  });

  test(
    'a late expiration reuses verification already completed for its session',
    () async {
      final late = Completer<AuthHttpResponse>();
      var readCount = 0;
      final gateway = _ReadingGateway()
        ..onRead = (_) {
          readCount++;
          if (readCount == 1) throw _expired;
          if (readCount == 2) return late.future;
          return _response('verified');
        };
      gateway.login.onPassword = (_) => LoginSuccess(stateTestSession());
      gateway.login.onVerify = (_) => stateTestSession();
      final repository = _repository([gateway]);
      await _signIn(repository);
      final scope = repository.state.knownIdentity!.scope;
      final first = _read(repository, scope);
      final second = _read(repository, scope);

      expect(await first, 'verified');
      late.completeError(_expired);

      expect(await second, 'verified');
      expect(gateway.login.verificationCalls, ['student-a']);
    },
  );

  test(
    'a second expiration stops retrying and keeps only the local identity',
    () async {
      final active = _ReadingGateway()..onRead = (_) => throw _expired;
      active.login.onPassword = (_) => LoginSuccess(stateTestSession());
      active.login.onVerify = (_) => throw _expired;
      final renewed = _ReadingGateway()..onRead = (_) => throw _expired;
      renewed.login.onPassword = (_) => LoginSuccess(stateTestSession());
      final repository = _repository([active, renewed]);
      await _signIn(repository);
      final identity = repository.state.knownIdentity!;

      await expectLater(
        _read(repository, identity.scope),
        throwsA(_failure(LoginFailureCode.expired)),
      );
      expect(active.requests, hasLength(1));
      expect(renewed.requests, hasLength(1));
      expect(renewed.login.closed, isTrue);
      expect(repository.state.isSignedIn, isFalse);
      expect(repository.isCurrentIdentity(identity), isTrue);
    },
  );

  test(
    'expiration does not invent credentials for an unremembered login',
    () async {
      final gateway = _ReadingGateway()..onRead = (_) => throw _expired;
      gateway.login.onPassword = (_) => LoginSuccess(stateTestSession());
      gateway.login.onVerify = (_) => throw _expired;
      final repository = _repository([gateway]);
      await _signIn(repository, rememberPassword: false);
      final identity = repository.state.knownIdentity!;

      await expectLater(
        _read(repository, identity.scope),
        throwsA(_failure(LoginFailureCode.expired)),
      );
      expect(gateway.login.passwordCalls, hasLength(1));
      expect(repository.state.isSignedIn, isFalse);
      expect(repository.isCurrentIdentity(identity), isTrue);
    },
  );

  test(
    'a renewal captcha stays visible and is not converted into query success',
    () async {
      final active = _ReadingGateway()..onRead = (_) => throw _expired;
      active.login.onPassword = (_) => LoginSuccess(stateTestSession());
      active.login.onVerify = (_) => throw _expired;
      final renewed = _ReadingGateway();
      renewed.login.onPassword = (_) => CaptchaRequired(image: [1, 2, 3]);
      renewed.login.onCaptcha = (_) => LoginSuccess(stateTestSession());
      final repository = _repository([active, renewed]);
      await _signIn(repository);
      final identity = repository.state.knownIdentity!;

      await expectLater(
        _read(repository, identity.scope),
        throwsA(_failure(LoginFailureCode.captcha)),
      );
      expect(repository.state.phase, AuthPhase.captcha);
      expect(repository.state.challenge?.image, [1, 2, 3]);
      expect(renewed.requests, isEmpty);
      expect(await repository.submitCaptcha('1234'), isTrue);
      expect(repository.isCurrentIdentity(identity), isTrue);
    },
  );

  for (final sameAccount in [false, true]) {
    test(
      'successful manual login cancels a late query, same account: $sameAccount',
      () async {
        final late = Completer<AuthHttpResponse>();
        final active = _ReadingGateway()..onRead = (_) => late.future;
        active.login.onPassword = (_) => LoginSuccess(stateTestSession());
        final next = _ReadingGateway();
        next.login.onPassword = (_) => LoginSuccess(
          stateTestSession(id: sameAccount ? 'student-a' : 'student-b'),
        );
        final repository = _repository([active, next]);
        await _signIn(repository);
        final identity = repository.state.knownIdentity!;
        final result = expectLater(
          _read(repository, identity.scope),
          throwsA(_failure(LoginFailureCode.cancelled)),
        );

        await _signIn(repository);
        late.complete(_response('old data'));
        await result;

        expect(repository.isCurrentIdentity(identity), isFalse);
        expect(
          repository.state.knownIdentity!.generation,
          isNot(identity.generation),
        );
      },
    );
  }

  test(
    'a failed account switch preserves the previous read and identity',
    () async {
      final late = Completer<AuthHttpResponse>();
      final active = _ReadingGateway()..onRead = (_) => late.future;
      active.login.onPassword = (_) => LoginSuccess(stateTestSession());
      final rejected = StateTestGateway()
        ..onPassword = (_) => throw const LoginFailure(
          LoginFailureCode.invalidCredentials,
          'synthetic rejection',
        );
      final repository = _repository([active, rejected]);
      await _signIn(repository);
      final identity = repository.state.knownIdentity!;
      final result = _read(repository, identity.scope);

      expect(
        await repository.signInPassword(
          stateTestOtherProfile,
          LoginCredentials(username: 'student-b', password: 'synthetic'),
          rememberPassword: true,
        ),
        isFalse,
      );
      late.complete(_response('still current'));

      expect(await result, 'still current');
      expect(repository.isCurrentIdentity(identity), isTrue);
    },
  );

  test(
    'sign out clears local identity and a late error cannot revive it',
    () async {
      final late = Completer<AuthHttpResponse>();
      final gateway = _ReadingGateway()..onRead = (_) => late.future;
      gateway.login.onPassword = (_) => LoginSuccess(stateTestSession());
      final vault = StateTestVault();
      final repository = _repository([gateway], vault: vault);
      await _signIn(repository);
      final identity = repository.state.knownIdentity!;
      final result = expectLater(
        _read(repository, identity.scope),
        throwsA(_failure(LoginFailureCode.cancelled)),
      );

      await repository.signOut();
      late.completeError(_offline);
      await result;

      expect(repository.state.knownIdentity, isNull);
      expect(repository.isCurrentIdentity(identity), isFalse);
      expect(vault.record, isNull);
      expect(gateway.login.verificationCalls, isEmpty);
    },
  );

  test('the read client cannot escape the owning operation', () async {
    final gateway = _ReadingGateway();
    gateway.login.onPassword = (_) => LoginSuccess(stateTestSession());
    final repository = _repository([gateway]);
    await _signIn(repository);
    late AuthenticatedReadClient retained;
    await repository.runRead(repository.state.knownIdentity!.scope, (
      client,
    ) async {
      retained = client;
    });

    await expectLater(
      retained.sendRead(_query),
      throwsA(_failure(LoginFailureCode.cancelled)),
    );
    expect(gateway.requests, isEmpty);
  });

  test(
    'a business parser failure after sign out is discarded with its old scope',
    () async {
      final parsing = Completer<void>();
      final releaseParser = Completer<void>();
      final gateway = _ReadingGateway()..onRead = (_) => _response();
      gateway.login.onPassword = (_) => LoginSuccess(stateTestSession());
      final repository = _repository([gateway]);
      await _signIn(repository);
      final identity = repository.state.knownIdentity!;
      final result = expectLater(
        repository.runRead(identity.scope, (client) async {
          await client.sendRead(_query);
          parsing.complete();
          await releaseParser.future;
          throw const FormatException('synthetic business parser failure');
        }),
        throwsA(_failure(LoginFailureCode.cancelled)),
      );
      await parsing.future;

      await repository.signOut();
      releaseParser.complete();
      await result;

      expect(repository.state.knownIdentity, isNull);
      expect(repository.state.failure, isNull);
    },
  );

  test('offline restoration exposes the stored identity before online verification', () async {
    final importing = Completer<void>();
    final response = Completer<LoginSession>();
    final gateway = StateTestGateway()
      ..onImportCookies = (_, _) {
        importing.complete();
        return response.future;
      };
    final vault = StateTestVault(record: stateTestStored());
    final repository = _repository([gateway], vault: vault);
    final restoring = repository.restore();
    await importing.future;
    final identity = repository.state.knownIdentity!;

    expect(identity.account.id, 'student-a');
    expect(identity.profile.school.id, stateTestProfile.school.id);
    expect(repository.state.account, isNull);
    expect(repository.state.isSignedIn, isFalse);
    response.completeError(_offline);
    await restoring;

    expect(repository.isCurrentIdentity(identity), isTrue);
    expect(repository.state.failure, same(_offline));
    expect(repository.state.isSignedIn, isFalse);
    expect(vault.writes, isEmpty);
    await expectLater(
      _read(repository, identity.scope),
      throwsA(same(_offline)),
    );
  });

  test('retrying restore after offline failure retains the local identity generation', () async {
    final offline = StateTestGateway()
      ..onImportCookies = (_, _) => throw _offline;
    final online = StateTestGateway()
      ..onImportCookies = (_, _) => stateTestSession();
    final repository = _repository([
      offline,
      online,
    ], vault: StateTestVault(record: stateTestStored()));
    await repository.restore();
    final identity = repository.state.knownIdentity!;

    await repository.restore();

    expect(repository.state.isSignedIn, isTrue);
    expect(repository.isCurrentIdentity(identity), isTrue);
  });
}

AuthRepository _repository(
  List<LoginGateway> gateways, {
  StateTestVault? vault,
}) {
  var next = 0;
  final repository = AuthRepository(
    initialProfile: stateTestProfile,
    gatewayFactory: (_) {
      if (next >= gateways.length) {
        throw StateError('Unexpected gateway creation.');
      }
      return gateways[next++];
    },
    vault: vault ?? StateTestVault(),
  );
  addTearDown(repository.dispose);
  return repository;
}

Future<void> _signIn(
  AuthRepository repository, {
  bool rememberPassword = true,
}) async {
  expect(
    await repository.signInPassword(
      stateTestProfile,
      stateTestCredentials,
      rememberPassword: rememberPassword,
    ),
    isTrue,
  );
}

final _query = AuthHttpRequest.form(
  stateTestProfile.baseUri.resolve('kbcx/xskbcx_cxXsKb.html'),
  fields: [const MapEntry('xnm', '2026')],
);

Future<String> _read(AuthRepository repository, AccountScope scope) =>
    repository.runRead(
      scope,
      (client) async => (await client.sendRead(_query)).text,
    );

AuthHttpResponse _response([String body = 'schedule']) =>
    AuthHttpResponse(uri: _query.uri, statusCode: 200, body: utf8.encode(body));

Matcher _failure(LoginFailureCode code) =>
    isA<LoginFailure>().having((failure) => failure.code, 'code', code);

final class _ReadingGateway
    implements
        LoginGateway,
        AuthenticatedReadClient,
        AuthenticatedMutationClient {
  final login = StateTestGateway();
  final requests = <AuthHttpRequest>[];
  FutureOr<AuthHttpResponse> Function(AuthHttpRequest)? onRead;

  @override
  Future<AuthHttpResponse> sendRead(AuthHttpRequest request) async {
    requests.add(request);
    final handler = onRead;
    if (handler == null) throw StateError('Unexpected authenticated read.');
    return handler(request);
  }

  @override
  Future<AuthHttpResponse> sendMutation(AuthHttpRequest request) =>
      sendRead(request);

  @override
  Future<LoginStep> loginPassword(LoginCredentials credentials) =>
      login.loginPassword(credentials);

  @override
  Future<LoginStep> submitCaptcha(String captcha) =>
      login.submitCaptcha(captcha);

  @override
  Future<Uint8List> refreshCaptcha() => login.refreshCaptcha();

  @override
  Future<LoginSession> importCookies(
    List<LoginCookie> cookies, {
    String usernameHint = '',
  }) => login.importCookies(cookies, usernameHint: usernameHint);

  @override
  Future<LoginSession> verifySession({String usernameHint = ''}) =>
      login.verifySession(usernameHint: usernameHint);

  @override
  Future<List<LoginCookie>> exportCookies() => login.exportCookies();

  @override
  void close() => login.close();
}
