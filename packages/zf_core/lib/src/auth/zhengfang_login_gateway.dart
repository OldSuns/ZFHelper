import 'dart:convert';
import 'dart:typed_data';

import 'authenticated_read_client.dart';
import 'login_gateway.dart';
import 'login_html_parser.dart';
import 'login_models.dart';
import 'school_connection.dart';

/// Performs one school's standard Zhengfang login using an isolated transport.
///
/// Authentication steps are sequential because tokens and captcha images belong
/// to the same attempt. Verified read-only queries share the transport and may
/// run concurrently. A redirect alone never establishes a session.
final class ZhengfangLoginGateway
    implements LoginGateway, AuthenticatedReadClient {
  ZhengfangLoginGateway({
    required this._profile,
    required this._transport,
    required this._cipher,
    required this._clock,
  });

  static const _maxRedirects = 3;
  static const _redirectCodes = {301, 302, 303, 307, 308};

  final SchoolConnection _profile;
  final AuthTransport _transport;
  final PasswordCipher _cipher;
  final DateTime Function() _clock;
  _PendingPasswordLogin? _pending;
  bool _closed = false;
  bool _busy = false;
  bool _hasVerifiedIdentity = false;

  @override
  Future<LoginStep> loginPassword(LoginCredentials credentials) =>
      _operation(() async {
        _pending = null;
        _hasVerifiedIdentity = false;
        await _transport.replaceCookies(_profile.baseUri, const []);
        _ensureOpen();
        final response = await _get(_profile.loginUri);
        _requireSuccess(response, '登录页面');
        final document = parseLoginDocument(response);
        final notice = classifyLoginPage(document);
        final form = parsePasswordForm(document, response.uri, _profile);
        _pending = _PendingPasswordLogin(credentials, form);
        if (form.hasVisibleCaptcha || notice.requiresCaptcha) {
          return CaptchaRequired(image: await _loadCaptcha());
        }
        return _postPassword('');
      });

  @override
  Future<LoginStep> submitCaptcha(String captcha) => _operation(() async {
    if (captcha.trim().isEmpty) {
      throw const LoginFailure(LoginFailureCode.captcha, '请输入验证码');
    }
    _requirePending();
    return _postPassword(captcha.trim());
  });

  @override
  Future<Uint8List> refreshCaptcha() => _operation(_loadCaptcha);

  @override
  Future<LoginSession> importCookies(
    List<LoginCookie> cookies, {
    String usernameHint = '',
  }) => _operation(() async {
    _pending = null;
    _hasVerifiedIdentity = false;
    if (cookies.isEmpty) {
      throw const LoginFailure(
        LoginFailureCode.expired,
        '没有可验证的教务 Cookie，请先完成登录',
      );
    }
    await _transport.replaceCookies(_profile.baseUri, cookies);
    _ensureOpen();
    return _verify(usernameHint);
  });

  @override
  Future<LoginSession> verifySession({String usernameHint = ''}) =>
      _operation(() async {
        final session = await _verify(usernameHint);
        _pending = null;
        return session;
      });

  @override
  Future<List<LoginCookie>> exportCookies() async {
    _ensureOpen();
    final cookies = await _transport.cookiesFor(_profile.accountUri);
    _ensureOpen();
    return cookies;
  }

  @override
  Future<AuthHttpResponse> sendRead(AuthHttpRequest request) async {
    _ensureOpen();
    if (!_hasVerifiedIdentity) {
      throw const LoginFailure(LoginFailureCode.expired, '请先核验教务登录状态');
    }
    final response = await _followRedirects(
      request,
      sessionRejectedBy: _isLoginUri,
    );
    if (response.statusCode == 401 || _isLoginUri(response.uri)) {
      throw const LoginFailure(LoginFailureCode.expired, '教务登录状态已失效，请重新登录');
    }
    return response;
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _pending = null;
    _hasVerifiedIdentity = false;
    _transport.close();
  }

  Future<LoginStep> _postPassword(String captcha) async {
    final pending = _requirePending();
    final encrypted = await _encryptPassword(pending.credentials.password);
    final fields = [
      ...pending.form.hiddenFields,
      MapEntry('yhm', pending.credentials.username),
      for (var index = 0; index < pending.form.passwordFieldCount; index++)
        MapEntry('mm', encrypted),
      if (captcha.isNotEmpty) MapEntry('yzm', captcha),
    ];
    final response = await _send(
      AuthHttpRequest.form(
        _timestamped(pending.form.action),
        fields: fields,
        headers: {
          'Origin': _profile.baseUri.origin,
          'Referer': pending.form.pageUri.toString(),
        },
      ),
    );
    if (response.statusCode == 302 || response.statusCode == 303) {
      return _finishPassword(pending.credentials.username);
    }
    if (_redirectCodes.contains(response.statusCode)) {
      throw const LoginFailure(
        LoginFailureCode.browserRequired,
        '学校要求额外的登录跳转，请使用网页登录',
      );
    }
    _requireSuccess(response, '登录提交');
    final document = parseLoginDocument(response);
    final notice = classifyLoginPage(document);
    if (notice.failure != null) throw notice.failure!;
    if (notice.requiresCaptcha || isLoginDocument(document)) {
      final form = parsePasswordForm(document, response.uri, _profile);
      _pending = _PendingPasswordLogin(pending.credentials, form);
      if (notice.requiresCaptcha || form.hasVisibleCaptcha) {
        return CaptchaRequired(
          image: await _loadCaptcha(),
          rejected: captcha.isNotEmpty,
          message: captcha.isEmpty ? '请输入图片验证码' : '验证码未通过，请重新输入',
        );
      }
      throw const LoginFailure(
        LoginFailureCode.protocol,
        '学校未完成登录，请使用网页登录查看具体提示',
      );
    }
    return _finishPassword(pending.credentials.username);
  }

  Future<LoginSuccess> _finishPassword(String username) async {
    final session = await _verify(username);
    _pending = null;
    return LoginSuccess(session);
  }

  Future<String> _encryptPassword(String password) async {
    final response = await _get(
      _timestamped(_profile.publicKeyUri),
      headers: {'X-Requested-With': 'XMLHttpRequest'},
    );
    _requireSuccess(response, '登录公钥');
    Object? decoded;
    try {
      decoded = jsonDecode(response.text);
    } on FormatException {
      throw const LoginFailure(
        LoginFailureCode.browserRequired,
        '学校未提供标准 RSA 登录公钥，请使用网页登录',
      );
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['modulus'] is! String ||
        decoded['exponent'] is! String) {
      throw const LoginFailure(
        LoginFailureCode.browserRequired,
        '学校使用的密码加密方式尚未支持，请使用网页登录',
      );
    }
    final encrypted = _cipher.encrypt(
      modulus: decoded['modulus'] as String,
      exponent: decoded['exponent'] as String,
      password: password,
    );
    if (encrypted.isEmpty) {
      throw const LoginFailure(LoginFailureCode.protocol, '密码加密没有生成有效结果');
    }
    return encrypted;
  }

  Future<Uint8List> _loadCaptcha() async {
    final response = await _get(
      _timestamped(_requirePending().form.captchaUri),
    );
    final contentType = response
        .header('content-type')
        ?.split(';')
        .first
        .trim()
        .toLowerCase();
    if (response.statusCode != 200 ||
        (contentType != null &&
            contentType != 'application/octet-stream' &&
            !contentType.startsWith('image/')) ||
        !_hasImageSignature(response.body)) {
      throw const LoginFailure(
        LoginFailureCode.captcha,
        '验证码接口未返回有效图片，请刷新或使用网页登录',
      );
    }
    return response.body;
  }

  Future<LoginSession> _verify(String usernameHint) async {
    final uri = _profile.accountUri.replace(
      queryParameters: {
        ..._profile.accountUri.queryParameters,
        'xt': 'jw',
        'localeKey': 'zh_CN',
        'gnmkdm': 'index',
        '_': _clock().millisecondsSinceEpoch.toString(),
      },
    );
    final response = await _get(
      uri,
      headers: {'X-Requested-With': 'XMLHttpRequest'},
      verifyingAccount: true,
    );
    if (response.statusCode == 401 ||
        response.statusCode == 403 ||
        _isLoginOrFailureUri(response.uri)) {
      throw const LoginFailure(LoginFailureCode.expired, '教务登录状态已失效，请重新登录');
    }
    _requireSuccess(response, '账号核验');
    final account = parseAuthenticatedAccount(
      parseLoginDocument(response),
      usernameHint,
    );
    final cookies = await _transport.cookiesFor(_profile.accountUri);
    _ensureOpen();
    if (cookies.isEmpty) {
      throw const LoginFailure(
        LoginFailureCode.expired,
        '学校没有返回可继续使用的教务会话，请重新登录',
      );
    }
    final session = LoginSession(
      account: account,
      cookies: cookies,
      verifiedAt: _clock(),
    );
    _hasVerifiedIdentity = true;
    return session;
  }

  Future<AuthHttpResponse> _get(
    Uri uri, {
    Map<String, String> headers = const {},
    bool verifyingAccount = false,
  }) => _followRedirects(
    AuthHttpRequest.get(uri, headers: headers),
    sessionRejectedBy: verifyingAccount ? _isLoginOrFailureUri : null,
  );

  Future<AuthHttpResponse> _followRedirects(
    AuthHttpRequest request, {
    bool Function(Uri)? sessionRejectedBy,
  }) async {
    var next = request;
    for (var redirects = 0; ; redirects++) {
      final response = await _send(next);
      if (!_redirectCodes.contains(response.statusCode)) return response;
      if (redirects == _maxRedirects) {
        throw const LoginFailure(
          LoginFailureCode.protocol,
          '学校页面跳转次数过多，请使用网页登录',
        );
      }
      final location = response.header('location');
      if (location == null || location.trim().isEmpty) {
        throw const LoginFailure(LoginFailureCode.protocol, '学校返回了没有目标地址的页面跳转');
      }
      final Uri destination;
      try {
        destination = resolveLoginUri(response.uri, location, _profile);
      } on LoginFailure catch (failure) {
        if (sessionRejectedBy != null &&
            failure.code == LoginFailureCode.browserRequired) {
          throw const LoginFailure(LoginFailureCode.expired, '学校未确认登录状态，请重新登录');
        }
        rethrow;
      }
      if (sessionRejectedBy?.call(destination) ?? false) {
        throw const LoginFailure(LoginFailureCode.expired, '学校未确认登录状态，请重新登录');
      }
      // Only this explicit query path can replay a POST across 307/308.
      // Password submissions call _send directly and are never replayed here.
      next =
          next.method == 'POST' &&
              (response.statusCode == 307 || response.statusCode == 308)
          ? AuthHttpRequest.form(
              destination,
              fields: next.form,
              headers: next.headers,
            )
          : AuthHttpRequest.get(destination, headers: next.headers);
    }
  }

  Future<AuthHttpResponse> _send(AuthHttpRequest request) async {
    _ensureOpen();
    checkLoginOrigin(request.uri, _profile);
    final response = await _transport.send(request);
    _ensureOpen();
    checkLoginOrigin(response.uri, _profile);
    return response;
  }

  Future<T> _operation<T>(Future<T> Function() action) async {
    _ensureOpen();
    if (_busy) {
      throw const LoginFailure(LoginFailureCode.protocol, '当前登录步骤尚未完成，请稍候');
    }
    _busy = true;
    try {
      final result = await action();
      _ensureOpen();
      return result;
    } on LoginFailure catch (failure) {
      if (failure.code != LoginFailureCode.captcha &&
          failure.code != LoginFailureCode.network) {
        _pending = null;
      }
      rethrow;
    } finally {
      _busy = false;
    }
  }

  _PendingPasswordLogin _requirePending() {
    _ensureOpen();
    return _pending ??
        (throw const LoginFailure(
          LoginFailureCode.expired,
          '本次密码登录已结束，请重新开始登录',
        ));
  }

  void _ensureOpen() {
    if (_closed) {
      throw const LoginFailure(LoginFailureCode.cancelled, '本次登录已取消');
    }
  }

  Uri _timestamped(Uri uri) => uri.replace(
    queryParameters: {
      ...uri.queryParameters,
      'time': _clock().millisecondsSinceEpoch.toString(),
    },
  );

  bool _isLoginOrFailureUri(Uri uri) {
    if (uri.path == _profile.loginUri.path) return true;
    if (uri.path == _profile.accountUri.path) return false;
    return RegExp(
      r'^(?:login|error|failure|fail|forbidden)(?:[._-]|$)',
      caseSensitive: false,
    ).hasMatch(
      uri.pathSegments.where((part) => part.isNotEmpty).lastOrNull ?? '',
    );
  }

  bool _isLoginUri(Uri uri) =>
      uri.path == _profile.loginUri.path ||
      RegExp(r'^login(?:[._-]|$)', caseSensitive: false).hasMatch(
        uri.pathSegments.where((part) => part.isNotEmpty).lastOrNull ?? '',
      );

  void _requireSuccess(AuthHttpResponse response, String operation) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LoginFailure(
        response.statusCode >= 500
            ? LoginFailureCode.network
            : LoginFailureCode.protocol,
        '$operation失败：学校返回 HTTP ${response.statusCode}',
      );
    }
  }
}

final class _PendingPasswordLogin {
  const _PendingPasswordLogin(this.credentials, this.form);

  final LoginCredentials credentials;
  final PasswordLoginForm form;
}

bool _hasImageSignature(Uint8List bytes) {
  bool startsWith(List<int> prefix) =>
      bytes.length >= prefix.length &&
      Iterable<int>.generate(prefix.length)
          .every((index) => bytes[index] == prefix[index]);
  return startsWith(const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]) ||
      startsWith(const [0xff, 0xd8, 0xff]) ||
      startsWith(const [0x47, 0x49, 0x46, 0x38, 0x37, 0x61]) ||
      startsWith(const [0x47, 0x49, 0x46, 0x38, 0x39, 0x61]) ||
      startsWith(const [0x42, 0x4d]) ||
      (startsWith(const [0x52, 0x49, 0x46, 0x46]) &&
          bytes.length >= 12 &&
          bytes[8] == 0x57 &&
          bytes[9] == 0x45 &&
          bytes[10] == 0x42 &&
          bytes[11] == 0x50);
}
