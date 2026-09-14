import 'dart:async';

import 'package:test/test.dart';
import 'package:zf_core/src/auth/auth_repository.dart';
import 'package:zf_core/src/auth/login_models.dart';

import 'auth_state_test_support.dart';

const _completionLimit = Duration(seconds: 3);

void main() {
  group('session checks after changing accounts', () {
    late Completer<LoginSession> oldResponse;
    late Completer<LoginSession> currentResponse;
    late StateTestGateway oldGateway;
    late StateTestGateway currentGateway;
    late AuthRepository repository;
    late List<Future<void>> checks;

    setUp(() {
      oldResponse = Completer<LoginSession>();
      currentResponse = Completer<LoginSession>();
      oldGateway = StateTestGateway()
        ..onPassword = ((_) => LoginSuccess(stateTestSession()))
        ..onVerify = (_) => oldResponse.future;
      currentGateway = StateTestGateway()
        ..onPassword = ((_) => LoginSuccess(stateTestSession(id: 'student-b')))
        ..onVerify = (_) => currentResponse.future;
      repository = AuthRepository(
        initialProfile: stateTestProfile,
        gatewayFactory: StateTestGatewayFactory([oldGateway, currentGateway])
            .call,
        vault: StateTestVault(),
      );
      checks = [];
    });

    tearDown(() async {
      if (!oldResponse.isCompleted) oldResponse.complete(stateTestSession());
      if (!currentResponse.isCompleted) {
        currentResponse.complete(stateTestSession(id: 'student-b'));
      }
      try {
        await Future.wait(checks).timeout(_completionLimit);
      } finally {
        await repository.dispose();
      }
    });

    Future<void> switchAccountsWithOldCheckPending() async {
      expect(
        await repository.signInPassword(
          stateTestProfile,
          stateTestCredentials,
          rememberPassword: false,
        ),
        isTrue,
      );
      checks.add(repository.checkSession());
      expect(oldGateway.verificationCalls, ['student-a']);

      await repository.signOut();
      expect(oldGateway.closed, isTrue);
      // close() requests cancellation; a late completion is still possible.
      expect(oldResponse.isCompleted, isFalse);

      expect(
        await repository.signInPassword(
          stateTestProfile,
          LoginCredentials(
            username: 'student-b',
            password: 'synthetic-second-password',
          ),
          rememberPassword: false,
        ),
        isTrue,
      );
    }

    test(
      'the current account is checked without waiting for the old response',
      () async {
        await switchAccountsWithOldCheckPending();

        final currentCheck = repository.checkSession();
        checks.add(currentCheck);
        expect(currentGateway.verificationCalls, ['student-b']);

        currentResponse.complete(stateTestSession(id: 'student-b'));
        await currentCheck.timeout(_completionLimit);

        expect(oldResponse.isCompleted, isFalse);
        expect(repository.state.account?.id, 'student-b');
        expect(repository.state.phase, AuthPhase.idle);
        expect(repository.state.failure, isNull);
      },
    );

    test(
      'old completion does not release the current in-flight check',
      () async {
        await switchAccountsWithOldCheckPending();

        checks.add(repository.checkSession());
        expect(currentGateway.verificationCalls, ['student-b']);
        oldResponse.complete(stateTestSession());
        await checks.first.timeout(_completionLimit);

        checks.add(repository.checkSession());
        expect(currentGateway.verificationCalls, ['student-b']);
        expect(repository.state.account?.id, 'student-b');
        expect(repository.state.phase, AuthPhase.checking);

        currentResponse.complete(stateTestSession(id: 'student-b'));
        await Future.wait(checks).timeout(_completionLimit);

        expect(repository.state.account?.id, 'student-b');
        expect(repository.state.phase, AuthPhase.idle);
        expect(repository.state.failure, isNull);
      },
    );
  });
}
