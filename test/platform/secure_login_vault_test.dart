import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zf_core/zf_core.dart';
import 'package:zfhelper/platform/secure_login_vault.dart';

import '../support/auth_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'a new vault restores all school endpoints without requiring an account',
    () async {
      final school = SchoolConnection(
        name: '自选学校',
        baseUri: Uri.parse('https://school.example/teaching/'),
        loginPath: 'auth/login',
        publicKeyPath: 'auth/key',
        captchaPath: 'auth/captcha',
        accountPath: 'account/identity',
        schedulePagePath: 'schedule/page',
        scheduleQueryPath: 'schedule/query',
        schedulePeriodsPath: 'schedule/periods',
        webLoginUri: Uri.parse('https://identity.example/cas/login'),
      );
      await SecureLoginVault().writeSchool(school);

      final restarted = SecureLoginVault();
      final restored = (await restarted.readSchool())!;

      expect(restored.name, school.name);
      expect(restored.baseUri, school.baseUri);
      expect(restored.loginUri, school.loginUri);
      expect(restored.publicKeyUri, school.publicKeyUri);
      expect(restored.captchaUri, school.captchaUri);
      expect(restored.accountUri, school.accountUri);
      expect(restored.schedulePageUri, school.schedulePageUri);
      expect(restored.scheduleQueryUri, school.scheduleQueryUri);
      expect(restored.schedulePeriodsUri, school.schedulePeriodsUri);
      expect(restored.browserUri, school.browserUri);
      expect(await restarted.read(), isNull);
    },
  );

  test(
    'legacy saved logins migrate their school and clearing login preserves it',
    () async {
      final stored = StoredLogin(
        profile: testProfile,
        session: testSession(),
        method: LoginMethod.web,
      );
      FlutterSecureStorage.setMockInitialValues({
        'zfhelper.active_login.v1': StoredLoginCodec.encode(stored),
      });
      final gateway = TestLoginGateway()
        ..onImport = (_, _) async => testSession();
      final auth = AuthRepository(
        gatewayFactory: (_) => gateway,
        vault: SecureLoginVault(),
      );
      addTearDown(auth.dispose);

      await auth.restore();

      expect(auth.state.isSignedIn, isTrue);
      expect(gateway.importedCookies!.single.value, 'test-session');
      final restarted = SecureLoginVault();
      expect((await restarted.readSchool())?.name, testProfile.name);
      expect((await restarted.read())?.credentials, isNull);

      await auth.signOut();

      expect(await SecureLoginVault().read(), isNull);
      expect(
        (await SecureLoginVault().readSchool())?.baseUri,
        testProfile.baseUri,
      );
    },
  );

  test(
    'corrupt saved school data is reported instead of treated as first use',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'zfhelper.selected_school.v1': '{invalid-json',
      });

      await expectLater(
        SecureLoginVault().readSchool(),
        throwsA(
          isA<LoginFailure>().having(
            (failure) => failure.code,
            'code',
            LoginFailureCode.storage,
          ),
        ),
      );
    },
  );
}
