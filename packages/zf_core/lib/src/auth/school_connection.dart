import '../school_identity.dart';
import 'school_address.dart';

final class SchoolConnection {
  SchoolConnection({
    required String name,
    required Uri baseUri,
    this.loginPath = 'xtgl/login_slogin.html',
    this.publicKeyPath = 'xtgl/login_getPublicKey.html',
    this.captchaPath = 'kaptcha',
    this.accountPath = 'xtgl/index_cxYhxxIndex.html',
    this.schedulePagePath = defaultSchedulePath,
    this.scheduleQueryPath = defaultSchedulePath,
    this.schedulePeriodsPath,
    this.gradePagePath = defaultGradePagePath,
    this.gradeQueryPath = defaultGradeQueryPath,
    this.selectionPagePath = defaultSelectionPagePath,
    this.webLoginUri,
  }) : name = name.trim(),
       baseUri = normalizeSchoolBaseUri(baseUri) {
    if (this.name.isEmpty) throw const FormatException('请输入学校名称');
    final webUri = webLoginUri;
    if (webUri != null &&
        (!['https', 'http'].contains(webUri.scheme) ||
            webUri.host.isEmpty ||
            webUri.userInfo.isNotEmpty)) {
      throw const FormatException('网页登录入口必须是完整的 HTTP 或 HTTPS 地址');
    }
    for (final path in [
      loginPath,
      publicKeyPath,
      captchaPath,
      accountPath,
      schedulePagePath,
      scheduleQueryPath,
      ?schedulePeriodsPath,
      gradePagePath,
      gradeQueryPath,
      selectionPagePath,
    ]) {
      final endpoint = Uri.parse(path);
      if (path.trim().isEmpty || endpoint.hasScheme || endpoint.hasAuthority) {
        throw const FormatException('接口路径必须是教务系统中的相对路径');
      }
      if (this.baseUri.resolveUri(endpoint).origin != this.baseUri.origin) {
        throw const FormatException('接口路径不能指向另一个网站');
      }
    }
  }

  factory SchoolConnection.fromInput({
    required String name,
    required String address,
    String loginPath = 'xtgl/login_slogin.html',
    String publicKeyPath = 'xtgl/login_getPublicKey.html',
    String captchaPath = 'kaptcha',
    String accountPath = 'xtgl/index_cxYhxxIndex.html',
    String schedulePagePath = defaultSchedulePath,
    String scheduleQueryPath = defaultSchedulePath,
    String? schedulePeriodsPath,
    String gradePagePath = defaultGradePagePath,
    String gradeQueryPath = defaultGradeQueryPath,
    String selectionPagePath = defaultSelectionPagePath,
    String webLoginAddress = '',
  }) => SchoolConnection(
    name: name,
    baseUri: recognizeSchoolAddress(address),
    loginPath: loginPath.trim(),
    publicKeyPath: publicKeyPath.trim(),
    captchaPath: captchaPath.trim(),
    accountPath: accountPath.trim(),
    schedulePagePath: schedulePagePath.trim(),
    scheduleQueryPath: scheduleQueryPath.trim(),
    schedulePeriodsPath: schedulePeriodsPath?.trim(),
    gradePagePath: gradePagePath.trim(),
    gradeQueryPath: gradeQueryPath.trim(),
    selectionPagePath: selectionPagePath.trim(),
    webLoginUri: webLoginAddress.trim().isEmpty
        ? null
        : Uri.parse(webLoginAddress.trim()),
  );

  final String name;
  final Uri baseUri;
  final String loginPath;
  final String publicKeyPath;
  final String captchaPath;
  final String accountPath;
  static const defaultSchedulePath = 'kbcx/xskbcx_cxXsKb.html?gnmkdm=N253508';
  static const defaultGradePagePath = 'cjcx/cjcx_cxDgXscj.html?gnmkdm=N305005';
  static const defaultGradeQueryPath =
      'cjcx/cjcx_cxDgXscj.html?doType=query&gnmkdm=N305005';
  static const defaultSelectionPagePath =
      'xsxk/zzxkyzb_cxZzxkYzbIndex.html?gnmkdm=N253512';

  final String schedulePagePath;
  final String scheduleQueryPath;
  final String? schedulePeriodsPath;
  final String gradePagePath;
  final String gradeQueryPath;
  final String selectionPagePath;
  final Uri? webLoginUri;

  SchoolIdentity get school =>
      SchoolIdentity(id: baseUri.toString(), name: name);
  Uri get loginUri => baseUri.resolve(loginPath);
  Uri get publicKeyUri => baseUri.resolve(publicKeyPath);
  Uri get captchaUri => baseUri.resolve(captchaPath);
  Uri get accountUri => baseUri.resolve(accountPath);
  Uri get schedulePageUri => baseUri.resolve(schedulePagePath);
  Uri get scheduleQueryUri => baseUri.resolve(scheduleQueryPath);
  Uri? get schedulePeriodsUri => schedulePeriodsPath == null
      ? null
      : baseUri.resolve(schedulePeriodsPath!);
  Uri get gradePageUri => baseUri.resolve(gradePagePath);
  Uri get gradeQueryUri => baseUri.resolve(gradeQueryPath);
  Uri get selectionPageUri => baseUri.resolve(selectionPagePath);
  Uri get browserUri => webLoginUri ?? loginUri;
}
