import 'dart:convert';
import 'dart:typed_data';

enum LoginMethod { password, web, cookie }

enum LoginFailureCode {
  network,
  protocol,
  browserRequired,
  invalidCredentials,
  accountLocked,
  captcha,
  expired,
  missingIdentity,
  cancelled,
  storage,
}

final class LoginFailure implements Exception {
  const LoginFailure(this.code, this.message);

  final LoginFailureCode code;
  final String message;

  @override
  String toString() => 'LoginFailure(${code.name}): $message';
}

final class LoginCredentials {
  LoginCredentials({required String username, required this.password})
    : username = username.trim() {
    if (this.username.isEmpty || password.isEmpty) {
      throw const LoginFailure(LoginFailureCode.invalidCredentials, '请输入账号和密码');
    }
  }

  final String username;
  final String password;
}

final class LoginAccount {
  const LoginAccount({
    required this.id,
    required this.displayName,
    required this.loginName,
    this.studentId,
  });

  final String id;
  final String displayName;
  final String loginName;
  final String? studentId;
}

final class LoginCookie {
  const LoginCookie({
    required this.name,
    required this.value,
    this.domain,
    this.path,
    this.secure = false,
    this.httpOnly = true,
    this.expiresAt,
  });

  final String name;
  final String value;
  final String? domain;
  final String? path;
  final bool secure;
  final bool httpOnly;
  final DateTime? expiresAt;
}

final class LoginSession {
  LoginSession({
    required this.account,
    required List<LoginCookie> cookies,
    required this.verifiedAt,
  }) : cookies = List.unmodifiable(cookies);

  final LoginAccount account;
  final List<LoginCookie> cookies;
  final DateTime verifiedAt;
}

sealed class LoginStep {
  const LoginStep();
}

final class LoginSuccess extends LoginStep {
  const LoginSuccess(this.session);
  final LoginSession session;
}

final class CaptchaRequired extends LoginStep {
  CaptchaRequired({
    required List<int> image,
    this.rejected = false,
    this.message = '请输入图片验证码',
  }) : image = Uint8List.fromList(image).asUnmodifiableView();

  final Uint8List image;
  final bool rejected;
  final String message;
}

final class AuthHttpRequest {
  AuthHttpRequest.get(this.uri, {Map<String, String> headers = const {}})
    : method = 'GET',
      headers = Map.unmodifiable(headers),
      form = const [];

  AuthHttpRequest.form(
    this.uri, {
    required List<MapEntry<String, String>> fields,
    Map<String, String> headers = const {},
  }) : method = 'POST',
       headers = Map.unmodifiable(headers),
       form = List.unmodifiable(fields);

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final List<MapEntry<String, String>> form;
}

final class AuthHttpResponse {
  AuthHttpResponse({
    required this.uri,
    required this.statusCode,
    required List<int> body,
    Map<String, List<String>> headers = const {},
  }) : body = Uint8List.fromList(body).asUnmodifiableView(),
       headers = Map.unmodifiable({
         for (final entry in headers.entries)
           entry.key.toLowerCase(): List<String>.unmodifiable(entry.value),
       });

  final Uri uri;
  final int statusCode;
  final Uint8List body;
  final Map<String, List<String>> headers;

  String get text => utf8.decode(body);
  String? header(String name) => headers[name.toLowerCase()]?.firstOrNull;
}
