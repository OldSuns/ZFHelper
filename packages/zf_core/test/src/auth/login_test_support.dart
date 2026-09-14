import 'dart:async';
import 'dart:convert';

import 'package:zf_core/src/auth/login_gateway.dart';
import 'package:zf_core/src/auth/login_models.dart';
import 'package:zf_core/src/auth/school_connection.dart';
import 'package:zf_core/src/auth/zhengfang_login_gateway.dart';

typedef RequestHandler = FutureOr<AuthHttpResponse> Function(
  AuthHttpRequest request,
);

final class ScriptedAuthTransport implements AuthTransport {
  ScriptedAuthTransport(this.handlers);

  final List<RequestHandler> handlers;
  final List<AuthHttpRequest> requests = [];
  final List<({Uri uri, List<LoginCookie> cookies})> replacements = [];
  final List<Uri> cookieReads = [];
  List<LoginCookie> availableCookies = const [
    LoginCookie(name: 'JSESSIONID', value: 'synthetic-test-session'),
  ];
  Future<List<LoginCookie>> Function(Uri)? cookieReader;
  bool closed = false;

  @override
  Future<AuthHttpResponse> send(AuthHttpRequest request) async {
    if (closed) throw const LoginFailure(LoginFailureCode.cancelled, '测试传输已关闭');
    final index = requests.length;
    requests.add(request);
    if (index >= handlers.length) {
      throw StateError('Unexpected request index $index');
    }
    return handlers[index](request);
  }

  @override
  Future<void> replaceCookies(Uri origin, List<LoginCookie> cookies) async {
    replacements.add((uri: origin, cookies: List.unmodifiable(cookies)));
  }

  @override
  Future<List<LoginCookie>> cookiesFor(Uri uri) async {
    cookieReads.add(uri);
    return cookieReader == null ? availableCookies : cookieReader!(uri);
  }

  @override
  void close() => closed = true;
}

final class RecordingPasswordCipher implements PasswordCipher {
  final List<({String modulus, String exponent, String password})> calls = [];

  @override
  String encrypt({
    required String modulus,
    required String exponent,
    required String password,
  }) {
    calls.add((modulus: modulus, exponent: exponent, password: password));
    return 'synthetic-encrypted-${calls.length}';
  }
}

final fixedTime = DateTime.utc(2026, 9, 12, 9, 30);
final defaultProfile = SchoolConnection(
  name: '协议测试学校',
  baseUri: Uri.parse('https://jw.example/jwglxt/'),
);
final credentials = LoginCredentials(
  username: ' 20260001 ',
  password: 'synthetic-password',
);
final pngImage = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a1ZkAAAAASUVORK5CYII=',
);

ZhengfangLoginGateway gatewayFor(
  ScriptedAuthTransport transport, {
  SchoolConnection? profile,
  RecordingPasswordCipher? cipher,
}) => ZhengfangLoginGateway(
  profile: profile ?? defaultProfile,
  transport: transport,
  cipher: cipher ?? RecordingPasswordCipher(),
  clock: () => fixedTime,
);

// These fixtures express the reference protocol; they are not school captures.
String loginPage({
  String token = 'csrf-one',
  bool visibleCaptcha = false,
  String notice = '',
  String action = 'login_slogin.html',
  String extraHidden = '',
  bool duplicatePassword = false,
}) =>
    '''
<!doctype html><html><body>
<form action="$action" method="post">
<input type="hidden" name="csrftoken" value="$token">
<input name="yhm"><input type="password" name="mm">
${duplicatePassword ? '<input type="hidden" name="mm" value="must-not-be-submitted">' : ''}
$extraHidden
<div ${visibleCaptcha ? '' : 'style="display: none"'}>
<label>验证码</label><input name="yzm"><img id="yzmPic" src="../kaptcha">
</div><div id="tips">$notice</div></form>
<script>const example = '用户名或密码不正确，验证码错误，账号已锁定';</script>
</body></html>
''';

AuthHttpResponse textResponse(
  AuthHttpRequest request,
  String body, {
  int status = 200,
  Map<String, List<String>> headers = const {},
}) => AuthHttpResponse(
  uri: request.uri,
  statusCode: status,
  body: utf8.encode(body),
  headers: headers,
);

AuthHttpResponse keyResponse(AuthHttpRequest request) => textResponse(
  request,
  '{"modulus":"synthetic-modulus","exponent":"synthetic-exponent"}',
);

AuthHttpResponse captchaResponse(AuthHttpRequest request) => AuthHttpResponse(
  uri: request.uri,
  statusCode: 200,
  body: pngImage,
  headers: {
    'content-type': ['image/png'],
  },
);

AuthHttpResponse successRedirect(AuthHttpRequest request) => textResponse(
  request,
  '',
  status: 302,
  headers: {
    'location': ['index_initMenu.html'],
  },
);

AuthHttpResponse accountResponse(AuthHttpRequest request) => textResponse(
  request,
  '<input name="xm" value="测试同学"><input name="xh" value="20260001">',
);

List<String> formValues(AuthHttpRequest request, String name) => request.form
    .where((field) => field.key == name)
    .map((field) => field.value)
    .toList();
