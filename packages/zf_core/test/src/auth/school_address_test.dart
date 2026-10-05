import 'package:test/test.dart';
import 'package:zf_core/zf_core.dart';

void main() {
  group('recognizeSchoolAddress', () {
    for (final scenario in <({String input, String expected})>[
      (input: 'jw.school.example', expected: 'https://jw.school.example/'),
      (
        input: '  jw.school.example/custom  ',
        expected: 'https://jw.school.example/custom/',
      ),
      (
        input: 'jw.school.example:8443/jwglxt',
        expected: 'https://jw.school.example:8443/jwglxt/',
      ),
      (
        input: '//jw.school.example:8443/jwglxt/xtgl/login_slogin.html',
        expected: 'https://jw.school.example:8443/jwglxt/',
      ),
      (
        input: 'http://jw.school.example:8080/jwglxt',
        expected: 'http://jw.school.example:8080/jwglxt/',
      ),
      (
        input: 'https://jw.school.example/jwglxt/xtgl/login_slogin.html',
        expected: 'https://jw.school.example/jwglxt/',
      ),
      (
        input:
            'https://jw.school.example/prefix/jwglxt/xtgl/index_initMenu.html',
        expected: 'https://jw.school.example/prefix/jwglxt/',
      ),
      (
        input: 'https://jw.school.example/custom/xtgl/login_slogin.html',
        expected: 'https://jw.school.example/custom/',
      ),
      (
        input: 'https://jw.school.example/xtgl/login_slogin.html',
        expected: 'https://jw.school.example/',
      ),
      (
        input: 'https://jw.school.example/custom',
        expected: 'https://jw.school.example/custom/',
      ),
      (
        input: 'https://jw.school.example/a/custom/root/',
        expected: 'https://jw.school.example/a/custom/root/',
      ),
      (
        input: 'https://jw.school.example/a/custom/root',
        expected: 'https://jw.school.example/a/custom/root/',
      ),
      (
        input: 'https://jw.school.example/prefix/jwglxt/custom/kbcx/page.html',
        expected: 'https://jw.school.example/prefix/jwglxt/custom/',
      ),
      (
        input: 'https://jw.school.example/jwxt/cjcx/cjcx_cxDgXscj.html?gnmkdm=N305005',
        expected: 'https://jw.school.example/jwxt/',
      ),
      (
        input: 'http://jw.school.example/jwxs/kbcx/xskbcx_cxXsKb.html?gnmkdm=N253508#table',
        expected: 'http://jw.school.example/jwxs/',
      ),
      (
        input: 'https://jw.school.example/prefix/jw/xsxk/zzxkyzb_cxZzxkYzbIndex.html',
        expected: 'https://jw.school.example/prefix/jw/',
      ),
      (
        input: 'https://jw.school.example/custom/xsxy/student.html',
        expected: 'https://jw.school.example/custom/',
      ),
      (
        input: 'https://jw.school.example/jwglxt/unknown-page.html',
        expected: 'https://jw.school.example/jwglxt/',
      ),
      (
        input: 'https://jw.school.example/a/../custom/xtgl/login_slogin.html',
        expected: 'https://jw.school.example/custom/',
      ),
      (
        input: 'HTTPS://JW.SCHOOL.EXAMPLE:443/JWGLXT/XTGL/login_slogin.html',
        expected: 'https://jw.school.example/JWGLXT/',
      ),
      (
        input: '10.0.2.2:8787/jwglxt/xtgl/login_slogin.html',
        expected: 'https://10.0.2.2:8787/jwglxt/',
      ),
      (
        input: 'http://127.0.0.1:8787/jwglxt/',
        expected: 'http://127.0.0.1:8787/jwglxt/',
      ),
      (input: 'localhost', expected: 'https://localhost/'),
      (
        input: 'localhost:8787/custom',
        expected: 'https://localhost:8787/custom/',
      ),
      (
        input: '[::1]:8787/jwglxt/xtgl/login_slogin.html',
        expected: 'https://[::1]:8787/jwglxt/',
      ),
      (
        input: 'http://[2001:db8::1]:8080/custom/cjcx/grades.html',
        expected: 'http://[2001:db8::1]:8080/custom/',
      ),
      (
        input: '2001:db8::1/custom/xtgl/login_slogin.html',
        expected: 'https://[2001:db8::1]/custom/',
      ),
      (input: '::1', expected: 'https://[::1]/'),
      (
        input: 'https://[::ffff:192.0.2.1]/jwglxt/',
        expected: 'https://[::ffff:192.0.2.1]/jwglxt/',
      ),
      (
        input: '教务.例子.中国/jwglxt/xtgl/login_slogin.html',
        expected: 'https://教务.例子.中国/jwglxt/',
      ),
      (
        input: 'https://xn--fsqu00a.xn--0zwm56d/custom/',
        expected: 'https://xn--fsqu00a.xn--0zwm56d/custom/',
      ),
      (
        input: 'https://school.example/学校/custom/xtgl/login_slogin.html',
        expected: 'https://school.example/学校/custom/',
      ),
    ]) {
      test('recognizes ${scenario.input}', () {
        final recognized = recognizeSchoolAddress(scenario.input);

        expect(recognized, Uri.parse(scenario.expected));
        expect(recognized.hasQuery, isFalse);
        expect(recognized.hasFragment, isFalse);
        expect(recognized.userInfo, isEmpty);
        expect(recognizeSchoolAddress(recognized.toString()), recognized);
        expect(
          SchoolConnection(name: '测试学校', baseUri: recognized).baseUri,
          recognized,
        );
      });
    }

    for (final directory in ['jwglxt', 'jwxt', 'jwxs', 'jw']) {
      test('keeps the prefix of deployment $directory', () {
        expect(
          recognizeSchoolAddress(
            'https://school.example/a/b/$directory/pages/portal.html',
          ),
          Uri.parse('https://school.example/a/b/$directory/'),
        );
      });
    }

    test(
      'never transfers authentication tickets into a normalized address',
      () {
        final root = recognizeSchoolAddress(
          'https://school.example/custom/kbcx/page.html?ticket=synthetic-ticket&service=https%3A%2F%2Fother.example%2F#token=synthetic-fragment',
        );

        expect(root.toString(), 'https://school.example/custom/');
        expect(root.toString(), isNot(contains('synthetic')));
      },
    );

    test(
      'does not inherit path or protocol guesses from a previous school',
      () {
        final first = recognizeSchoolAddress(
          'http://one.example/jwglxt/xtgl/login_slogin.html',
        );
        final second = recognizeSchoolAddress('two.example');
        final third = recognizeSchoolAddress(
          'https://three.example/custom/cjcx/grades.html',
        );

        expect(first, Uri.parse('http://one.example/jwglxt/'));
        expect(second, Uri.parse('https://two.example/'));
        expect(third, Uri.parse('https://three.example/custom/'));
        expect(recognizeSchoolAddress(first.toString()), first);
      },
    );

    for (final (index, input) in [
      '',
      '   ',
      '这不是网址',
      'not a website',
      '/jwglxt/',
      'example',
      'ftp://school.example/',
      'file:///tmp/private',
      'javascript:alert(1)',
      'mailto:student@school.example',
      'http:school.example',
      'https://school.example:0/',
      'school.example:65536/jwglxt/',
      'https://school.example:-1/',
      'school.example:invalid/',
      'https://school.example:/',
      'https://[::1]:99999/',
      'https://[2001:db8::1/',
      'https://[not-ip]/',
      'https://999.1.1.1/',
      'https://127.0.1/',
      'https://-school.example/',
      'https://school..example/',
      r'https://school.example\jwglxt\xtgl\login_slogin.html',
      'https://school.example/jwglxt/\n',
      'https://school.example/jwglxt/\u0000',
      'https://school.example/custom%5cpath/xtgl/login_slogin.html',
      'https://school.example/custom%0dpath/xtgl/login_slogin.html',
      'https://school.example/custom%2froot/xtgl/login_slogin.html',
      'https://school.example/unrecognized.html?ticket=synthetic-ticket',
      'https://school.example/custom/unknown.jsp#synthetic-fragment',
    ].indexed) {
      test('rejects invalid or ambiguous input $index without exposing it', () {
        expect(
          () => recognizeSchoolAddress(input),
          throwsA(
            isA<FormatException>()
                .having((error) => error.source, 'source', isNull)
                .having((error) => error.offset, 'offset', isNull)
                .having(
                  (error) => error.message,
                  'message',
                  isNot(contains('synthetic')),
                ),
          ),
        );
      });
    }

    for (final (index, input) in [
      'https://synthetic-user:synthetic-password@school.example/jwglxt/?ticket=synthetic-ticket',
      'https://@school.example/jwglxt/?ticket=synthetic-ticket',
      'https://school.example:bad-port/?ticket=synthetic-ticket',
    ].indexed) {
      test('redacts credentials and tickets for invalid address $index', () {
        try {
          recognizeSchoolAddress(input);
          fail('Expected an invalid address to be rejected.');
        } on FormatException catch (error) {
          expect(error.source, isNull);
          expect(error.toString(), isNot(contains('synthetic')));
          expect(error.toString(), isNot(contains('bad-port')));
          expect(RegExp(r'[\u4e00-\u9fff]').hasMatch(error.message), isTrue);
        }
      });
    }

    for (final path in [
      '/cas/login',
      '/authserver/login',
      '/prefix/CAS/login.html',
    ]) {
      test('asks for a post-login teaching address for $path', () {
        expect(
          () => recognizeSchoolAddress(
            'https://identity.example$path?ticket=synthetic-ticket',
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('进入教务系统'),
            ),
          ),
        );
      });
    }
  });
}
