import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zf_core/zf_core.dart';
import 'package:zfhelper/app/app.dart';
import 'package:zfhelper/app/app_configuration.dart';
import 'package:zfhelper/ui/features/auth/views/login_page.dart';
import 'package:zfhelper/ui/features/auth/views/login_advanced_settings_page.dart';
import 'package:zfhelper/ui/features/auth/views/school_connection_page.dart';
import 'package:zfhelper/ui/features/settings/views/account_settings_page.dart';

import '../../../support/auth_fakes.dart';
import '../../../support/schedule_fakes.dart';
import '../../../support/grade_fakes.dart';
import '../../../support/course_fakes.dart';

void main() {
  final captchaPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  Future<AuthRepository> openLogin(
    WidgetTester tester, {
    TestLoginGateway? gateway,
    TestLoginVault? vault,
    void Function(SchoolConnection)? onProfile,
    Size size = const Size(420, 1100),
    double textScale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    final auth = testAuth(
      vault: vault,
      gatewayFactory: (profile) {
        onProfile?.call(profile);
        return gateway ?? (throw StateError('Unexpected request.'));
      },
    );
    await tester.pumpWidget(
      ZfHelperApp(
        configuration: AppConfiguration(
          courses: testCourseRepository(),
          grades: testGradeRepository(),
          schedule: testScheduleRepository(),
          auth: auth,
          clock: () => DateTime(2026, 9, 12, 13),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('账号与设置'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('登录 / 更换学校'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('登录 / 更换学校'));
    await tester.pumpAndSettle();
    return auth;
  }

  Future<void> submit(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('login-submit'));
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pump();
  }

  Future<void> enterCredentials(
    WidgetTester tester, {
    String password = 'test-password',
  }) async {
    await tester.enterText(
      find.byKey(const ValueKey('login-username')),
      '20260001',
    );
    await tester.enterText(
      find.byKey(const ValueKey('login-password')),
      password,
    );
  }

  Future<void> openAdvanced(WidgetTester tester) async {
    await tester.ensureVisible(find.byTooltip('登录设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('登录设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('高级设置'));
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.pumpAndSettle();
    final finder = find.byKey(ValueKey(key));
    await tester.scrollUntilVisible(
      finder,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('custom school and base URL reach the same login flow', (
    tester,
  ) async {
    SchoolConnection? requestedProfile;
    final vault = TestLoginVault();
    final gateway = TestLoginGateway()
      ..onPassword = (_) async => LoginSuccess(testSession());
    final auth = await openLogin(
      tester,
      gateway: gateway,
      vault: vault,
      onProfile: (p) => requestedProfile = p,
    );
    await tester.tap(find.byKey(const ValueKey('school-selector')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('school-name')), '另一所大学');
    await tester.enterText(
      find.byKey(const ValueKey('school-address')),
      'academic.other.test/prefix/jwglxt/kbcx/xskbcx_cxXsgrkb.html?xnm=2026#week',
    );
    await tester.pump();
    expect(find.text('https://academic.other.test'), findsOneWidget);
    expect(find.text('/prefix/jwglxt/'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('school-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('school-save')));
    await tester.pumpAndSettle();
    await enterCredentials(tester, password: '  keep whitespace  ');
    await submit(tester);
    await tester.pumpAndSettle();

    expect(requestedProfile?.name, '另一所大学');
    expect(
      requestedProfile?.loginUri.toString(),
      'https://academic.other.test/prefix/jwglxt/xtgl/login_slogin.html',
    );
    expect(gateway.credentials?.password, '  keep whitespace  ');
    expect(auth.state.isSignedIn, isTrue);
    expect(vault.saved?.session.account.id, '20260001');
    expect(vault.saved?.credentials, isNull);
    expect(find.byType(AccountSettingsPage), findsOneWidget);
    expect(find.text('另一所大学'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('已连接教务账号'), findsOneWidget);
    expect(find.text('另一所大学'), findsOneWidget);
    expect(find.text('课表还没有同步'), findsOneWidget);
  });

  testWidgets(
    'new login does not reuse the current account as a cookie identity hint',
    (tester) async {
      final gateway = TestLoginGateway()
        ..onPassword = (_) async => LoginSuccess(testSession());
      await openLogin(tester, gateway: gateway);
      await enterCredentials(tester);
      await submit(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('切换学校或账号'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cookie 导入'));
      await tester.pumpAndSettle();
      final username = tester.widget<TextFormField>(
        find.byKey(const ValueKey('login-username')),
      );
      expect(username.controller!.text, isEmpty);
    },
  );

  testWidgets('invalid connection settings never start authentication', (
    tester,
  ) async {
    final gateway = TestLoginGateway();
    await openLogin(tester, gateway: gateway);
    await tester.tap(find.byKey(const ValueKey('school-selector')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('school-address')),
      'not-a-url',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('school-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('school-save')));
    await tester.pumpAndSettle();
    expect(gateway.passwordCalls, 0);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('school-address')))
          .decoration!
          .errorText,
      isNotNull,
    );
    expect(find.byType(SchoolConnectionPage), findsOneWidget);
  });

  testWidgets(
    'password rejection preserves the form and never marks it connected',
    (tester) async {
      final gateway = TestLoginGateway()
        ..onPassword = (_) async => throw const LoginFailure(
          LoginFailureCode.invalidCredentials,
          '用户名或密码不正确',
        );
      final auth = await openLogin(tester, gateway: gateway);
      await enterCredentials(tester);
      await submit(tester);
      await tester.pumpAndSettle();
      expect(auth.state.isSignedIn, isFalse);
      expect(find.text('用户名或密码不正确'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('login-username')))
            .controller!
            .text,
        '20260001',
      );
    },
  );

  testWidgets('captcha can be refreshed, retried, then verified', (
    tester,
  ) async {
    var attempts = 0;
    var refreshes = 0;
    final gateway = TestLoginGateway()
      ..onPassword = (_) async {
        return CaptchaRequired(image: captchaPng);
      }
      ..onRefreshCaptcha = () async {
        refreshes++;
        return captchaPng;
      }
      ..onCaptcha = (code) async {
        attempts++;
        if (code != 'correct') {
          return CaptchaRequired(
            image: captchaPng,
            rejected: true,
            message: '验证码未通过，请重新输入',
          );
        }
        return LoginSuccess(testSession());
      };
    final auth = await openLogin(tester, gateway: gateway);
    await enterCredentials(tester);
    await submit(tester);
    await tester.pumpAndSettle();
    expect(auth.state.isSignedIn, isFalse);
    final refresh = find.text('换一张验证码');
    await tester.ensureVisible(refresh);
    await tester.tap(refresh);
    await tester.pumpAndSettle();
    expect(refreshes, 1);
    await tester.enterText(
      find.byKey(const ValueKey('login-captcha')),
      'wrong',
    );
    await submit(tester);
    await tester.pumpAndSettle();
    expect(find.text('验证码未通过，请重新输入'), findsOneWidget);
    final semantics = tester.ensureSemantics();
    try {
      await tester.pump();
      expect(find.bySemanticsLabel('验证码未通过，请重新输入'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
    await tester.enterText(
      find.byKey(const ValueKey('login-captcha')),
      'correct',
    );
    await submit(tester);
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(auth.state.isSignedIn, isTrue);
    expect(find.byType(AccountSettingsPage), findsOneWidget);
  });

  testWidgets('cancel closes an attempt and ignores its late success', (
    tester,
  ) async {
    final completion = Completer<LoginStep>();
    final gateway = TestLoginGateway()..onPassword = (_) => completion.future;
    final auth = await openLogin(tester, gateway: gateway);
    await enterCredentials(tester);
    await submit(tester);
    await tester.pump();
    await tester.ensureVisible(find.text('取消并重新填写'));
    await tester.tap(find.text('取消并重新填写'));
    await tester.pumpAndSettle();
    completion.complete(LoginSuccess(testSession()));
    await tester.pumpAndSettle();
    expect(gateway.closed, isTrue);
    expect(auth.state.isSignedIn, isFalse);
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets(
    'Cookie login and school survive restart without an extra remember toggle',
    (tester) async {
      final vault = TestLoginVault();
      final gateway = TestLoginGateway()
        ..onImport = (cookies, hint) async => testSession();
      final auth = await openLogin(tester, gateway: gateway, vault: vault);
      await tester.tap(find.text('Cookie 导入'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('cookie-input')),
        'Cookie: JSESSIONID=token==; route=node1',
      );
      await submit(tester);
      await tester.pumpAndSettle();
      expect(gateway.importedCookies!.first.value, 'token==');
      expect(gateway.importedCookies!.first.secure, isTrue);
      expect(auth.state.isSignedIn, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      final restored = AuthRepository(
        gatewayFactory: (_) =>
            TestLoginGateway()..onImport = (_, _) async => testSession(),
        vault: vault,
      );
      addTearDown(restored.dispose);
      await restored.restore();

      expect(restored.state.profile?.name, testProfile.name);
      expect(restored.state.profile?.baseUri, testProfile.baseUri);
      expect(restored.state.isSignedIn, isTrue);
      expect(vault.saved?.credentials, isNull);
    },
  );

  testWidgets('saved school survives restart before the first login', (
    tester,
  ) async {
    final vault = TestLoginVault();
    await openLogin(tester, vault: vault);
    await tapKey(tester, 'school-selector');
    await tester.enterText(find.byKey(const ValueKey('school-name')), '自选大学');
    await tester.enterText(
      find.byKey(const ValueKey('school-address')),
      'https://chosen.example.edu/jwglxt/',
    );
    await tapKey(tester, 'school-save');
    await tester.pumpWidget(const SizedBox.shrink());
    final restored = AuthRepository(
      gatewayFactory: (_) =>
          throw StateError('School restore must stay offline.'),
      vault: vault,
    );
    addTearDown(restored.dispose);

    await restored.restore();

    expect(restored.state.profile?.name, '自选大学');
    expect(
      restored.state.profile?.baseUri.toString(),
      'https://chosen.example.edu/jwglxt/',
    );
    expect(restored.state.isSignedIn, isFalse);
  });

  testWidgets('failed school save retains input and can be retried', (
    tester,
  ) async {
    final vault = TestLoginVault()
      ..schoolWriteFailure = const LoginFailure(
        LoginFailureCode.storage,
        '学校设置未能保存到本机，请重试',
      );
    final auth = await openLogin(tester, vault: vault);
    await tapKey(tester, 'school-selector');
    await tester.enterText(find.byKey(const ValueKey('school-name')), '新的学校');
    await tester.enterText(
      find.byKey(const ValueKey('school-address')),
      testProfile.baseUri.toString(),
    );
    await tapKey(tester, 'school-save');

    expect(find.byType(SchoolConnectionPage), findsOneWidget);
    expect(find.text('学校设置未能保存到本机，请重试'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('school-name')))
          .controller!
          .text,
      '新的学校',
    );
    expect(auth.state.configuredProfile?.name, testProfile.name);

    vault.schoolWriteFailure = null;
    await tapKey(tester, 'school-save');

    expect(find.byType(LoginPage), findsOneWidget);
    expect(vault.school?.name, '新的学校');
  });

  testWidgets(
    'offline restore keeps the account visible and offers a session retry',
    (tester) async {
      final vault = TestLoginVault()
        ..saved = StoredLogin(
          profile: testProfile,
          session: testSession(),
          method: LoginMethod.web,
        );
      var attempts = 0;
      final gateway = TestLoginGateway()
        ..onImport = (_, _) async {
          if (attempts++ == 0) {
            throw const LoginFailure(LoginFailureCode.network, '教务网络暂不可用');
          }
          return testSession();
        };
      final auth = await openLogin(tester, vault: vault, gateway: gateway);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('登录待核验'), findsOneWidget);
      expect(find.text('账号 20260001'), findsOneWidget);
      expect(find.text('教务网络暂不可用'), findsOneWidget);
      expect(auth.state.isSignedIn, isFalse);
      await tapKey(tester, 'restore-login');

      expect(auth.state.isSignedIn, isTrue);
      expect(attempts, 2);
      expect(gateway.passwordCalls, 0);
      expect(find.text('已连接'), findsOneWidget);
    },
  );

  testWidgets('Cookie rejection stays unconnected', (tester) async {
    final gateway = TestLoginGateway()
      ..onImport = (_, _) async =>
          throw const LoginFailure(LoginFailureCode.expired, '教务登录状态已失效，请重新登录');
    final auth = await openLogin(tester, gateway: gateway);
    await tester.tap(find.text('Cookie 导入'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('cookie-input')),
      'JSESSIONID=anonymous',
    );
    await submit(tester);
    await tester.pumpAndSettle();
    expect(auth.state.isSignedIn, isFalse);
    expect(find.text('教务登录状态已失效，请重新登录'), findsOneWidget);
  });

  testWidgets('automatic session save failures keep verified login visible', (
    tester,
  ) async {
    final vault = TestLoginVault()
      ..writeFailure = const LoginFailure(LoginFailureCode.storage, '无法保存到本机');
    final gateway = TestLoginGateway()
      ..onPassword = (_) async => LoginSuccess(testSession());
    final auth = await openLogin(tester, gateway: gateway, vault: vault);
    await enterCredentials(tester);
    await submit(tester);
    await tester.pumpAndSettle();
    expect(auth.state.isSignedIn, isTrue);
    expect(auth.state.remembered, isFalse);
    expect(find.text('无法保存到本机'), findsOneWidget);
    expect(find.text('当前登录仅在本次运行中有效'), findsOneWidget);
  });

  testWidgets(
    'advanced settings preserve grade paths and SSO and can restore defaults',
    (tester) async {
      final vault = TestLoginVault();
      await openLogin(tester, vault: vault);
      expect(find.byType(ExpansionTile), findsNothing);
      expect(find.text('RSA 公钥路径'), findsNothing);
      expect(find.byKey(const ValueKey('school-address')), findsNothing);
      expect(find.byKey(const ValueKey('web-login-open')), findsOneWidget);
      await openAdvanced(tester);
      expect(find.byType(LoginAdvancedSettingsPage), findsOneWidget);
      const gradePaths = {
        '成绩页面路径': 'results/index',
        '成绩查询路径': 'results/query?doType=query',
      };
      final scrollable = find.byType(Scrollable).first;
      for (final entry in gradePaths.entries) {
        final field = find.widgetWithText(TextField, entry.key);
        await tester.scrollUntilVisible(field, 180, scrollable: scrollable);
        await tester.enterText(field, entry.value);
      }
      final sso = find.byKey(const ValueKey('web-login-address'));
      await tester.scrollUntilVisible(sso, 180, scrollable: scrollable);
      await tester.enterText(sso, 'https://sso.other.test/cas/login');
      await tapKey(tester, 'advanced-save');
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byKey(const ValueKey('web-login-address')), findsNothing);
      expect(vault.school!.gradePagePath, 'results/index');
      expect(vault.school!.gradeQueryPath, 'results/query?doType=query');
      await openAdvanced(tester);
      for (final entry in gradePaths.entries) {
        final field = find.widgetWithText(TextField, entry.key);
        await tester.scrollUntilVisible(field, 180, scrollable: scrollable);
        expect(tester.widget<TextField>(field).controller!.text, entry.value);
      }
      await tester.scrollUntilVisible(sso, 180, scrollable: scrollable);
      expect(
        tester.widget<TextField>(sso).controller!.text,
        'https://sso.other.test/cas/login',
      );
      final reset = find.text('恢复默认设置');
      await tester.scrollUntilVisible(reset, 180, scrollable: scrollable);
      await tester.tap(reset);
      await tapKey(tester, 'advanced-save');
      expect(
        vault.school!.gradePagePath,
        SchoolConnection.defaultGradePagePath,
      );
      expect(
        vault.school!.gradeQueryPath,
        SchoolConnection.defaultGradeQueryPath,
      );
      expect(vault.school!.webLoginUri, isNull);
    },
  );

  testWidgets(
    'advanced settings are transactional and keep explicit root paths',
    (tester) async {
      SchoolConnection? requested;
      final gateway = TestLoginGateway()
        ..onPassword = (_) async => LoginSuccess(testSession());
      await openLogin(
        tester,
        gateway: gateway,
        onProfile: (profile) => requested = profile,
      );
      await openAdvanced(tester);
      final loginPath = find.widgetWithText(TextField, '密码登录路径');
      await tester.enterText(loginPath, 'cancelled/login.html');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await openAdvanced(tester);
      expect(
        tester.widget<TextField>(loginPath).controller!.text,
        testProfile.loginPath,
      );
      await tester.enterText(
        find.byKey(const ValueKey('advanced-base-address')),
        'https://other.example/prefix/xtgl/custom/',
      );
      await tester.enterText(loginPath, 'auth/login.html');
      await tapKey(tester, 'advanced-save');
      await enterCredentials(tester);
      await submit(tester);
      await tester.pumpAndSettle();
      expect(
        requested!.baseUri.toString(),
        'https://other.example/prefix/xtgl/custom/',
      );
      expect(requested!.loginPath, 'auth/login.html');
    },
  );

  testWidgets(
    'changing schools clears credentials typed for the previous school',
    (tester) async {
      await openLogin(tester);
      await enterCredentials(tester);
      await tapKey(tester, 'school-selector');
      await tester.enterText(
        find.byKey(const ValueKey('school-address')),
        'new.example.edu.cn/jwxt/cjcx/results.html',
      );
      await tester.enterText(find.byKey(const ValueKey('school-name')), '新的学校');
      await tapKey(tester, 'school-save');
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('login-username')))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('login-password')))
            .controller!
            .text,
        isEmpty,
      );
      expect(find.text('新的学校'), findsOneWidget);
    },
  );

  testWidgets('manual input wins over a late clipboard response', (
    tester,
  ) async {
    final clipboard = Completer<Map<String, dynamic>?>();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return clipboard.future;
      if (call.method == 'Clipboard.hasStrings') return {'value': false};
      return null;
    });
    addTearDown(() {
      if (!clipboard.isCompleted) clipboard.complete(null);
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
    await openLogin(tester);
    await tapKey(tester, 'school-selector');
    await tester.tap(find.byTooltip('粘贴网址'));
    await tester.pump();
    final address = find.byKey(const ValueKey('school-address'));
    await tester.enterText(address, 'new.example/jwglxt/');
    clipboard.complete({'text': 'old.example/jwglxt/'});
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(address).controller!.text,
      'new.example/jwglxt/',
    );
    expect(find.text('https://new.example'), findsOneWidget);
  });

  testWidgets('cancelled school editing does not change the login target', (
    tester,
  ) async {
    await openLogin(tester);
    await tapKey(tester, 'school-selector');
    final address = find.byKey(const ValueKey('school-address'));
    await tester.enterText(
      address,
      'new.example/jwglxt/xtgl/login_slogin.html',
    );
    await tester.pump();
    expect(find.text('https://new.example'), findsOneWidget);
    await tester.enterText(address, 'bad address');
    await tester.pump();
    expect(find.byKey(const ValueKey('recognized-origin')), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text(testProfile.name), findsOneWidget);
    expect(find.text(testProfile.baseUri.toString()), findsOneWidget);
  });

  for (final size in [const Size(320, 640), const Size(780, 360)]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'login stays usable at $size with large text and system ${brightness.name}',
        (tester) async {
          await openLogin(
            tester,
            size: size,
            textScale: 2,
            brightness: brightness,
          );
          expect(
            Theme.of(tester.element(find.byType(LoginPage))).brightness,
            brightness,
          );
          await tester.scrollUntilVisible(
            find.text('Cookie 导入'),
            180,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Cookie 导入'));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('login-submit')),
            180,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(find.text('导入并验证'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('school and advanced editors support 200% text on a small phone', (
    tester,
  ) async {
    await openLogin(tester, size: const Size(320, 640), textScale: 2);
    await tapKey(tester, 'school-selector');
    expect(find.text('智能识别网址'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.enterText(
      find.byKey(const ValueKey('school-address')),
      'https://long.school.example.edu.cn/prefix/jwglxt/xtgl/login_slogin.html',
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('school-name')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const ValueKey('school-name')),
      '用户选择的学校',
    );
    await tapKey(tester, 'school-save');
    await openAdvanced(tester);
    await tapKey(tester, 'advanced-save');
    expect(find.byType(LoginPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
