import 'package:test/test.dart';
import 'package:zf_core/src/auth/cookie_header_parser.dart';
import 'package:zf_core/src/auth/login_models.dart';

void main() {
  final baseUri = Uri.parse('https://jw.example/jwglxt/');
  final invalidHeader = throwsA(
    isA<LoginFailure>().having(
      (failure) => failure.code,
      'code',
      LoginFailureCode.protocol,
    ),
  );

  test('preserves equals signs and scopes a copied header to its school', () {
    final cookies = parseLoginCookies(
      'Cookie: JSESSIONID=test-session; token=a=b==; empty=',
      baseUri,
    );

    expect(cookies.map((cookie) => cookie.name), [
      'JSESSIONID',
      'token',
      'empty',
    ]);
    expect(cookies.map((cookie) => cookie.value), [
      'test-session',
      'a=b==',
      '',
    ]);
    expect(
      cookies.every(
        (cookie) =>
            cookie.domain == null && cookie.path == '/jwglxt/' && cookie.secure,
      ),
      isTrue,
    );
    expect(() => cookies.clear(), throwsUnsupportedError);
  });

  test('keeps HTTP cookie scope explicit without upgrading its scheme', () {
    final cookies = parseLoginCookies(
      'session=value;',
      Uri.parse('http://jw.example/'),
    );

    expect(cookies.single.secure, isFalse);
    expect(cookies.single.path, '/');
  });

  test('accepts a quoted cookie value without decoding its contents', () {
    final cookie = parseLoginCookies('value="a=b"', baseUri).single;

    expect(cookie.value, '"a=b"');
  });

  test('rejects duplicate names instead of silently choosing an account', () {
    expect(
      () => parseLoginCookies('session=one; session=two', baseUri),
      invalidHeader,
    );
  });

  test('rejects header injection and Set-Cookie attributes', () {
    for (final raw in [
      'session=one\r\nOther: header',
      'session=one; Path=/',
      'session=one; HttpOnly',
    ]) {
      expect(() => parseLoginCookies(raw, baseUri), invalidHeader);
    }
  });

  test('reports malformed input rather than dropping bad fields', () {
    for (final raw in [
      '',
      'Cookie:',
      'session=one; broken',
      '=value',
      'bad name=value',
      'session=中文',
    ]) {
      expect(() => parseLoginCookies(raw, baseUri), invalidHeader);
    }
  });
}
