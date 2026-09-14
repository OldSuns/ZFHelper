import 'dart:async';

import 'package:test/test.dart';
import 'package:zf_core/zf_core.dart';

import 'auth_state_test_support.dart';

void main() {
  AuthRepository create(StateTestVault vault, List<StateTestGateway> gateways) {
    final repository = AuthRepository(
      gatewayFactory: StateTestGatewayFactory(gateways).call,
      vault: vault,
    );
    addTearDown(repository.dispose);
    return repository;
  }

  test(
    'a password login restores without saving or resubmitting its password',
    () async {
      final vault = StateTestVault();
      final signingIn = StateTestGateway()
        ..onPassword = (_) => LoginSuccess(stateTestSession());
      final first = create(vault, [signingIn]);
      await first.signInPassword(stateTestProfile, stateTestCredentials);
      await first.dispose();
      final restoring = StateTestGateway()
        ..onImportCookies = (_, _) => stateTestSession();
      final restarted = create(vault, [restoring]);

      await restarted.restore();

      expect(restarted.state.account?.id, stateTestSession().account.id);
      expect(restarted.state.profile?.baseUri, stateTestProfile.baseUri);
      expect(restarted.state.remembered, isTrue);
      expect(vault.record?.credentials, isNull);
      expect(restoring.importCalls.single.cookies.single.expiresAt, isNull);
      expect(restoring.passwordCalls, isEmpty);
    },
  );

  test(
    'a network failure retains the saved identity and retries the same session',
    () async {
      final stored = stateTestStored(method: LoginMethod.web);
      final vault = StateTestVault(record: stored);
      final offline = StateTestGateway()
        ..onImportCookies = (_, _) => throw const LoginFailure(
          LoginFailureCode.network,
          'synthetic offline',
        );
      final online = StateTestGateway()
        ..onImportCookies = (_, _) => stateTestSession();
      final repository = create(vault, [offline, online]);

      await repository.restore();
      final identity = repository.state.knownIdentity!;

      expect(repository.state.isSignedIn, isFalse);
      expect(repository.state.canRestoreSession, isTrue);
      expect(repository.state.needsSignIn, isFalse);
      expect(repository.state.failure?.code, LoginFailureCode.network);
      expect(vault.record, same(stored));
      expect(vault.clearCalls, 0);
      expect(vault.school?.baseUri, stored.profile.baseUri);

      await repository.restore();

      expect(repository.state.isSignedIn, isTrue);
      expect(repository.isCurrentIdentity(identity), isTrue);
      expect(online.importCalls.single.cookies, stored.session.cookies);
      expect(online.passwordCalls, isEmpty);
      expect(repository.state.failure, isNull);
    },
  );

  test('concurrent restore callers wait for one school verification', () async {
    final importing = Completer<void>();
    final verified = Completer<LoginSession>();
    final gateway = StateTestGateway()
      ..onImportCookies = (_, _) {
        importing.complete();
        return verified.future;
      };
    final vault = StateTestVault(
      record: stateTestStored(method: LoginMethod.web),
    );
    final repository = create(vault, [gateway]);
    final first = repository.restore();
    await importing.future;

    var secondFinished = false;
    final second = repository.restore().then((_) => secondFinished = true);
    await Future<void>.value();
    expect(secondFinished, isFalse);
    expect(repository.state.isSignedIn, isFalse);
    verified.complete(stateTestSession());
    await Future.wait([first, second]);

    expect(vault.readCalls, 1);
    expect(gateway.importCalls, hasLength(1));
    expect(repository.state.isSignedIn, isTrue);
  });

  test(
    'a network interruption during password renewal can retry the saved login',
    () async {
      const expired = LoginFailure(
        LoginFailureCode.expired,
        'synthetic expiry',
      );
      final active = StateTestGateway()
        ..onPassword = ((_) => LoginSuccess(stateTestSession()))
        ..onVerify = (_) => throw expired;
      final offline = StateTestGateway()
        ..onPassword = (_) => throw const LoginFailure(
          LoginFailureCode.network,
          'synthetic offline renewal',
        );
      final online = StateTestGateway()
        ..onImportCookies = ((_, _) => throw expired)
        ..onPassword = (_) => LoginSuccess(stateTestSession());
      final vault = StateTestVault();
      final repository = create(vault, [active, offline, online]);
      await repository.signInPassword(
        stateTestProfile,
        stateTestCredentials,
        rememberPassword: true,
      );
      final identity = repository.state.knownIdentity!;

      await repository.checkSession();

      expect(repository.state.isSignedIn, isFalse);
      expect(repository.state.failure?.code, LoginFailureCode.network);
      expect(repository.state.canRestoreSession, isTrue);
      await repository.restore();

      expect(repository.state.isSignedIn, isTrue);
      expect(repository.isCurrentIdentity(identity), isTrue);
      expect(
        online.passwordCalls.single.username,
        stateTestCredentials.username,
      );
    },
  );

  test(
    'school expiry requests login while keeping the school and account known',
    () async {
      final vault = StateTestVault(
        record: stateTestStored(method: LoginMethod.web),
      );
      final expired = StateTestGateway()
        ..onImportCookies = (_, _) => throw const LoginFailure(
          LoginFailureCode.expired,
          'synthetic server logout',
        );
      final repository = create(vault, [expired]);

      await repository.restore();

      expect(repository.state.isSignedIn, isFalse);
      expect(repository.state.needsSignIn, isTrue);
      expect(repository.state.canRestoreSession, isFalse);
      expect(repository.state.profile?.name, stateTestProfile.name);
      expect(repository.state.knownIdentity?.account.id, 'student-a');
      expect(expired.passwordCalls, isEmpty);
    },
  );

  test(
    'explicit sign out retains school settings but cannot restore a login',
    () async {
      final vault = StateTestVault();
      final gateway = StateTestGateway()
        ..onImportCookies = (_, _) => stateTestSession();
      final repository = create(vault, [gateway]);
      await repository.configureSchool(stateTestProfile);
      await repository.signInCookies(
        stateTestProfile,
        stateTestSession().cookies,
        method: LoginMethod.web,
      );

      await repository.signOut();
      await repository.dispose();
      final restarted = create(vault, []);
      await restarted.restore();

      expect(restarted.state.profile?.baseUri, stateTestProfile.baseUri);
      expect(restarted.state.isSignedIn, isFalse);
      expect(restarted.state.knownIdentity, isNull);
      expect(vault.record, isNull);
    },
  );

  test(
    'changing the configured school never changes an existing account scope',
    () async {
      final vault = StateTestVault();
      final gateway = StateTestGateway()
        ..onImportCookies = ((_, _) => stateTestSession())
        ..onVerify = (_) => stateTestSession();
      final repository = create(vault, [gateway]);
      await repository.signInCookies(
        stateTestProfile,
        stateTestSession().cookies,
        method: LoginMethod.web,
      );
      final identity = repository.state.knownIdentity!;

      await repository.configureSchool(stateTestOtherProfile);
      await repository.checkSession();

      expect(repository.isCurrentIdentity(identity), isTrue);
      expect(repository.state.profile?.baseUri, stateTestProfile.baseUri);
      expect(
        repository.state.configuredProfile?.baseUri,
        stateTestOtherProfile.baseUri,
      );
      expect(vault.school?.baseUri, stateTestOtherProfile.baseUri);
      expect(vault.record?.profile.baseUri, stateTestProfile.baseUri);
    },
  );
}
