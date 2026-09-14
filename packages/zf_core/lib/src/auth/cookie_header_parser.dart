import 'login_models.dart';

/// Parses a request Cookie header scoped to the configured school's base URI.
///
/// A copied request header does not contain original cookie attributes. The
/// resulting cookies are host-only, use the base path, and require HTTPS when
/// [baseUri] uses HTTPS. Set-Cookie response attributes are not accepted.
List<LoginCookie> parseLoginCookies(String raw, Uri baseUri) {
  if (!['http', 'https'].contains(baseUri.scheme) ||
      baseUri.host.isEmpty ||
      baseUri.userInfo.isNotEmpty) {
    throw const LoginFailure(LoginFailureCode.protocol, '请先配置有效的教务系统地址');
  }
  final header = raw.trim().replaceFirst(
    RegExp(r'^cookie\s*:\s*', caseSensitive: false),
    '',
  );
  if (header.isEmpty || RegExp(r'[\r\n\x00]').hasMatch(header)) {
    throw const LoginFailure(LoginFailureCode.protocol, '请输入单行 Cookie 请求头');
  }

  final names = <String>{};
  final cookies = <LoginCookie>[];
  final parts = header.split(';');
  for (var index = 0; index < parts.length; index++) {
    final part = parts[index].trim();
    if (part.isEmpty && index == parts.length - 1) continue;
    final separator = part.indexOf('=');
    if (separator <= 0) _invalidCookie();
    final name = part.substring(0, separator).trim();
    final value = part.substring(separator + 1).trim();
    if (!_cookieName.hasMatch(name) ||
        !_cookieValue.hasMatch(value) ||
        _responseAttributes.contains(name.toLowerCase())) {
      _invalidCookie();
    }
    if (!names.add(name)) {
      throw const LoginFailure(
        LoginFailureCode.protocol,
        'Cookie 中有重复名称，请重新复制当前页面的请求头',
      );
    }
    cookies.add(
      LoginCookie(
        name: name,
        value: value,
        path: baseUri.path.isEmpty ? '/' : baseUri.path,
        secure: baseUri.scheme == 'https',
      ),
    );
  }
  if (cookies.isEmpty) _invalidCookie();
  return List<LoginCookie>.unmodifiable(cookies);
}

final _cookieName = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$");
final _cookieValue = RegExp(
  r'^(?:[\x21\x23-\x2B\x2D-\x3A\x3C-\x5B\x5D-\x7E]*|"[\x21\x23-\x2B\x2D-\x3A\x3C-\x5B\x5D-\x7E]*")$',
);
const _responseAttributes = {
  'path',
  'domain',
  'expires',
  'max-age',
  'secure',
  'httponly',
  'samesite',
};

Never _invalidCookie() => throw const LoginFailure(
  LoginFailureCode.protocol,
  'Cookie 格式无效，请粘贴 Cookie 请求头，不包含 Set-Cookie 属性',
);
