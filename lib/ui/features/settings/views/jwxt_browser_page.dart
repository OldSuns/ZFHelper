import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zf_core/zf_core.dart';

/// In-app browser for the school portal. The selected account's saved cookies
/// are seeded once to reuse the current session; no credentials are entered,
/// stored or submitted here, and external apps are never opened.
class JwxtBrowserPage extends StatefulWidget {
  const JwxtBrowserPage({
    required this.profile,
    required this.cookies,
    super.key,
  });

  final SchoolConnection profile;

  /// Stored session cookies; empty when the account has no saved session.
  final List<LoginCookie> cookies;

  @override
  State<JwxtBrowserPage> createState() => _JwxtBrowserPageState();
}

class _JwxtBrowserPageState extends State<JwxtBrowserPage> {
  // Cookie stores are shared process-wide (default store on Android, the
  // single environment on Windows). Serialize every clear+seed so two pages
  // opened in sequence cannot interleave their shared-store mutations.
  static Future<void> _cookieTurn = Future<void>.value();

  // Windows without an environment gets a transient WebView2 profile whose
  // cookies cannot be seeded, so keep one persistent environment per process.
  // The pending creation is cached too: concurrent page opens must share a
  // single create operation instead of racing two environments.
  static Future<WebViewEnvironment>? _windowsEnvironmentFuture;

  WebViewEnvironment? _environment;
  InAppWebViewController? _controller;
  late final TextEditingController _address;
  final _addressFocus = FocusNode();
  int _progress = 100;
  bool _ready = false;
  bool _blocked = false;
  bool _canGoBack = false;
  bool _canGoForward = false;
  String? _failure;
  String? _lastUrl;

  @override
  void initState() {
    super.initState();
    _address = TextEditingController(
      text: widget.profile.browserUri.toString(),
    );
    // Freeze the address while the user edits it.
    _addressFocus.addListener(_handleAddressFocus);
    unawaited(_prepare());
  }

  @override
  void dispose() {
    _addressFocus.dispose();
    _address.dispose();
    super.dispose();
  }

  final _settings = InAppWebViewSettings(
    javaScriptEnabled: true,
    domStorageEnabled: true,
    useShouldOverrideUrlLoading: true,
    isInspectable: false,
  );

  bool get _isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Future<void> _prepare() async {
    // Mirrors LoginBrowserSession: only Android and Windows are supported.
    if (!_isWindows &&
        (kIsWeb || defaultTargetPlatform != TargetPlatform.android)) {
      if (mounted) {
        setState(() {
          _failure = '当前平台尚不支持应用内教务网页';
          _blocked = true;
          _ready = true;
        });
      }
      return;
    }
    String? failure;
    var blocked = false;
    final turn = _cookieTurn.then((_) async {
      // A page disposed while waiting for its turn must not touch the
      // shared cookie store afterwards.
      if (!mounted) return;
      try {
        final CookieManager cookies;
        if (_isWindows) {
          final creation = _windowsEnvironmentFuture ??=
              WebViewEnvironment.create(
                settings: WebViewEnvironmentSettings(
                  userDataFolder: (await getApplicationSupportDirectory()).uri
                      .resolve('zfhelper-browser')
                      .toFilePath(),
                  allowSingleSignOnUsingOSPrimaryAccount: false,
                ),
              );
          late final WebViewEnvironment environment;
          try {
            environment = await creation;
          } on Object {
            // Drop only this failed creation so a later open can build a new
            // environment instead of reusing a broken one.
            if (identical(_windowsEnvironmentFuture, creation)) {
              _windowsEnvironmentFuture = null;
            }
            rethrow;
          }
          _environment = environment;
          cookies = CookieManager.fromPlatformCreationParams(
            PlatformCookieManagerCreationParams(
              webViewEnvironment: environment.platform,
            ),
          );
        } else {
          cookies = CookieManager.instance();
        }
        // The web view cookie store is shared app-wide; clear it so a session
        // left by a previously selected account cannot leak into the initial
        // navigation of the current account's portal.
        await cookies.deleteAllCookies();
        failure = await _seed(cookies);
        blocked = _isWindows && _environment == null;
      } on Object {
        // The plugin may be unavailable (e.g. widget tests); the web view can
        // still be opened manually, just without the saved session.
        failure = '无法复用教务登录会话，可在网页中手动浏览';
        blocked = _isWindows && _environment == null;
      }
    });
    // Keep the queue alive even when a turn throws.
    _cookieTurn = turn.then((_) {}, onError: (_) {});
    await turn;
    if (mounted) {
      setState(() {
        _failure = failure;
        _blocked = blocked;
        _ready = true;
      });
    }
  }

  Future<String?> _seed(CookieManager cookies) async {
    final target = WebUri.uri(widget.profile.baseUri);
    for (final cookie in widget.cookies) {
      try {
        await cookies.setCookie(
          url: target,
          name: cookie.name,
          value: cookie.value,
          domain: cookie.domain,
          path: cookie.path ?? '/',
          isSecure: cookie.secure,
          isHttpOnly: cookie.httpOnly,
          expiresDate: cookie.expiresAt?.millisecondsSinceEpoch,
        );
      } on Object {
        return '无法写入学校网页会话，登录态可能未生效';
      }
    }
    return null;
  }

  void _handleAddressFocus() {
    if (!_addressFocus.hasFocus) {
      _address.text = _controllerUrl;
    }
  }

  String get _controllerUrl => _lastUrl ?? widget.profile.browserUri.toString();

  Future<void> _goBack() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      if (await controller.canGoBack()) await controller.goBack();
    } on Object {
      // The view may navigate concurrently; the history buttons refresh
      // themselves on the next completed load.
    }
  }

  Future<void> _goForward() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      if (await controller.canGoForward()) await controller.goForward();
    } on Object {
      // Concurrent navigation may race the check; see _goBack.
    }
  }

  Future<void> _reload() async {
    try {
      await _controller?.reload();
    } on Object {
      if (mounted) setState(() => _failure = '网页无法刷新，请返回后重新打开');
    }
  }

  Future<void> _submitAddress(String value) async {
    final controller = _controller;
    _addressFocus.unfocus();
    if (controller == null) return;
    Uri? uri;
    try {
      uri = Uri.parse(value.trim());
    } on FormatException {
      uri = null;
    }
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      setState(() => _failure = '请输入完整的 http(s) 网页地址');
      return;
    }
    try {
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri.uri(uri)));
    } on Exception {
      if (mounted) setState(() => _failure = '无法打开该地址，请检查后再试');
    }
  }

  Future<void> _copyAddress() async {
    await Clipboard.setData(ClipboardData(text: _controllerUrl));
  }

  Future<void> _syncState(InAppWebViewController controller) async {
    try {
      final canGoBack = await controller.canGoBack();
      final canGoForward = await controller.canGoForward();
      if (!mounted) return;
      setState(() {
        _canGoBack = canGoBack;
        _canGoForward = canGoForward;
      });
    } on Object {
      // History queries can fail while the view rebuilds; the buttons keep
      // their previous state until the next completed load.
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${widget.profile.name} · 教务网页')),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(
              children: [
                IconButton(
                  tooltip: '后退',
                  onPressed: _canGoBack ? _goBack : null,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                IconButton(
                  tooltip: '前进',
                  onPressed: _canGoForward ? _goForward : null,
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
                IconButton(
                  tooltip: '刷新网页',
                  onPressed: _controller == null ? null : _reload,
                  icon: const Icon(Icons.refresh_rounded),
                ),
                Expanded(
                  child: TextField(
                    controller: _address,
                    focusNode: _addressFocus,
                    enabled: _ready && !_blocked,
                    autocorrect: false,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    onSubmitted: _submitAddress,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      hintText: '输入网页地址',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      suffixIcon: IconButton(
                        tooltip: '复制当前地址',
                        onPressed: _copyAddress,
                        icon: const Icon(Icons.copy_rounded, size: 18),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_progress < 100) LinearProgressIndicator(value: _progress / 100),
          if (_failure != null && !_blocked)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                _failure!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(child: _browser()),
        ],
      ),
    ),
  );

  Widget _browser() {
    // Cookies must be seeded before the first school navigation, or the
    // portal would not see the existing session on the initial request.
    if (!_ready) return const Center(child: CircularProgressIndicator());
    if (_blocked) {
      return Center(child: Text(_failure ?? '网页组件初始化失败，请返回后重试'));
    }
    return InAppWebView(
      webViewEnvironment: _environment,
      initialSettings: _settings,
      initialUrlRequest: URLRequest(url: WebUri.uri(widget.profile.browserUri)),
      onWebViewCreated: (controller) => _controller = controller,
      onLoadStart: (controller, url) {
        if (!mounted) return;
        setState(() {
          _progress = 0;
          if (url != null && ['http', 'https'].contains(url.scheme)) {
            _lastUrl = url.toString();
            if (!_addressFocus.hasFocus) _address.text = _lastUrl!;
          }
        });
      },
      onLoadStop: (controller, url) => _syncState(controller),
      onUpdateVisitedHistory: (controller, url, isReload) {
        if (!mounted) return;
        _syncState(controller);
      },
      onProgressChanged: (controller, progress) {
        if (mounted) setState(() => _progress = progress);
      },
      onReceivedError: (controller, request, error) {
        if (!mounted || request.isForMainFrame != true) return;
        setState(() => _failure = '网页加载失败，请检查网络和教务地址后重试');
      },
      onReceivedHttpError: (controller, request, response) {
        if (!mounted || request.isForMainFrame != true) return;
        setState(() => _failure = '学校网页返回 HTTP ${response.statusCode}，请稍后重试');
      },
      shouldOverrideUrlLoading: (controller, action) async {
        final scheme = action.request.url?.scheme;
        if (scheme == 'http' || scheme == 'https' || scheme == 'about') {
          return NavigationActionPolicy.ALLOW;
        }
        if (mounted) setState(() => _failure = '该链接需要外部应用，网页内无法打开');
        return NavigationActionPolicy.CANCEL;
      },
    );
  }
}
