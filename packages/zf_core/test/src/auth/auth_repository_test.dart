import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zf_core/src/auth/auth_repository.dart';
import 'package:zf_core/src/auth/login_models.dart';

import 'auth_state_test_support.dart';

void main() {
  AuthRepository repositoryFor(
    StateTestGatewayFactory factory,
    StateTestVault vault,
  ) {
    final repository = AuthRepository(
      initialProfile: stateTestProfile,
      gatewayFactory: factory.call,
      vault: vault,
    );
    addTearDown(repository.dispose);
    return repository;
  }

  for (final rememberPassword in [true, false]) {
    test(
      'login always persists its session; saving password is $rememberPassword',
      () async {
        final response = Completer<LoginStep>();
        final gateway = StateTestGateway()..onPassword = (_) => response.future;
        final vault = StateTestVault(
          record: stateTestStored(credentials: stateTestCredentials),
        );
        final repository = repositoryFor(
          StateTestGatewayFactory([gateway]),
          vault,
        );

        final signingIn = repository.signInPassword(
          stateTestProfile,
          stateTestCredentials,
          rememberPassword: rememberPassword,
        );
        expect(repository.state.isSignedIn, isFalse);
        expect(repository.state.isBusy, isTrue);
        expect(vault.writes, isEmpty);
        response.complete(LoginSuccess(stateTestSession()));

        expect(await signingIn, isTrue);
        expect(repository.state.account?.id, 'student-a');
        expect(repository.state.phase, AuthPhase.idle);
        expect(repository.state.remembered, isTrue);
        expect(repository.state.failure, isNull);
        expect(vault.writes, hasLength(1));
        expect(vault.record?.method, LoginMethod.password);
        if (rememberPassword) {
          expect(vault.record?.credentials?.password, '  synthetic password  ');
        } else {
          expect(vault.record?.credentials, isNull);
        }
        expect(vault.clearCalls, 0);
      },
    );
  }

  for (final method in [LoginMethod.cookie, LoginMethod.web]) {
    test(
      '${method.name} login does not inherit a previous account password',
      () async {
        final first = StateTestGateway()
          ..onPassword = (_) => LoginSuccess(stateTestSession());
        final secondSession = stateTestSession(
          id: 'student-b',
          displayName: '测试乙',
        );
        final second = StateTestGateway()
          ..onImportCookies = (_, _) => secondSession;
        final vault = StateTestVault();
        final repository = repositoryFor(
          StateTestGatewayFactory([first, second]),
          vault,
        );
        await repository.signInPassword(
          stateTestProfile,
          stateTestCredentials,
          rememberPassword: true,
        );

        expect(
          await repository.signInCookies(
            stateTestOtherProfile,
            secondSession.cookies,
            method: method,
            usernameHint: 'student-b',
          ),
          isTrue,
        );

        expect(vault.record?.method, method);
        expect(vault.record?.credentials, isNull);
        expect(vault.record?.session.account.id, 'student-b');
        expect(
          repository.state.profile!.baseUri,
          stateTestOtherProfile.baseUri,
        );
        expect(first.closed, isFalse);
        expect(repository.state.accounts, hasLength(2));
        expect(second.passwordCalls, isEmpty);
      },
    );
  }

  test(
    'a failed new login keeps the existing verified account and saved record',
    () async {
      final activeGateway = StateTestGateway()
        ..onPassword = (_) => LoginSuccess(stateTestSession());
      final rejectedGateway = StateTestGateway()
        ..onPassword = (_) => throw const LoginFailure(
          LoginFailureCode.invalidCredentials,
          'synthetic rejection',
        );
      final vault = StateTestVault();
      final repository = repositoryFor(
        StateTestGatewayFactory([activeGateway, rejectedGateway]),
        vault,
      );
      await repository.signInPassword(
        stateTestProfile,
        stateTestCredentials,
        rememberPassword: true,
      );
      final stored = vault.record;

      expect(
        await repository.signInPassword(
          stateTestOtherProfile,
          LoginCredentials(username: 'student-b', password: 'synthetic-b'),
          rememberPassword: true,
        ),
        isFalse,
      );

      expect(repository.state.account?.id, 'student-a');
      expect(repository.state.profile!.baseUri, stateTestProfile.baseUri);
      expect(
        repository.state.failure?.code,
        LoginFailureCode.invalidCredentials,
      );
      expect(repository.state.remembered, isTrue);
      expect(vault.record, same(stored));
      expect(activeGateway.closed, isFalse);
      expect(rejectedGateway.closed, isTrue);
    },
  );

  test(
    'keeps captcha attempts in one gateway and saves only after verification',
    () async {
      final gateway = StateTestGateway()
        ..onPassword = ((_) => CaptchaRequired(image: [1, 2]))
        ..onRefreshCaptcha = (() => Uint8List.fromList([3, 4]))
        ..onCaptcha = (value) => value == 'correct'
            ? LoginSuccess(stateTestSession())
            : CaptchaRequired(image: [5, 6], rejected: true);
      final factory = StateTestGatewayFactory([gateway]);
      final vault = StateTestVault();
      final repository = repositoryFor(factory, vault);

      expect(
        await repository.signInPassword(
          stateTestProfile,
          stateTestCredentials,
          rememberPassword: true,
        ),
        isFalse,
      );
      expect(repository.state.phase, AuthPhase.captcha);
      expect(repository.state.pendingUsername, 'student-a');
      expect(repository.state.isSignedIn, isFalse);
      expect(vault.writes, isEmpty);
      await repository.refreshCaptcha();
      expect(repository.state.challenge?.image, [3, 4]);
      expect(await repository.submitCaptcha('wrong'), isFalse);
      expect(repository.state.challenge?.rejected, isTrue);
      expect(await repository.submitCaptcha(' correct '), isTrue);

      expect(gateway.captchaCalls, ['wrong', 'correct']);
      expect(factory.profiles, hasLength(1));
      expect(vault.writes, hasLength(1));
      expect(repository.state.challenge, isNull);
      expect(repository.state.account?.id, 'student-a');
    },
  );

  test('cancelling a login rejects its late success response', () async {
    final response = Completer<LoginStep>();
    final gateway = StateTestGateway()..onPassword = (_) => response.future;
    final vault = StateTestVault();
    final repository = repositoryFor(StateTestGatewayFactory([gateway]), vault);
    final signingIn = repository.signInPassword(
      stateTestProfile,
      stateTestCredentials,
      rememberPassword: true,
    );

    repository.cancelSignIn();
    response.complete(LoginSuccess(stateTestSession()));

    expect(await signingIn, isFalse);
    expect(gateway.closed, isTrue);
    expect(repository.state.isSignedIn, isFalse);
    expect(repository.state.phase, AuthPhase.idle);
    expect(vault.writes, isEmpty);
  });

  test('a superseded login cannot replace a newer verified account', () async {
    final lateResponse = Completer<LoginStep>();
    final first = StateTestGateway()..onPassword = (_) => lateResponse.future;
    final second = StateTestGateway()
      ..onPassword = (_) => LoginSuccess(stateTestSession(id: 'student-b'));
    final vault = StateTestVault();
    final repository = repositoryFor(
      StateTestGatewayFactory([first, second]),
      vault,
    );
    final oldLogin = repository.signInPassword(
      stateTestProfile,
      stateTestCredentials,
      rememberPassword: true,
    );

    expect(
      await repository.signInPassword(
        stateTestOtherProfile,
        LoginCredentials(username: 'student-b', password: 'synthetic-b'),
        rememberPassword: true,
      ),
      isTrue,
    );
    lateResponse.complete(LoginSuccess(stateTestSession()));

    expect(await oldLogin, isFalse);
    expect(first.closed, isTrue);
    expect(repository.state.account?.id, 'student-b');
    expect(vault.writes.map((login) => login.session.account.id), [
      'student-b',
    ]);
  });

  test('a vault write failure leaves the verified login valid and reports storage failure', () async {
    final gateway = StateTestGateway()
      ..onPassword = (_) => LoginSuccess(stateTestSession());
    final vault = StateTestVault()
      ..beforeWrite = (_) => throw const LoginFailure(
        LoginFailureCode.storage,
        'synthetic vault failure',
      );
    final repository = repositoryFor(StateTestGatewayFactory([gateway]), vault);

    expect(
      await repository.signInPassword(
        stateTestProfile,
        stateTestCredentials,
        rememberPassword: true,
      ),
      isTrue,
    );

    expect(repository.state.isSignedIn, isTrue);
    expect(repository.state.phase, AuthPhase.idle);
    expect(repository.state.remembered, isFalse);
    expect(repository.state.failure, isNull);
    expect(repository.state.storageFailure?.code, LoginFailureCode.storage);
  });

  test('sign out is serialized after an in-flight save and cannot resurrect the account', () async {
    final writing = Completer<void>();
    final releaseWrite = Completer<void>();
    final gateway = StateTestGateway()
      ..onPassword = (_) => LoginSuccess(stateTestSession());
    final vault = StateTestVault()
      ..beforeWrite = (_) {
        writing.complete();
        return releaseWrite.future;
      };
    final repository = repositoryFor(StateTestGatewayFactory([gateway]), vault);
    final signingIn = repository.signInPassword(
      stateTestProfile,
      stateTestCredentials,
      rememberPassword: true,
    );
    await writing.future;
    expect(repository.state.isSignedIn, isTrue);
    final afterSignOut = <AuthSnapshot>[];
    final subscription = repository.changes.listen(afterSignOut.add);
    addTearDown(subscription.cancel);

    final signingOut = repository.signOut();
    expect(repository.state.isSignedIn, isFalse);
    expect(vault.clearCalls, 0);
    releaseWrite.complete();

    expect(await signingIn, isFalse);
    await signingOut;
    expect(vault.events, [
      'read:start',
      'read:complete',
      'write:start',
      'write:complete',
      'clear:start',
      'clear:complete',
    ]);
    expect(vault.record, isNull);
    expect(repository.state.remembered, isFalse);
    expect(afterSignOut.every((state) => !state.isSignedIn), isTrue);
    expect(gateway.closed, isTrue);
  });

  test('sign out invalidates a pending network login before clearing saved credentials', () async {
    final response = Completer<LoginStep>();
    final gateway = StateTestGateway()..onPassword = (_) => response.future;
    final vault = StateTestVault(
      record: stateTestStored(credentials: stateTestCredentials),
    );
    final repository = repositoryFor(StateTestGatewayFactory([gateway]), vault);
    final signingIn = repository.signInPassword(
      stateTestProfile,
      stateTestCredentials,
      rememberPassword: true,
    );

    await repository.signOut();
    response.complete(LoginSuccess(stateTestSession()));

    expect(await signingIn, isFalse);
    expect(repository.state.isSignedIn, isFalse);
    expect(vault.record, isNull);
    expect(vault.writes, isEmpty);
  });

  test(
    'restore of an empty vault remains signed out without creating a gateway',
    () async {
      final vault = StateTestVault();
      final factory = StateTestGatewayFactory([]);
      final repository = repositoryFor(factory, vault);

      await repository.restore();

      expect(vault.readCalls, 1);
      expect(factory.profiles, isEmpty);
      expect(repository.state.isSignedIn, isFalse);
      expect(repository.state.phase, AuthPhase.idle);
      expect(repository.state.failure, isNull);
      expect(repository.state.storageFailure, isNull);
    },
  );

  test(
    'restore reports a vault read failure without inventing a session',
    () async {
      final vault = StateTestVault()
        ..onRead = () => throw const LoginFailure(
          LoginFailureCode.storage,
          'synthetic read failure',
        );
      final factory = StateTestGatewayFactory([]);
      final repository = repositoryFor(factory, vault);

      await repository.restore();

      expect(repository.state.isSignedIn, isFalse);
      expect(repository.state.phase, AuthPhase.idle);
      expect(repository.state.storageFailure?.code, LoginFailureCode.storage);
      expect(repository.state.failure, isNull);
      expect(factory.profiles, isEmpty);
    },
  );

  test(
    'restore verifies cached cookies before exposing or persisting the account',
    () async {
      final importing = Completer<void>();
      final response = Completer<LoginSession>();
      final stored = stateTestStored(
        profile: stateTestOtherProfile,
        method: LoginMethod.cookie,
      );
      final refreshed = stateTestSession(
        verifiedAt: stateTestTime.add(const Duration(minutes: 3)),
      );
      final gateway = StateTestGateway()
        ..onImportCookies = (_, _) {
          importing.complete();
          return response.future;
        };
      final factory = StateTestGatewayFactory([gateway]);
      final vault = StateTestVault(record: stored);
      final repository = repositoryFor(factory, vault);
      final restoring = repository.restore();
      await importing.future;

      expect(repository.state.isSignedIn, isFalse);
      expect(vault.writes, isEmpty);
      response.complete(refreshed);
      await restoring;

      expect(factory.profiles.single.baseUri, stateTestOtherProfile.baseUri);
      expect(gateway.importCalls.single.hint, stored.session.account.loginName);
      expect(gateway.importCalls.single.cookies, stored.session.cookies);
      expect(gateway.passwordCalls, isEmpty);
      expect(repository.state.account?.id, 'student-a');
      expect(repository.state.remembered, isTrue);
      expect(vault.record?.session.verifiedAt, refreshed.verifiedAt);
    },
  );

  test(
    'restore renews expired cookies with explicitly remembered credentials',
    () async {
      final gateway = StateTestGateway()
        ..onImportCookies = ((_, _) => throw const LoginFailure(
          LoginFailureCode.expired,
          'synthetic expired session',
        ))
        ..onPassword = (_) => LoginSuccess(stateTestSession());
      final vault = StateTestVault(
        record: stateTestStored(credentials: stateTestCredentials),
      );
      final repository = repositoryFor(
        StateTestGatewayFactory([gateway]),
        vault,
      );

      await repository.restore();

      expect(gateway.importCalls, hasLength(1));
      expect(gateway.passwordCalls.single.password, '  synthetic password  ');
      expect(repository.state.isSignedIn, isTrue);
      expect(repository.state.remembered, isTrue);
      expect(repository.state.failure, isNull);
      expect(vault.writes, hasLength(1));
    },
  );

  test(
    'restore of an expired cookie-only record never pretends to be logged in',
    () async {
      final gateway = StateTestGateway()
        ..onImportCookies = (_, _) => throw const LoginFailure(
          LoginFailureCode.expired,
          'synthetic expired session',
        );
      final vault = StateTestVault(
        record: stateTestStored(method: LoginMethod.cookie),
      );
      final repository = repositoryFor(
        StateTestGatewayFactory([gateway]),
        vault,
      );

      await repository.restore();

      expect(repository.state.isSignedIn, isFalse);
      expect(repository.state.failure?.code, LoginFailureCode.expired);
      expect(repository.state.remembered, isTrue);
      expect(repository.state.canRestoreSession, isFalse);
      expect(gateway.passwordCalls, isEmpty);
      expect(gateway.closed, isTrue);
      expect(vault.writes, isEmpty);
    },
  );

  test(
    'password renewal during restore exposes a real captcha challenge',
    () async {
      final gateway = StateTestGateway()
        ..onImportCookies = ((_, _) => throw const LoginFailure(
          LoginFailureCode.expired,
          'synthetic expired session',
        ))
        ..onPassword = ((_) => CaptchaRequired(image: [1, 2]))
        ..onCaptcha = (_) => LoginSuccess(stateTestSession());
      final vault = StateTestVault(
        record: stateTestStored(credentials: stateTestCredentials),
      );
      final repository = repositoryFor(
        StateTestGatewayFactory([gateway]),
        vault,
      );

      await repository.restore();
      expect(repository.state.phase, AuthPhase.captcha);
      expect(repository.state.isSignedIn, isFalse);
      expect(repository.state.pendingUsername, 'student-a');
      expect(vault.writes, isEmpty);
      expect(await repository.submitCaptcha('1234'), isTrue);
      expect(repository.state.remembered, isTrue);
    },
  );

  test(
    'cancelling restore rejects a late vault read before creating a gateway',
    () async {
      final reading = Completer<void>();
      final response = Completer<StoredLogin?>();
      final vault = StateTestVault()
        ..onRead = () {
          reading.complete();
          return response.future;
        };
      final factory = StateTestGatewayFactory([]);
      final repository = repositoryFor(factory, vault);
      final restoring = repository.restore();
      await reading.future;

      repository.cancelSignIn();
      response.complete(stateTestStored(credentials: stateTestCredentials));
      await restoring;

      expect(factory.profiles, isEmpty);
      expect(repository.state.isSignedIn, isFalse);
      expect(repository.state.phase, AuthPhase.idle);
    },
  );

  test('concurrent session checks share one verification and persist its refreshed result', () async {
    final verifying = Completer<void>();
    final response = Completer<LoginSession>();
    final gateway = StateTestGateway()
      ..onPassword = ((_) => LoginSuccess(stateTestSession()))
      ..onVerify = (_) {
        verifying.complete();
        return response.future;
      };
    final vault = StateTestVault();
    final repository = repositoryFor(StateTestGatewayFactory([gateway]), vault);
    await repository.signInPassword(
      stateTestProfile,
      stateTestCredentials,
      rememberPassword: true,
    );

    final checks = [
      repository.checkSession(),
      repository.checkSession(),
      repository.checkSession(),
    ];
    await verifying.future;
    expect(gateway.verificationCalls, ['student-a']);
    expect(repository.state.phase, AuthPhase.checking);
    final refreshed = stateTestSession(
      displayName: '更新后的姓名',
      verifiedAt: stateTestTime.add(const Duration(minutes: 5)),
    );
    response.complete(refreshed);
    await Future.wait(checks);

    expect(repository.state.account?.displayName, '更新后的姓名');
    expect(repository.state.phase, AuthPhase.idle);
    expect(vault.writes, hasLength(2));
    expect(vault.record?.session.verifiedAt, refreshed.verifiedAt);
  });

  test(
    'session checks never bind another account to saved credentials',
    () async {
      final active = StateTestGateway()
        ..onPassword = ((_) => LoginSuccess(stateTestSession()))
        ..onVerify = (_) =>
            stateTestSession(id: 'student-b', displayName: '另一账号');
      final reauthenticated = StateTestGateway()
        ..onPassword = (_) => LoginSuccess(stateTestSession());
      final vault = StateTestVault();
      final repository = repositoryFor(
        StateTestGatewayFactory([active, reauthenticated]),
        vault,
      );
      await repository.signInPassword(
        stateTestProfile,
        stateTestCredentials,
        rememberPassword: true,
      );
      final checkedStates = <AuthSnapshot>[];
      final subscription = repository.changes.listen(checkedStates.add);
      addTearDown(subscription.cancel);

      await repository.checkSession();

      expect(
        checkedStates.map((state) => state.account?.id),
        isNot(contains('student-b')),
      );
      expect(
        vault.writes.where((login) => login.session.account.id == 'student-b'),
        isEmpty,
      );
      if (reauthenticated.passwordCalls.isEmpty) {
        expect(repository.state.failure, isA<LoginFailure>());
      } else {
        expect(reauthenticated.passwordCalls.single.username, 'student-a');
        expect(repository.state.account?.id, 'student-a');
      }
    },
  );

  test(
    'restore never combines another account session with saved credentials',
    () async {
      final imported = StateTestGateway()
        ..onImportCookies = ((_, _) =>
            stateTestSession(id: 'student-b', displayName: '另一账号'))
        ..onPassword = (_) => LoginSuccess(stateTestSession());
      final reauthenticated = StateTestGateway()
        ..onPassword = (_) => LoginSuccess(stateTestSession());
      final vault = StateTestVault(
        record: stateTestStored(credentials: stateTestCredentials),
      );
      final repository = repositoryFor(
        StateTestGatewayFactory([imported, reauthenticated]),
        vault,
      );
      final restoredStates = <AuthSnapshot>[];
      final subscription = repository.changes.listen(restoredStates.add);
      addTearDown(subscription.cancel);

      await repository.restore();

      expect(
        restoredStates.map((state) => state.account?.id),
        isNot(contains('student-b')),
      );
      expect(
        vault.writes.where((login) => login.session.account.id == 'student-b'),
        isEmpty,
      );
      final passwordCalls = [
        ...imported.passwordCalls,
        ...reauthenticated.passwordCalls,
      ];
      if (passwordCalls.isEmpty) {
        expect(repository.state.failure, isA<LoginFailure>());
      } else {
        expect(passwordCalls.single.username, 'student-a');
        expect(repository.state.account?.id, 'student-a');
      }
    },
  );

  for (final rememberPassword in [true, false]) {
    test(
      'expired session checks reuse credentials only when remembered is $rememberPassword',
      () async {
        final active = StateTestGateway()
          ..onPassword = ((_) => LoginSuccess(stateTestSession()))
          ..onVerify = (_) => throw const LoginFailure(
            LoginFailureCode.expired,
            'synthetic expired session',
          );
        final renewed = StateTestGateway()
          ..onPassword = (_) => LoginSuccess(stateTestSession());
        final factory = StateTestGatewayFactory(
          rememberPassword ? [active, renewed] : [active],
        );
        final vault = StateTestVault();
        final repository = repositoryFor(factory, vault);
        await repository.signInPassword(
          stateTestProfile,
          stateTestCredentials,
          rememberPassword: rememberPassword,
        );

        await repository.checkSession();

        expect(active.closed, isTrue);
        expect(repository.state.isSignedIn, rememberPassword);
        if (rememberPassword) {
          expect(
            renewed.passwordCalls.single.password,
            '  synthetic password  ',
          );
          expect(repository.state.failure, isNull);
          expect(repository.state.remembered, isTrue);
        } else {
          expect(factory.profiles, hasLength(1));
          expect(repository.state.failure?.code, LoginFailureCode.expired);
          expect(vault.record?.credentials, isNull);
        }
      },
    );
  }
}
