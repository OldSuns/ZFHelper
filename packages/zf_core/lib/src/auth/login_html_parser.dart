import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import 'login_models.dart';
import 'school_connection.dart';

/// Parsed fields for one password form in its current server session.
final class PasswordLoginForm {
  PasswordLoginForm({
    required this.pageUri,
    required this.action,
    required List<MapEntry<String, String>> hiddenFields,
    required this.passwordFieldCount,
    required this.hasVisibleCaptcha,
    required this.captchaUri,
  }) : hiddenFields = List.unmodifiable(hiddenFields);

  final Uri pageUri;
  final Uri action;
  final List<MapEntry<String, String>> hiddenFields;
  final int passwordFieldCount;
  final bool hasVisibleCaptcha;
  final Uri captchaUri;
}

/// A classified response notice that contains no server-provided identity text.
final class LoginPageNotice {
  const LoginPageNotice({this.failure, this.requiresCaptcha = false});

  final LoginFailure? failure;
  final bool requiresCaptcha;
}

Document parseLoginDocument(AuthHttpResponse response) {
  try {
    return html.parse(response.text);
  } on FormatException {
    throw const LoginFailure(LoginFailureCode.protocol, '学校页面的文字编码无法识别');
  }
}

PasswordLoginForm parsePasswordForm(
  Document document,
  Uri pageUri,
  SchoolConnection profile,
) {
  final form = document
      .querySelectorAll('form')
      .where(
        (candidate) =>
            candidate.querySelector('input[name="yhm"], input[name="mm"]') !=
            null,
      )
      .firstOrNull;
  final scope = form ?? document;
  final token = scope
      .querySelector('input[name="csrftoken"]')
      ?.attributes['value'];
  if (token == null || token.trim().isEmpty) {
    throw const LoginFailure(
      LoginFailureCode.browserRequired,
      '该登录页没有标准新正方登录令牌，请使用网页登录',
    );
  }
  final baseHref = document.querySelector('base[href]')?.attributes['href'];
  final baseUri = baseHref == null
      ? pageUri
      : resolveLoginUri(pageUri, baseHref, profile);
  final action = form?.attributes['action'];
  final actionUri = action == null || action.trim().isEmpty
      ? pageUri
      : resolveLoginUri(baseUri, action, profile);
  checkLoginOrigin(actionUri, profile);

  final hidden = <MapEntry<String, String>>[MapEntry('csrftoken', token)];
  for (final input in scope.querySelectorAll('input')) {
    final name = input.attributes['name'];
    if (input.attributes['type']?.toLowerCase() != 'hidden' ||
        input.attributes.containsKey('disabled') ||
        name == null ||
        name.isEmpty ||
        const {'csrftoken', 'yhm', 'mm', 'yzm'}.contains(name)) {
      continue;
    }
    hidden.add(MapEntry(name, input.attributes['value'] ?? ''));
  }
  final captchaInput = scope
      .querySelectorAll('input[name="yzm"], input#yzm')
      .where(
        (input) =>
            input.attributes['type']?.toLowerCase() != 'hidden' &&
            !input.attributes.containsKey('disabled') &&
            _isVisible(input),
      )
      .firstOrNull;
  final imageSource = scope
      .querySelector(
        'img#yzmPic, img#kaptcha, img#kaptchaImage, img[src*="kaptcha"]',
      )
      ?.attributes['src'];
  final captchaUri = imageSource == null || imageSource.trim().isEmpty
      ? profile.captchaUri
      : resolveLoginUri(baseUri, imageSource, profile);
  final passwordFieldCount = scope
      .querySelectorAll('input[name="mm"]')
      .where((input) => !input.attributes.containsKey('disabled'))
      .length;
  return PasswordLoginForm(
    pageUri: pageUri,
    action: actionUri,
    hiddenFields: hidden,
    passwordFieldCount: passwordFieldCount == 0 ? 1 : passwordFieldCount,
    hasVisibleCaptcha: captchaInput != null,
    captchaUri: captchaUri,
  );
}

LoginPageNotice classifyLoginPage(Document document) {
  final notices = document
      .querySelectorAll(
        '#tips, #msg, #errorMsg, #errMsg, .error-msg, .error-message, .alert-danger, [role="alert"]',
      )
      .where(_isVisible)
      .map(_visibleText)
      .where((text) => text.trim().isNotEmpty)
      .join(' ');
  final rendered = _visibleText(document).trim();
  if (_lockedMessage.hasMatch(notices) ||
      _standaloneLockedMessage.hasMatch(rendered)) {
    return const LoginPageNotice(
      failure: LoginFailure(
        LoginFailureCode.accountLocked,
        '学校已锁定该账号，请稍后再试或联系学校',
      ),
    );
  }
  if (_credentialsMessage.hasMatch(notices) ||
      _standaloneCredentialsMessage.hasMatch(rendered)) {
    return const LoginPageNotice(
      failure: LoginFailure(LoginFailureCode.invalidCredentials, '用户名或密码不正确'),
    );
  }
  return LoginPageNotice(
    requiresCaptcha:
        RegExp(r'验证码|校验码').hasMatch(notices) ||
        _captchaMessage.hasMatch(rendered),
  );
}

bool isLoginDocument(Document document) =>
    document.querySelector('input[name="mm"], input[type="password"]') !=
        null ||
    (document.querySelector('input[name="csrftoken"]') != null &&
        document.querySelector('input[name="yhm"]') != null);

LoginAccount parseAuthenticatedAccount(Document document, String usernameHint) {
  final visiblePassword = document
      .querySelectorAll('input[name="mm"]')
      .any(_isVisibleControl);
  final visibleLoginForm =
      document.querySelectorAll('input[name="yhm"]').any(_isVisibleControl) &&
      document
          .querySelectorAll('input[type="password"]')
          .any(_isVisibleControl);
  if (visiblePassword || visibleLoginForm) {
    throw const LoginFailure(LoginFailureCode.expired, '教务登录状态已失效，请重新登录');
  }
  final name =
      _firstIdentity(document, const ['input[name="xm"]']) ??
      _firstIdentity(document, const [
        'h4.media-heading',
        'span[name="xm"]',
        'div[name="xm"]',
        '.user-name',
        '.student-name',
        '#xhxm',
      ])?.replaceFirst(RegExp(r'\s*(?:学生|同学)\s*$'), '').trim();
  final studentId = _firstIdentity(document, const [
    'input[name="xh"]',
    'span[name="xh"]',
    'div[name="xh"]',
    '.student-id',
    '#xh',
    '.user-id',
  ]);
  final notice = classifyLoginPage(document);
  if (notice.failure != null) throw notice.failure!;
  final title = document.querySelector('title')?.text ?? '';
  if (RegExp(
    r'错误|异常|失败|error|forbidden',
    caseSensitive: false,
  ).hasMatch(title)) {
    throw const LoginFailure(LoginFailureCode.protocol, '账号核验接口返回了学校错误页面');
  }
  // Authenticated pages may also embed login templates and password guidance.
  if ((name == null || name.isEmpty) && studentId == null) {
    final rendered = _visibleText(document);
    if (isLoginDocument(document) ||
        RegExp(r'未登录|未登陆|登录.{0,8}失效|会话.{0,8}过期|请重新登录').hasMatch(rendered)) {
      throw const LoginFailure(LoginFailureCode.expired, '教务登录状态已失效，请重新登录');
    }
    throw const LoginFailure(
      LoginFailureCode.protocol,
      '学校尚未返回可确认的账号信息，请完成网页登录后重试',
    );
  }
  final hint = usernameHint.trim();
  if (studentId == null && hint.isEmpty) {
    throw const LoginFailure(
      LoginFailureCode.missingIdentity,
      '已确认登录，但学校未返回学号，请补充学号',
    );
  }
  return LoginAccount(
    id: studentId ?? hint,
    displayName: name == null || name.isEmpty ? studentId! : name,
    loginName: hint.isEmpty ? studentId! : hint,
    studentId: studentId,
  );
}

Uri resolveLoginUri(Uri base, String path, SchoolConnection profile) {
  try {
    final uri = base.resolve(path.trim()).removeFragment();
    checkLoginOrigin(uri, profile);
    return uri;
  } on FormatException {
    throw const LoginFailure(LoginFailureCode.protocol, '学校返回了无效的页面地址');
  }
}

void checkLoginOrigin(Uri uri, SchoolConnection profile) {
  if (!['http', 'https'].contains(uri.scheme) ||
      uri.userInfo.isNotEmpty ||
      uri.origin != profile.baseUri.origin) {
    throw const LoginFailure(
      LoginFailureCode.browserRequired,
      '该登录流程需要访问其他认证网站，请使用网页登录',
    );
  }
}

String? _firstIdentity(Document document, List<String> selectors) {
  for (final selector in selectors) {
    for (final element in document.querySelectorAll(selector)) {
      final value =
          (element.localName == 'input'
                  ? element.attributes['value'] ?? ''
                  : element.text)
              .trim();
      if (value.isNotEmpty) return value;
    }
  }
  return null;
}

bool _isVisibleControl(Element input) =>
    input.attributes['type']?.toLowerCase() != 'hidden' && _isVisible(input);

bool _isVisible(Element element) {
  for (Element? current = element; current != null; current = current.parent) {
    if (current.attributes.containsKey('hidden') ||
        current.attributes['aria-hidden'] == 'true' ||
        current.classes.any(const {'hidden', 'hide', 'd-none'}.contains) ||
        RegExp(
          r'(?:display\s*:\s*none|visibility\s*:\s*hidden)',
          caseSensitive: false,
        ).hasMatch(current.attributes['style'] ?? '')) {
      return false;
    }
  }
  return true;
}

String _visibleText(Node node) {
  if (node is Text) return node.data;
  if (node is Element &&
      (const {
            'script',
            'style',
            'template',
            'noscript',
          }.contains(node.localName) ||
          !_isVisible(node))) {
    return '';
  }
  return node.nodes.map(_visibleText).join(' ');
}

final _lockedMessage = RegExp(r'(?:账号|帐号|账户|用户).{0,12}(?:锁定|冻结)|(?:已被|已经|被)锁定');
final _standaloneLockedMessage = RegExp(
  r'^(?:账号|帐号|账户|用户)(?:已被|已经|已|被)(?:锁定|冻结)(?:[。！!，,\s]|$)',
);
final _standaloneCredentialsMessage = RegExp(
  r'^(?:(?:用户名|账号|帐号|学号)(?:或|和)密码|密码)(?:不正确|错误|不匹配)(?:[。！!，,\s]|$)',
);
final _credentialsMessage = RegExp(
  r'(?:用户名|账号|帐号|学号).{0,12}(?:密码).{0,8}(?:不正确|错误|不匹配)|'
  r'(?:用户名|账号|帐号|学号).{0,8}(?:不存在|不正确|错误)|密码.{0,8}(?:不正确|错误|不匹配)',
);
final _captchaMessage = RegExp(
  r'(?:请输入|请填写|请提供).{0,8}(?:验证码|校验码)|'
  r'(?:验证码|校验码).{0,8}(?:不能为空|必填|错误|不正确|无效|过期)',
);
