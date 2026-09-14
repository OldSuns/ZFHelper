import 'package:test/test.dart';
import 'package:zf_core/src/auth/school_connection.dart';
import 'package:zf_core/src/auth/school_connection_codec.dart';

void main() {
  test('an explicit business root is not re-inferred from directory names', () {
    final profile = SchoolConnection(
      name: '配置中的学校',
      baseUri: Uri.parse('https://school.example/prefix/xtgl/custom/'),
    );
    expect(
      profile.baseUri.toString(),
      'https://school.example/prefix/xtgl/custom/',
    );
    expect(
      profile.loginUri.toString(),
      'https://school.example/prefix/xtgl/custom/xtgl/login_slogin.html',
    );
  });

  for (final scenario in [
    (address: 'https://one.example', base: 'https://one.example/'),
    (
      address: 'bare.example:8787/custom',
      base: 'https://bare.example:8787/custom/',
    ),
    (
      address: 'https://two.example/jwglxt',
      base: 'https://two.example/jwglxt/',
    ),
    (
      address: 'https://three.example/teaching/system/',
      base: 'https://three.example/teaching/system/',
    ),
    (
      address: 'https://four.example/jwglxt/xtgl/login_slogin.html',
      base: 'https://four.example/jwglxt/',
    ),
    (
      address: 'http://five.example:8080/education/xtgl/login_slogin.html?language=zh_CN',
      base: 'http://five.example:8080/education/',
    ),
    (
      address: 'https://six.example/prefix/jwglxt/kbcx/xskbcx_cxXsKb.html?ticket=synthetic-ticket#view',
      base: 'https://six.example/prefix/jwglxt/',
    ),
    (
      address: 'https://seven.example/custom/?redirect=other#fragment',
      base: 'https://seven.example/custom/',
    ),
  ]) {
    test('normalizes a generic deployment: ${scenario.address}', () {
      final profile = SchoolConnection.fromInput(
        name: ' 测试学校 ',
        address: ' ${scenario.address} ',
      );

      expect(profile.baseUri, Uri.parse(scenario.base));
      expect(
        profile.loginUri,
        Uri.parse('${scenario.base}xtgl/login_slogin.html'),
      );
      expect(
        profile.publicKeyUri,
        Uri.parse('${scenario.base}xtgl/login_getPublicKey.html'),
      );
      expect(profile.captchaUri, Uri.parse('${scenario.base}kaptcha'));
      expect(
        profile.accountUri,
        Uri.parse('${scenario.base}xtgl/index_cxYhxxIndex.html'),
      );
      expect(
        profile.gradePageUri,
        Uri.parse('${scenario.base}cjcx/cjcx_cxDgXscj.html?gnmkdm=N305005'),
      );
      expect(
        profile.gradeQueryUri,
        Uri.parse(
          '${scenario.base}cjcx/cjcx_cxDgXscj.html?doType=query&gnmkdm=N305005',
        ),
      );
    });
  }

  test(
    'allows a different origin only for the separate browser login entry',
    () {
      final profile = SchoolConnection.fromInput(
        name: '测试学校',
        address: 'https://teaching.example/deployment/',
        loginPath: ' login/form.html ',
        publicKeyPath: ' api/public-key ',
        captchaPath: ' api/captcha ',
        accountPath: ' api/account ',
        gradePagePath: ' results/index ',
        gradeQueryPath: ' results/query?doType=query ',
        webLoginAddress:
            ' https://identity.example/cas/login?service=teaching ',
      );

      expect(
        profile.browserUri,
        Uri.parse('https://identity.example/cas/login?service=teaching'),
      );
      expect(
        profile.loginUri,
        Uri.parse('https://teaching.example/deployment/login/form.html'),
      );
      expect(profile.gradePagePath, 'results/index');
      expect(profile.gradeQueryPath, 'results/query?doType=query');
      expect(
        [
          profile.loginUri,
          profile.publicKeyUri,
          profile.captchaUri,
          profile.accountUri,
          profile.gradePageUri,
          profile.gradeQueryUri,
        ].every((uri) => uri.origin == 'https://teaching.example'),
        isTrue,
      );
    },
  );

  test(
    'uses the native login entry when no separate browser entry is configured',
    () {
      final profile = SchoolConnection.fromInput(
        name: '学校',
        address: 'https://school.example/',
      );

      expect(profile.webLoginUri, isNull);
      expect(
        profile.browserUri,
        Uri.parse('https://school.example/xtgl/login_slogin.html'),
      );
    },
  );

  test('school identity uses the normalized deployment rather than its display name', () {
    final root = SchoolConnection.fromInput(
      name: '学校旧名称',
      address: 'https://one.example/jwglxt/',
    );
    final login = SchoolConnection.fromInput(
      name: '学校新名称',
      address: 'https://one.example/jwglxt/xtgl/login_slogin.html',
    );
    final other = SchoolConnection.fromInput(
      name: '学校旧名称',
      address: 'https://two.example/jwglxt/',
    );

    expect(root.school.id, login.school.id);
    expect(root.school.id, isNot(other.school.id));
  });

  test('rejects absolute and cross-origin native endpoints', () {
    for (final path in [
      'https://identity.example/login',
      '//identity.example/login',
      'javascript:invalid',
      '',
      '  ',
    ]) {
      expect(
        () => SchoolConnection(
          name: '测试学校',
          baseUri: Uri.parse('https://school.example/'),
          loginPath: path,
        ),
        throwsFormatException,
      );
      expect(
        () => SchoolConnection(
          name: '测试学校',
          baseUri: Uri.parse('https://school.example/'),
          gradePagePath: path,
        ),
        throwsFormatException,
      );
      expect(
        () => SchoolConnection(
          name: '测试学校',
          baseUri: Uri.parse('https://school.example/'),
          gradeQueryPath: path,
        ),
        throwsFormatException,
      );
    }
  });

  test(
    'school storage retains grade paths and migrates absent legacy keys',
    () {
      final profile = SchoolConnection(
        name: '测试学校',
        baseUri: Uri.parse('https://school.example/jwglxt/'),
        gradePagePath: 'results/index',
        gradeQueryPath: 'results/query?doType=query',
      );
      final restored = SchoolConnectionCodec.decode(
        SchoolConnectionCodec.encode(profile),
      );
      expect(restored.gradePageUri, profile.gradePageUri);
      expect(restored.gradeQueryUri, profile.gradeQueryUri);

      final legacy = SchoolConnectionCodec.toMap(profile)
        ..remove('gradePagePath')
        ..remove('gradeQueryPath');
      final migrated = SchoolConnectionCodec.fromMap(legacy);
      expect(migrated.gradePagePath, SchoolConnection.defaultGradePagePath);
      expect(migrated.gradeQueryPath, SchoolConnection.defaultGradeQueryPath);
      expect(migrated.school.id, profile.school.id);
    },
  );

  test('present invalid grade paths are not treated as legacy omissions', () {
    final profile = SchoolConnection(
      name: '测试学校',
      baseUri: Uri.parse('https://school.example/jwglxt/'),
    );
    for (final key in ['gradePagePath', 'gradeQueryPath']) {
      for (final invalid in [null, '', '  ', 42]) {
        final saved = SchoolConnectionCodec.toMap(profile)..[key] = invalid;
        expect(
          () => SchoolConnectionCodec.fromMap(saved),
          throwsFormatException,
          reason: '$key must reject $invalid',
        );
      }
    }
  });

  test('rejects invalid or ambiguous base addresses', () {
    for (final address in [
      'ftp://school.example/',
      'https://school.example/page.html',
      'https://user:synthetic@school.example/jwglxt/',
    ]) {
      expect(
        () => SchoolConnection.fromInput(name: '测试学校', address: address),
        throwsFormatException,
      );
    }
  });

  test('the constructor accepts only a canonical business root', () {
    for (final address in [
      'school.example/jwglxt/',
      'https://school.example/jwglxt/xtgl/login_slogin.html',
      'https://school.example/jwglxt/?ticket=synthetic-ticket',
      'https://school.example/jwglxt/#fragment',
    ]) {
      expect(
        () => SchoolConnection(name: '测试学校', baseUri: Uri.parse(address)),
        throwsFormatException,
      );
    }
    expect(
      SchoolConnection(
        name: '测试学校',
        baseUri: Uri.parse('https://school.example/custom'),
      ).baseUri,
      Uri.parse('https://school.example/custom/'),
    );
  });

  test('rejects unsafe or incomplete browser entry schemes', () {
    for (final address in [
      'javascript:invalid',
      '/cas/login',
      'ftp://identity.example/',
      'https://user:synthetic@identity.example/',
    ]) {
      expect(
        () => SchoolConnection.fromInput(
          name: '测试学校',
          address: 'https://school.example/',
          webLoginAddress: address,
        ),
        throwsFormatException,
      );
    }
  });
}
