import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:zf_core/zf_core.dart';

const _connectTimeout = Duration(seconds: 15);
const _sendTimeout = Duration(seconds: 30);
const _receiveTimeout = Duration(seconds: 30);
const _minimumStatusCode = 100;
const _maximumStatusCode = 599;
const _cancelled = LoginFailure(LoginFailureCode.cancelled, '登录请求已取消');
const _invalidCookie = LoginFailure(
  LoginFailureCode.protocol,
  'Cookie 格式或所属域无效',
);

/// Owns a single account's HTTP client and cookie jar.
///
/// Injected [client] and [cookieJar] must also be exclusive to this instance.
/// Redirects are returned to the gateway without replaying a request body.
final class DioAuthTransport implements AuthTransport {
  DioAuthTransport({
    Dio? client,
    CookieJar? cookieJar,
    DateTime Function()? clock,
  }) : _client = client ?? Dio(),
       _cookieJar = cookieJar ?? CookieJar(),
       _clock = clock ?? DateTime.now;

  final Dio _client;
  final CookieJar _cookieJar;
  final DateTime Function() _clock;
  final CancelToken _cancelToken = CancelToken();
  bool _closed = false;
  int _cookieGeneration = 0;

  @override
  Future<AuthHttpResponse> send(AuthHttpRequest request) async {
    _ensureOpen();
    final generation = _cookieGeneration;
    final headers = _requestHeaders(request);
    final cookies = await cookiesFor(request.uri);
    _ensureGeneration(generation);
    if (cookies.isNotEmpty) {
      headers[HttpHeaders.cookieHeader] = cookies
          .map((cookie) => '${cookie.name}=${cookie.value}')
          .join('; ');
    }

    final Response<Object?> response;
    try {
      response = await _client.requestUri<Object?>(
        request.uri,
        data: request.method == 'POST' ? _encodeForm(request.form) : null,
        cancelToken: _cancelToken,
        options: Options(
          method: request.method,
          headers: headers,
          contentType: request.method == 'POST'
              ? Headers.formUrlEncodedContentType
              : null,
          responseType: ResponseType.bytes,
          followRedirects: false,
          maxRedirects: 0,
          validateStatus: (_) => true,
          connectTimeout: _connectTimeout,
          sendTimeout: _sendTimeout,
          receiveTimeout: _receiveTimeout,
        ),
      );
    } on DioException catch (error) {
      if (_closed || error.type == DioExceptionType.cancel) throw _cancelled;
      throw _mapNetworkFailure(error);
    }

    _ensureGeneration(generation);
    final status = response.statusCode;
    final body = response.data;
    if (status == null ||
        status < _minimumStatusCode ||
        status > _maximumStatusCode ||
        body is! List<int> ||
        body.any((byte) => byte < 0 || byte > 255)) {
      throw const LoginFailure(LoginFailureCode.protocol, '教务响应格式无效');
    }

    final incoming = _responseCookies(
      request.uri,
      response.headers[HttpHeaders.setCookieHeader] ?? const [],
    );
    _ensureGeneration(generation);
    await _cookieJar.saveFromResponse(request.uri, incoming);
    _ensureGeneration(generation);
    return AuthHttpResponse(
      uri: request.uri,
      statusCode: status,
      body: body,
      headers: response.headers.map,
    );
  }

  @override
  Future<void> replaceCookies(Uri origin, List<LoginCookie> cookies) async {
    _ensureOpen();
    _validateUri(origin);
    final converted = cookies
        .map((cookie) => _importCookie(origin, cookie))
        .toList(growable: false);
    final generation = ++_cookieGeneration;
    // Validate the complete import before replacing any existing account state.
    await _cookieJar.deleteAll();
    _ensureGeneration(generation);
    await _cookieJar.saveFromResponse(origin, converted);
    _ensureGeneration(generation);
  }

  @override
  Future<List<LoginCookie>> cookiesFor(Uri uri) async {
    _ensureOpen();
    _validateUri(uri);
    final cookies = await _cookieJar.loadForRequest(uri);
    _ensureOpen();
    final now = _clock().toUtc();
    return List<LoginCookie>.unmodifiable([
      for (final cookie in cookies)
        if (_matchesRequest(cookie, uri, now))
          LoginCookie(
            name: cookie.name,
            value: cookie.value,
            domain: cookie.domain,
            path: cookie.path,
            secure: cookie.secure,
            httpOnly: cookie.httpOnly,
            expiresAt: cookie.expires,
          ),
    ]);
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _cancelToken.cancel();
    _client.close(force: true);
  }

  Map<String, Object?> _requestHeaders(AuthHttpRequest request) {
    for (final key in [
      ...request.headers.keys,
      ..._client.options.headers.keys,
    ]) {
      if (key.toLowerCase() == HttpHeaders.cookieHeader) {
        throw const LoginFailure(
          LoginFailureCode.protocol,
          'Cookie 请求头必须由当前账号的会话统一生成',
        );
      }
    }
    return {
      for (final entry in request.headers.entries)
        if (request.method != 'POST' ||
            entry.key.toLowerCase() != HttpHeaders.contentTypeHeader)
          entry.key: entry.value,
    };
  }

  static String _encodeForm(List<MapEntry<String, String>> fields) => fields
      .map(
        (entry) =>
            '${Uri.encodeQueryComponent(entry.key)}='
            '${Uri.encodeQueryComponent(entry.value)}',
      )
      .join('&');

  List<Cookie> _responseCookies(Uri uri, List<String> headers) {
    final receivedAt = _clock().toUtc();
    try {
      return [
        for (final header in headers) _parseCookie(uri, header, receivedAt),
      ];
    } on FormatException {
      throw _invalidCookie;
    } on ArgumentError {
      throw _invalidCookie;
    }
  }

  static Cookie _parseCookie(Uri uri, String header, DateTime receivedAt) {
    if (!header.split(';').first.contains('=')) throw _invalidCookie;
    final cookie = Cookie.fromSetCookieValue(header);
    cookie.domain = _validatedDomain(uri, cookie.domain);
    cookie.path = _validatedPath(cookie.path, _responseDefaultPath(uri));
    final maxAge = cookie.maxAge;
    if (maxAge != null) {
      // Max-Age is relative to receipt, never to a later export or restore.
      cookie.expires = maxAge <= 0
          ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
          : receivedAt.add(Duration(seconds: maxAge));
      cookie.maxAge = null;
    }
    return cookie;
  }

  static Cookie _importCookie(Uri origin, LoginCookie source) {
    try {
      return Cookie(source.name, source.value)
        ..domain = _validatedDomain(origin, source.domain)
        ..path = _validatedPath(
          source.path,
          origin.path.isEmpty ? '/' : origin.path,
        )
        ..secure = source.secure
        ..httpOnly = source.httpOnly
        ..expires = source.expiresAt?.toUtc();
    } on FormatException {
      throw _invalidCookie;
    } on ArgumentError {
      throw _invalidCookie;
    }
  }

  static String? _validatedDomain(Uri origin, String? rawDomain) {
    if (rawDomain == null || rawDomain.isEmpty) return null;
    final domain = rawDomain.toLowerCase();
    final canonical = domain.startsWith('.') ? domain.substring(1) : domain;
    final host = origin.host.toLowerCase();
    final matches =
        host == canonical ||
        (InternetAddress.tryParse(host) == null &&
            host.endsWith('.$canonical'));
    if (canonical.isEmpty || canonical.endsWith('.') || !matches) {
      throw _invalidCookie;
    }
    return domain;
  }

  static String _validatedPath(String? path, String defaultPath) {
    if (path == null || path.isEmpty) return defaultPath;
    if (!path.startsWith('/') || path.contains(RegExp(r'[\x00-\x1f\x7f;]'))) {
      throw _invalidCookie;
    }
    return path;
  }

  static String _responseDefaultPath(Uri uri) {
    final lastSlash = uri.path.lastIndexOf('/');
    return lastSlash <= 0 ? '/' : uri.path.substring(0, lastSlash);
  }

  static bool _matchesRequest(Cookie cookie, Uri uri, DateTime now) {
    // cookie_jar 4.0.9 DefaultCookieJar._check uses an OR that admits Secure
    // cookies over HTTP and expired Secure cookies over HTTPS. Its
    // _isPathMatch also lowercases paths. Keep one jar and correct its output
    // here for both exports and sends; remove only with these tests passing.
    if (cookie.secure && uri.scheme != 'https') return false;
    final expiry = cookie.expires;
    if (expiry != null && !expiry.isAfter(now)) return false;
    if (cookie.maxAge != null && cookie.maxAge! <= 0) return false;
    final path = cookie.path ?? '/';
    final requestPath = uri.path.isEmpty ? '/' : uri.path;
    return requestPath == path ||
        (requestPath.startsWith(path) &&
            (path.endsWith('/') ||
                requestPath.substring(path.length).startsWith('/')));
  }

  static void _validateUri(Uri uri) {
    if (!['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw const LoginFailure(LoginFailureCode.protocol, '教务请求地址无效');
    }
  }

  static LoginFailure _mapNetworkFailure(DioException error) {
    if (error.type == DioExceptionType.badResponse) {
      final status = error.response?.statusCode;
      if (status != null) {
        return LoginFailure(
          status >= 500 ? LoginFailureCode.network : LoginFailureCode.protocol,
          '教务请求失败：学校返回 HTTP $status',
        );
      }
      return const LoginFailure(LoginFailureCode.protocol, '教务请求返回了无效状态');
    }
    if (error.error is FormatException || error.error is ArgumentError) {
      return const LoginFailure(LoginFailureCode.protocol, '教务响应格式无效');
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.transformTimeout => const LoginFailure(
        LoginFailureCode.network,
        '教务请求超时，请检查网络后重试',
      ),
      DioExceptionType.badCertificate => const LoginFailure(
        LoginFailureCode.network,
        '无法验证教务系统的安全连接',
      ),
      _ => const LoginFailure(
        LoginFailureCode.network,
        '无法连接教务系统，请检查网络或学校服务状态',
      ),
    };
  }

  void _ensureOpen() {
    if (_closed) throw _cancelled;
  }

  void _ensureGeneration(int generation) {
    _ensureOpen();
    if (generation != _cookieGeneration) throw _cancelled;
  }
}
