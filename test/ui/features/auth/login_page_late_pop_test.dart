import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zf_core/zf_core.dart';
import 'package:zfhelper/app/app.dart';
import 'package:zfhelper/app/app_configuration.dart';
import 'package:zfhelper/ui/features/auth/views/login_page.dart';
import 'package:zfhelper/ui/features/settings/views/account_settings_page.dart';

import '../../../support/auth_fakes.dart';
import '../../../support/schedule_fakes.dart';
import '../../../support/grade_fakes.dart';
import '../../../support/course_fakes.dart';
import '../../../support/settings_fakes.dart';

void main() {
  testWidgets('finishing a save during back navigation keeps settings open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final vault = _DeferredWriteVault();
    final gateway = TestLoginGateway()
      ..onPassword = (_) async => LoginSuccess(testSession());
    final auth = AuthRepository(
      initialProfile: testProfile,
      gatewayFactory: (_) => gateway,
      vault: vault,
    );
    addTearDown(() async {
      if (!vault.releaseWrite.isCompleted) vault.releaseWrite.complete();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    await tester.pumpWidget(
      ZfHelperApp(
        configuration: AppConfiguration(
          appearance: testAppearance(),
          courses: testCourseRepository(),
          grades: testGradeRepository(),
          schedule: testScheduleRepository(),
          auth: auth,
          clock: () => DateTime(2026, 9, 12, 13),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, '设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '账号与学校'));
    await tester.pumpAndSettle();
    final openLogin = find.byKey(const ValueKey('add-account'));
    await tester.scrollUntilVisible(
      openLogin,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(openLogin);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('login-username')),
      '20260001',
    );
    await tester.enterText(
      find.byKey(const ValueKey('login-password')),
      'synthetic-password',
    );
    final submit = find.byKey(const ValueKey('login-submit'));
    await tester.ensureVisible(submit);
    await tester.pump();
    await tester.tap(submit);
    await tester.pump();

    expect(vault.writeStarted.isCompleted, isTrue);
    expect(auth.state.phase, AuthPhase.saving);
    final departingLogin = tester.element(find.byType(LoginPage));

    await tester.tap(find.byType(BackButton));
    // Keep the reverse transition alive: an exiting route can still be mounted.
    await tester.pump();
    expect(departingLogin.mounted, isTrue);

    vault.releaseWrite.complete();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(LoginPage), findsNothing);
    expect(find.byType(AccountSettingsPage), findsOneWidget);
    expect(find.widgetWithText(AppBar, '账号与学校'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

final class _DeferredWriteVault implements LoginVault {
  final writeStarted = Completer<void>();
  final releaseWrite = Completer<void>();
  StoredLogin? _saved;
  SchoolConnection? _school;
  StoredLoginLibrary? _library;

  @override
  Future<StoredLoginLibrary> readAccounts() async =>
      _library ?? StoredLoginLibrary.fromLogin(_saved);

  @override
  Future<void> writeAccounts(StoredLoginLibrary library) async {
    final selected = library.selected?.login;
    if (selected == null) {
      await clear();
    } else {
      await write(selected);
    }
    _library = library;
  }

  @override
  Future<SchoolConnection?> readSchool() async => _school;

  @override
  Future<void> writeSchool(SchoolConnection profile) async => _school = profile;

  @override
  Future<StoredLogin?> read() async => _saved;

  @override
  Future<void> write(StoredLogin login) async {
    writeStarted.complete();
    await releaseWrite.future;
    _saved = login;
  }

  @override
  Future<void> clear() async {
    _saved = null;
  }
}
