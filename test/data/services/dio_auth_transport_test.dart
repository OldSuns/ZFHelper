import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zf_core/zf_core.dart';
import 'package:zfhelper/data/services/dio_auth_transport.dart';

final _base = Uri.parse('https://school.example/jwglxt/');

void main() {
  group('HTTP requests', () {
    test(
      'encodes UTF-8 form fields and preserves duplicate mm values',
      () async {
        final adapter = _Adapter(
          (_, _) => ResponseBody.fromBytes([0, 255], 201),
        );
        final transport = _transport(adapter);
        final uri = _base.resolve('xtgl/login_slogin.html?time=123');
        final response = await transport.send(
          AuthHttpRequest.form(
            uri,
            fields: const [
              MapEntry('yhm', '学生 +&='),
              MapEntry('mm', 'first+/='),
              MapEntry('mm', 'second value'),
              MapEntry('empty', ''),
            ],
            headers: const {'Referer': 'https://school.example/jwglxt/'},
          ),
        );

        final exchange = adapter.exchanges.single;
        expect(exchange.options.method, 'POST');
        expect(exchange.options.uri, uri);
        expect(
          exchange.options.contentType,
          startsWith('application/x-www-form-urlencoded'),
        );
        expect(
          utf8.decode(exchange.body),
          'yhm=%E5%AD%A6%E7%94%9F+%2B%26%3D&mm=first%2B%2F%3D&'
          'mm=second+value&empty=',
        );
        expect(response.statusCode, 201);
        expect(response.body, [0, 255]);
        expect(response.uri, uri);
      },
    );

    test('returns 302 without replay and retains its Set-Cookie', () async {
      final adapter = _Adapter(
        (_, _) => ResponseBody.fromString(
          '',
          302,
          headers: {
            'location': ['/jwglxt/xtgl/index_initMenu.html'],
            'set-cookie': ['SID=redirect-session; Path=/jwglxt/; HttpOnly'],
          },
        ),
      );
      final transport = _transport(adapter);
      final response = await transport.send(
        AuthHttpRequest.form(
          _base.resolve('xtgl/login_slogin.html'),
          fields: const [MapEntry('mm', 'synthetic-ciphertext')],
        ),
      );

      expect(adapter.exchanges, hasLength(1));
      expect(adapter.exchanges.single.options.followRedirects, isFalse);
      expect(adapter.exchanges.single.options.maxRedirects, 0);
      expect(response.statusCode, 302);
      expect(response.header('Location'), '/jwglxt/xtgl/index_initMenu.html');
      final cookies = await transport.cookiesFor(_base);
      expect(cookies.single.name, 'SID');
      expect(cookies.single.value, 'redirect-session');
      expect(cookies.single.httpOnly, isTrue);
    });

    test(
      'GET has no body and HTTP failure status remains a response',
      () async {
        final adapter = _Adapter(
          (_, _) => ResponseBody.fromString('denied', 403),
        );
        final transport = _transport(adapter);
        final response = await transport.send(AuthHttpRequest.get(_base));
        expect(adapter.exchanges.single.body, isEmpty);
        expect(response.statusCode, 403);
        expect(response.text, 'denied');
      },
    );

    for (final header in ['Cookie', 'cookie', 'cOoKiE']) {
      test('rejects explicit $header before issuing any request', () async {
        final adapter = _Adapter((_, _) => ResponseBody.fromString('', 200));
        final transport = _transport(adapter);
        await expectLater(
          transport.send(
            AuthHttpRequest.get(_base, headers: {header: 'SID=do-not-send'}),
          ),
          throwsA(_failure(LoginFailureCode.protocol)),
        );
        expect(adapter.exchanges, isEmpty);
      });
    }

    test('rejects Cookie in an injected client default header', () async {
      final adapter = _Adapter((_, _) => ResponseBody.fromString('', 200));
      final client = Dio()..httpClientAdapter = adapter;
      client.options.headers['Cookie'] = 'SID=do-not-send';
      final transport = DioAuthTransport(client: client);
      addTearDown(transport.close);
      await expectLater(
        transport.send(AuthHttpRequest.get(_base)),
        throwsA(_failure(LoginFailureCode.protocol)),
      );
      expect(adapter.exchanges, isEmpty);
    });
  });

  group('Cookie scope and isolation', () {
    test(
      'unknown domain is host-only and unknown path is the business root',
      () async {
        final adapter = _Adapter((_, _) => ResponseBody.fromString('', 200));
        final transport = _transport(adapter);
        await transport.replaceCookies(_base, const [
          LoginCookie(name: 'SID', value: 'only-this-host'),
        ]);

        final cookies = await transport.cookiesFor(_base.resolve('xtgl/page'));
        expect(cookies.single.domain, isNull);
        expect(cookies.single.path, '/jwglxt/');
        expect(
          await transport.cookiesFor(Uri.parse('https://school.example/')),
          isEmpty,
        );
        expect(
          await transport.cookiesFor(
            Uri.parse('https://sub.school.example/jwglxt/'),
          ),
          isEmpty,
        );
        await transport.send(AuthHttpRequest.get(_base.resolve('xtgl/page')));
        expect(
          _cookieHeader(adapter.exchanges.single.options),
          'SID=only-this-host',
        );
      },
    );

    test('secure cookies never leave over HTTP in exports or sends', () async {
      final adapter = _Adapter((_, _) => ResponseBody.fromString('', 200));
      final transport = _transport(adapter);
      await transport.replaceCookies(_base, const [
        LoginCookie(name: 'SECRET', value: 'secure', secure: true),
        LoginCookie(name: 'NORMAL', value: 'plain'),
      ]);
      final httpUri = _base.replace(scheme: 'http');
      expect((await transport.cookiesFor(httpUri)).map((c) => c.name), [
        'NORMAL',
      ]);
      await transport.send(AuthHttpRequest.get(httpUri));
      expect(_cookieHeader(adapter.exchanges.single.options), 'NORMAL=plain');
      expect(
        (await transport.cookiesFor(_base)).map((c) => c.name),
        containsAll(['SECRET', 'NORMAL']),
      );
    });

    test('path matching remains case sensitive with path boundaries', () async {
      final adapter = _Adapter((_, _) => ResponseBody.fromString('', 200));
      final transport = _transport(adapter);
      await transport.replaceCookies(_base, const [
        LoginCookie(name: 'SID', value: 'upper', path: '/JWGLXT'),
      ]);
      expect(await transport.cookiesFor(_base.resolve('page')), isEmpty);
      expect(
        await transport.cookiesFor(_base.resolve('/JWGLXT-other')),
        isEmpty,
      );
      expect(
        (await transport.cookiesFor(_base.resolve('/JWGLXT/page')))
            .single
            .value,
        'upper',
      );
      await transport.send(AuthHttpRequest.get(_base.resolve('page')));
      expect(_cookieHeader(adapter.exchanges.single.options), isNull);
    });

    test(
      'keeps same-name cookies at distinct paths and their attributes',
      () async {
        final adapter = _Adapter((_, _) => ResponseBody.fromString('', 200));
        final transport = _transport(adapter);
        await transport.replaceCookies(_base, const [
          LoginCookie(name: 'SID', value: 'root', path: '/', httpOnly: false),
          LoginCookie(
            name: 'SID',
            value: 'app',
            path: '/jwglxt/',
            secure: true,
          ),
        ]);
        final cookies = await transport.cookiesFor(_base);
        expect(cookies, hasLength(2));
        expect(cookies.map((c) => (c.value, c.path, c.secure, c.httpOnly)), [
          ('app', '/jwglxt/', true, true),
          ('root', '/', false, false),
        ]);
        await transport.send(AuthHttpRequest.get(_base));
        expect(
          _cookieHeader(adapter.exchanges.single.options),
          'SID=app; SID=root',
        );
      },
    );

    test('retains parent-domain cookies only for matching hosts', () async {
      final transport = _transport(
        _Adapter((_, _) => ResponseBody.fromString('', 200)),
      );
      await transport.replaceCookies(_base, const [
        LoginCookie(name: 'SHARED', value: 'parent', domain: '.school.example'),
      ]);
      expect(
        (await transport.cookiesFor(
          Uri.parse('https://child.school.example/jwglxt/'),
        )).single.domain,
        '.school.example',
      );
      expect(
        await transport.cookiesFor(
          Uri.parse('https://notschool.example/jwglxt/'),
        ),
        isEmpty,
      );
    });

    test(
      'another instance replacing its account never clears this jar',
      () async {
        final first = _transport(
          _Adapter((_, _) => ResponseBody.fromString('', 200)),
        );
        final second = _transport(
          _Adapter((_, _) => ResponseBody.fromString('', 200)),
        );
        await first.replaceCookies(_base, const [
          LoginCookie(name: 'SID', value: 'first-account'),
        ]);
        await second.replaceCookies(_base, const [
          LoginCookie(name: 'SID', value: 'second-account'),
        ]);
        await second.replaceCookies(_base, const []);
        expect((await first.cookiesFor(_base)).single.value, 'first-account');
        expect(await second.cookiesFor(_base), isEmpty);
      },
    );

    test(
      'rejects an entire foreign-domain import without partial replacement',
      () async {
        final transport = _transport(
          _Adapter((_, _) => ResponseBody.fromString('', 200)),
        );
        await transport.replaceCookies(_base, const [
          LoginCookie(name: 'SID', value: 'original'),
        ]);
        await expectLater(
          transport.replaceCookies(_base, const [
            LoginCookie(name: 'GOOD', value: 'partial'),
            LoginCookie(name: 'BAD', value: 'secret', domain: 'other.example'),
          ]),
          throwsA(_failure(LoginFailureCode.protocol)),
        );
        expect((await transport.cookiesFor(_base)).single.value, 'original');
      },
    );

    test('rejects a response cookie for a foreign domain', () async {
      final transport = _transport(
        _Adapter(
          (_, _) => ResponseBody.fromString(
            '',
            200,
            headers: {
              'set-cookie': ['SID=secret; Domain=other.example'],
            },
          ),
        ),
      );
      await expectLater(
        transport.send(AuthHttpRequest.get(_base)),
        throwsA(_failure(LoginFailureCode.protocol)),
      );
      expect(await transport.cookiesFor(_base), isEmpty);
    });

    test(
      'missing response Path uses the response directory, not the app root',
      () async {
        final transport = _transport(
          _Adapter(
            (_, _) => ResponseBody.fromString(
              '',
              200,
              headers: {
                'set-cookie': ['SID=directory-only'],
              },
            ),
          ),
        );
        final loginUri = _base.resolve('xtgl/login_slogin.html');
        await transport.send(AuthHttpRequest.get(loginUri));
        expect(
          (await transport.cookiesFor(loginUri)).single.path,
          '/jwglxt/xtgl',
        );
        expect(
          await transport.cookiesFor(_base.resolve('other/page')),
          isEmpty,
        );
      },
    );
  });

  group('Expiry', () {
    test(
      'Max-Age becomes a receipt-based expiry and restore cannot extend it',
      () async {
        final receipt = DateTime.now().toUtc();
        var now = receipt;
        final first = _transport(
          _Adapter(
            (_, _) => ResponseBody.fromString(
              '',
              200,
              headers: {
                'set-cookie': [
                  'SID=short-lived; Path=/jwglxt/; Max-Age=60; '
                      'Expires=Thu, 01 Jan 1970 00:00:00 GMT',
                ],
              },
            ),
          ),
          clock: () => now,
        );
        await first.send(AuthHttpRequest.get(_base));
        final exported = await first.cookiesFor(_base);
        expect(
          exported.single.expiresAt,
          receipt.add(const Duration(seconds: 60)),
        );

        now = receipt.add(const Duration(seconds: 20));
        final restored = _transport(
          _Adapter((_, _) => ResponseBody.fromString('', 200)),
          clock: () => now,
        );
        await restored.replaceCookies(_base, exported);
        expect(
          (await restored.cookiesFor(_base)).single.expiresAt,
          exported.single.expiresAt,
        );
        now = receipt.add(const Duration(seconds: 61));
        expect(await first.cookiesFor(_base), isEmpty);
        expect(await restored.cookiesFor(_base), isEmpty);
      },
    );

    test(
      'expired Secure cookies cannot pass the upstream OR condition',
      () async {
        final jar = CookieJar();
        final cookie = Cookie('SID', 'expired')
          ..path = '/jwglxt/'
          ..secure = true
          ..expires = DateTime.now().add(const Duration(hours: 1));
        await jar.saveFromResponse(_base, [cookie]);
        // Simulates expiry of a previously accepted cookie without sleeping.
        cookie.expires = DateTime.now().subtract(const Duration(seconds: 1));
        final adapter = _Adapter((_, _) => ResponseBody.fromString('', 200));
        final transport = _transport(adapter, cookieJar: jar);
        expect(await transport.cookiesFor(_base), isEmpty);
        await transport.send(AuthHttpRequest.get(_base));
        expect(_cookieHeader(adapter.exchanges.single.options), isNull);
      },
    );

    test(
      'rememberMe is retained normally and removed by its actual deletion',
      () async {
        var delete = false;
        final transport = _transport(
          _Adapter(
            (_, _) => ResponseBody.fromString(
              '',
              200,
              headers: {
                'set-cookie': [
                  delete
                      ? 'rememberMe=deleteMe; Path=/jwglxt/; Max-Age=0'
                      : 'rememberMe=keep-me; Path=/jwglxt/; Max-Age=3600',
                ],
              },
            ),
          ),
        );
        await transport.send(AuthHttpRequest.get(_base));
        expect((await transport.cookiesFor(_base)).single.value, 'keep-me');
        delete = true;
        await transport.send(AuthHttpRequest.get(_base));
        expect(await transport.cookiesFor(_base), isEmpty);
      },
    );
  });

  group('Failure and lifecycle', () {
    for (final type in DioExceptionType.values) {
      test(
        '$type is mapped without leaking request or exception contents',
        () async {
          const secret = 'synthetic-password-cookie-do-not-display';
          final transport = _transport(
            _Adapter((options, _) {
              throw DioException(
                requestOptions: options,
                type: type,
                message: secret,
                error: const SocketException(secret),
              );
            }),
          );
          final expected = type == DioExceptionType.cancel
              ? LoginFailureCode.cancelled
              : type == DioExceptionType.badResponse
              ? LoginFailureCode.protocol
              : LoginFailureCode.network;
          await expectLater(
            transport.send(
              AuthHttpRequest.form(
                _base,
                fields: const [MapEntry('mm', secret)],
                headers: const {'Authorization': secret},
              ),
            ),
            throwsA(
              _failure(expected).having(
                (error) => error.toString(),
                'public error',
                isNot(contains(secret)),
              ),
            ),
          );
        },
      );
    }

    test('maps an HTTP error response to its status code', () async {
      final transport = _transport(
        _Adapter((options, _) {
          throw DioException.badResponse(
            statusCode: 503,
            requestOptions: options,
            response: Response<Object?>(
              requestOptions: options,
              statusCode: 503,
              data: 'server-error',
            ),
          );
        }),
      );
      await expectLater(
        transport.send(AuthHttpRequest.get(_base)),
        throwsA(
          _failure(
            LoginFailureCode.network,
          ).having((error) => error.message, 'message', '教务请求失败：学校返回 HTTP 503'),
        ),
      );
    });

    test(
      'malformed response cookies fail explicitly without exposing them',
      () async {
        final transport = _transport(
          _Adapter(
            (_, _) => ResponseBody.fromString(
              '',
              200,
              headers: {
                'set-cookie': ['bad name=synthetic-secret'],
              },
            ),
          ),
        );
        await expectLater(
          transport.send(AuthHttpRequest.get(_base)),
          throwsA(
            _failure(LoginFailureCode.protocol).having(
              (error) => error.toString(),
              'public error',
              isNot(contains('synthetic-secret')),
            ),
          ),
        );
        expect(await transport.cookiesFor(_base), isEmpty);
      },
    );

    test('a malformed status is a protocol failure', () async {
      final transport = _transport(
        _Adapter((_, _) => ResponseBody.fromString('not-http', 0)),
      );
      await expectLater(
        transport.send(AuthHttpRequest.get(_base)),
        throwsA(_failure(LoginFailureCode.protocol)),
      );
    });

    test('a non-byte response is a protocol failure', () async {
      final client = Dio();
      client.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response<Object?>(
                requestOptions: options,
                data: 'unexpected-text',
                statusCode: 200,
              ),
            );
          },
        ),
      );
      final transport = DioAuthTransport(client: client);
      addTearDown(transport.close);
      await expectLater(
        transport.send(AuthHttpRequest.get(_base)),
        throwsA(_failure(LoginFailureCode.protocol)),
      );
    });

    test(
      'close cancels in-flight work and late Set-Cookie cannot reach the jar',
      () async {
        final response = Completer<ResponseBody>();
        final started = Completer<void>();
        final jar = CookieJar();
        final adapter = _Adapter((_, _) {
          started.complete();
          return response.future;
        });
        final transport = _transport(adapter, cookieJar: jar);
        await transport.replaceCookies(_base, const [
          LoginCookie(name: 'SID', value: 'before-close'),
        ]);
        final request = transport.send(AuthHttpRequest.get(_base));
        final assertion = expectLater(
          request,
          throwsA(_failure(LoginFailureCode.cancelled)),
        );
        await started.future;
        transport.close();
        transport.close();
        await assertion;
        expect(adapter.closed, isTrue);
        expect(adapter.forceClosed, isTrue);
        await adapter.cancelled.future;
        response.complete(
          ResponseBody.fromString(
            '',
            200,
            headers: {
              'set-cookie': ['SID=late-response; Path=/jwglxt/'],
            },
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect((await jar.loadForRequest(_base)).single.value, 'before-close');
        await expectLater(
          transport.send(AuthHttpRequest.get(_base)),
          throwsA(_failure(LoginFailureCode.cancelled)),
        );
        await expectLater(
          transport.cookiesFor(_base),
          throwsA(_failure(LoginFailureCode.cancelled)),
        );
        await expectLater(
          transport.replaceCookies(_base, const []),
          throwsA(_failure(LoginFailureCode.cancelled)),
        );
      },
    );

    test(
      'a response from before replacement cannot overwrite imported cookies',
      () async {
        final response = Completer<ResponseBody>();
        final started = Completer<void>();
        final transport = _transport(
          _Adapter((_, _) {
            started.complete();
            return response.future;
          }),
        );
        final request = transport.send(AuthHttpRequest.get(_base));
        final assertion = expectLater(
          request,
          throwsA(_failure(LoginFailureCode.cancelled)),
        );
        await started.future;
        await transport.replaceCookies(_base, const [
          LoginCookie(name: 'SID', value: 'new-account'),
        ]);
        response.complete(
          ResponseBody.fromString(
            '',
            200,
            headers: {
              'set-cookie': ['SID=previous-account; Path=/jwglxt/'],
            },
          ),
        );
        await assertion;
        expect((await transport.cookiesFor(_base)).single.value, 'new-account');
      },
    );
  });
}

DioAuthTransport _transport(
  _Adapter adapter, {
  CookieJar? cookieJar,
  DateTime Function()? clock,
}) {
  final transport = DioAuthTransport(
    client: Dio()..httpClientAdapter = adapter,
    cookieJar: cookieJar,
    clock: clock,
  );
  addTearDown(transport.close);
  return transport;
}

TypeMatcher<LoginFailure> _failure(LoginFailureCode code) =>
    isA<LoginFailure>().having((failure) => failure.code, 'code', code);

String? _cookieHeader(RequestOptions options) {
  for (final entry in options.headers.entries) {
    if (entry.key.toLowerCase() == 'cookie') return entry.value as String?;
  }
  return null;
}

typedef _Responder = FutureOr<ResponseBody> Function(
  RequestOptions options,
  List<int> body,
);

final class _Exchange {
  const _Exchange(this.options, this.body);
  final RequestOptions options;
  final List<int> body;
}

final class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final _Responder respond;
  final List<_Exchange> exchanges = [];
  final Completer<void> cancelled = Completer<void>();
  bool closed = false;
  bool forceClosed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        body.addAll(chunk);
      }
    }
    cancelFuture?.then((_) {
      if (!cancelled.isCompleted) cancelled.complete();
    });
    exchanges.add(_Exchange(options, List<int>.unmodifiable(body)));
    return respond(options, body);
  }

  @override
  void close({bool force = false}) {
    closed = true;
    forceClosed = force;
  }
}
