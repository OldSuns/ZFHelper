/// Recognizes a Zhengfang business root from an address without network access.
///
/// Bare hosts and protocol-relative addresses use HTTPS; explicit HTTP is
/// preserved. Known module paths and deployment names identify the root, while
/// otherwise plain directory paths are kept in full. Unknown document pages
/// and CAS entry pages require the user to supply a business root instead.
/// Query strings and fragments never become part of the result. This is syntax
/// recognition, not evidence that a school or endpoint has been verified.
Uri recognizeSchoolAddress(String input) => _safeAddress(() {
  final uri = _parseAddress(input, inferScheme: true);
  return _baseUri(uri, _businessRoot(_segments(uri)));
});

/// Validates an already configured business root for SchoolConnection.
///
/// Unlike [recognizeSchoolAddress], this boundary does not accept a page URL,
/// a missing scheme, a query string, or a fragment.
Uri normalizeSchoolBaseUri(Uri input) => _safeAddress(() {
  if (!input.hasScheme || input.hasQuery || input.hasFragment) {
    _fail('学校配置必须使用完整且不含查询参数、片段的教务根网址');
  }
  final uri = _parseAddress(input.toString(), inferScheme: false);
  final segments = _segments(uri);
  if (_documentSuffix.hasMatch(uri.path)) {
    _fail('学校配置需要教务系统根网址，请先识别完整页面网址');
  }
  return _baseUri(uri, segments);
});

const _moduleDirectories = {'xtgl', 'xsxk', 'kbcx', 'cjcx', 'xsxy'};
const _systemDirectories = {'jwglxt', 'jwxt', 'jwxs', 'jw'};
final _unsafeCharacters = RegExp(r'[\\\x00-\x1f\x7f-\x9f]');
final _hostLabel = RegExp(r'^[\p{L}\p{M}\p{N}_-]+$', unicode: true);
final _schemePrefix = RegExp(r'^[a-z][a-z0-9+.-]*:', caseSensitive: false);
final _httpPrefix = RegExp(r'^https?://', caseSensitive: false);
final _documentSuffix = RegExp(
  r'\.(?:html?|aspx?|jsp|php|do|action)$',
  caseSensitive: false,
);

Uri _parseAddress(String input, {required bool inferScheme}) {
  if (_unsafeCharacters.hasMatch(input)) {
    _fail('网址不能包含反斜线或控制字符');
  }
  var text = input.trim();
  if (text.isEmpty) _fail('请输入教务系统网址');
  if (RegExp(r'\s', unicode: true).hasMatch(text)) {
    _fail('网址中不能包含空白字符，请粘贴完整网址');
  }
  var bareHost = false;
  if (!_httpPrefix.hasMatch(text)) {
    if (!inferScheme) _fail('教务根网址必须使用 HTTP 或 HTTPS 协议');
    if (text.startsWith('//')) {
      text = 'https:$text';
    } else {
      final end = text.indexOf(RegExp(r'[/\?#]'));
      final authority = end < 0 ? text : text.substring(0, end);
      if (!authority.startsWith('[') && ':'.allMatches(authority).length > 1) {
        Uri.parseIPv6Address(authority);
        text = '[$authority]${end < 0 ? '' : text.substring(end)}';
      } else if (_schemePrefix.hasMatch(text) && !_isBareHostPort(authority)) {
        _fail('仅支持 HTTP 或 HTTPS 网址；带协议时请包含 ://');
      }
      bareHost = true;
      text = 'https://$text';
    }
  }
  final authorityStart = text.indexOf('://') + 3;
  final authorityEnd = text.indexOf(RegExp(r'[/\?#]'), authorityStart);
  final authority = text.substring(
    authorityStart,
    authorityEnd < 0 ? text.length : authorityEnd,
  );
  _validateAuthority(authority);
  final uri = Uri.parse(text).normalizePath();
  if (!uri.hasAuthority || !const {'http', 'https'}.contains(uri.scheme)) {
    _fail('请输入有效的 HTTP 或 HTTPS 教务网址');
  }
  _validateHost(_decodedHost(uri), requireQualified: bareHost);
  return uri;
}

bool _isBareHostPort(String authority) {
  if (authority.startsWith('[')) return true;
  final separator = authority.lastIndexOf(':');
  if (separator <= 0) return false;
  final host = authority.substring(0, separator).toLowerCase();
  return host == 'localhost' || host.contains('.');
}

void _validateAuthority(String authority) {
  if (authority.isEmpty) _fail('网址缺少域名或 IP 地址');
  if (authority.contains('@')) _fail('网址不能包含用户名或密码');
  String? port;
  if (authority.startsWith('[')) {
    final end = authority.indexOf(']');
    if (end < 0) _fail('IPv6 地址需要使用完整的方括号');
    final suffix = authority.substring(end + 1);
    if (suffix.isNotEmpty) {
      if (!suffix.startsWith(':')) _fail('IPv6 地址或端口格式无效');
      port = suffix.substring(1);
    }
  } else if (authority.contains(':')) {
    if (':'.allMatches(authority).length > 1) {
      _fail('带协议的 IPv6 网址请使用方括号包住地址');
    }
    port = authority.substring(authority.indexOf(':') + 1);
  }
  if (port == null) return;
  final value = RegExp(r'^[0-9]+$').hasMatch(port) ? int.tryParse(port) : null;
  if (value == null || value < 1 || value > 65535) {
    _fail('网址端口必须是 1 到 65535 之间的整数');
  }
}

String _decodedHost(Uri uri) =>
    Uri.decodeComponent(uri.host)
        .toLowerCase()
        .replaceAll(RegExp('[\u3002\uff0e\uff61]'), '.');

void _validateHost(String host, {required bool requireQualified}) {
  if (host.isEmpty) _fail('网址缺少域名或 IP 地址');
  if (host.contains(':')) {
    Uri.parseIPv6Address(host);
    return;
  }
  final name = host.endsWith('.') ? host.substring(0, host.length - 1) : host;
  if (RegExp(r'^[0-9.]+$').hasMatch(name)) {
    Uri.parseIPv4Address(name);
    return;
  }
  final labels = name.split('.');
  if (requireQualified && labels.length < 2 && name != 'localhost') {
    _fail('请输入完整域名、IP 地址或 localhost');
  }
  if (labels.any(
    (label) =>
        label.isEmpty ||
        !_hostLabel.hasMatch(label) ||
        label.startsWith('-') ||
        label.endsWith('-'),
  )) {
    _fail('网址的域名格式无效');
  }
}

List<String> _segments(Uri uri) {
  final parts = uri.pathSegments;
  if (parts.any(
    (part) => part.contains('/') || _unsafeCharacters.hasMatch(part),
  )) {
    _fail('网址路径包含无效的转义分隔符或控制字符');
  }
  return parts.isNotEmpty && parts.last.isEmpty
      ? parts.sublist(0, parts.length - 1)
      : parts;
}

List<String> _businessRoot(List<String> segments) {
  final lower = segments.map((segment) => segment.toLowerCase()).toList();
  for (var index = 0; index + 1 < lower.length; index++) {
    if (const {'cas', 'authserver'}.contains(lower[index]) &&
        RegExp(r'^login(?:\.[a-z0-9]+)?$').hasMatch(lower[index + 1])) {
      _fail('这是统一身份认证网址，请登录后复制进入教务系统的页面网址');
    }
  }
  final module = lower.indexWhere(_moduleDirectories.contains);
  if (module >= 0) return segments.sublist(0, module);
  final isDocument = lower.isNotEmpty && _documentSuffix.hasMatch(lower.last);
  if (!isDocument) return segments;
  final deployment = lower.lastIndexWhere(_systemDirectories.contains);
  if (deployment >= 0) return segments.sublist(0, deployment + 1);
  _fail('无法从该页面确定教务根目录，请提供教务系统根网址');
}

Uri _baseUri(Uri uri, List<String> segments) => Uri(
  scheme: uri.scheme,
  host: _decodedHost(uri),
  port: uri.hasPort ? uri.port : null,
  pathSegments: ['', ...segments, ''],
);

Uri _safeAddress(Uri Function() parse) {
  try {
    return parse();
  } on _AddressProblem catch (problem) {
    throw FormatException(problem.message);
  } on FormatException {
    // SDK parse errors may carry the original address, including its tickets.
    throw const FormatException('网址格式无效，请检查域名、IP 地址和端口');
  }
}

Never _fail(String message) => throw _AddressProblem(message);

final class _AddressProblem implements Exception {
  const _AddressProblem(this.message);
  final String message;
}
