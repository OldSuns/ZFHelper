import 'package:flutter_test/flutter_test.dart';
import 'package:zf_core/zf_core.dart';
import 'package:zfhelper/ui/features/auth/view_models/school_address_view_model.dart';

void main() {
  final original = SchoolConnection(
    name: '原学校',
    baseUri: Uri.parse('https://old.example/education/'),
    loginPath: 'custom/login.html',
    gradePagePath: 'custom/grades',
    gradeQueryPath: 'custom/grades?doType=query',
    webLoginUri: Uri.parse('https://identity.example/cas/login'),
  );

  test(
    'new input replaces the preview and cannot reuse an earlier valid result',
    () {
      final model = SchoolAddressViewModel(
        initialProfile: original,
        address: '',
      );
      addTearDown(model.dispose);
      model.changeAddress(
        'new.example/prefix/jwglxt/kbcx/page.html?token=synthetic',
      );
      expect(
        model.recognizedAddress.toString(),
        'https://new.example/prefix/jwglxt/',
      );
      model.changeAddress('invalid input');
      expect(model.recognizedAddress, isNull);
      expect(model.addressError, isNull);
      expect(model.submit('学校'), isNull);
      expect(model.addressError, isNotNull);
      model.changeAddress('http://next.example:8080/custom');
      expect(model.addressError, isNull);
      expect(
        model.submit('学校')!.baseUri.toString(),
        'http://next.example:8080/custom/',
      );
    },
  );

  test('new school restores standard endpoints and does not inherit SSO', () {
    final model = SchoolAddressViewModel(
      initialProfile: original,
      address: 'new.example/jwglxt/',
    );
    addTearDown(model.dispose);
    expect(model.resetsCustomSettings, isTrue);
    expect(model.submit('   '), isNull);
    expect(model.nameError, isNotNull);
    final next = model.submit('新学校')!;
    expect(next.name, '新学校');
    expect(
      next.loginUri.toString(),
      'https://new.example/jwglxt/xtgl/login_slogin.html',
    );
    expect(next.webLoginUri, isNull);
    expect(next.gradePagePath, SchoolConnection.defaultGradePagePath);
    expect(next.gradeQueryPath, SchoolConnection.defaultGradeQueryPath);
    expect(original.loginPath, 'custom/login.html');
    expect(original.webLoginUri!.host, 'identity.example');
  });

  test('renaming the same school preserves advanced settings', () {
    final model = SchoolAddressViewModel(initialProfile: original);
    addTearDown(model.dispose);
    final next = model.submit(' 新名称 ')!;
    expect(next.name, '新名称');
    expect(next.loginPath, original.loginPath);
    expect(next.webLoginUri, original.webLoginUri);
    expect(next.gradePagePath, original.gradePagePath);
    expect(next.gradeQueryPath, original.gradeQueryPath);
    expect(next.baseUri, original.baseUri);
    expect(model.resetsCustomSettings, isFalse);
  });

  test('changing schools identifies custom grade endpoints for reset', () {
    for (final profile in [
      SchoolConnection(
        name: '原学校',
        baseUri: original.baseUri,
        gradePagePath: 'custom/grades',
      ),
      SchoolConnection(
        name: '原学校',
        baseUri: original.baseUri,
        gradeQueryPath: 'custom/grades?doType=query',
      ),
    ]) {
      final model = SchoolAddressViewModel(
        initialProfile: profile,
        address: 'new.example/jwglxt/',
      );
      addTearDown(model.dispose);
      expect(model.resetsCustomSettings, isTrue);
      final next = model.submit('新学校')!;
      expect(next.gradePagePath, SchoolConnection.defaultGradePagePath);
      expect(next.gradeQueryPath, SchoolConnection.defaultGradeQueryPath);
    }
  });

  test(
    'opening a configured root does not re-infer its deployment directory',
    () {
      final profile = SchoolConnection(
        name: '手动配置',
        baseUri: Uri.parse('https://old.example/prefix/xtgl/custom/'),
      );
      final model = SchoolAddressViewModel(initialProfile: profile);
      addTearDown(model.dispose);
      expect(model.submit(profile.name)!.baseUri, profile.baseUri);
    },
  );
}
