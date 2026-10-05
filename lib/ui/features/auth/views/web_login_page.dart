import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:zf_core/zf_core.dart';

import '../../../../platform/login_browser_session.dart';
import '../view_models/auth_view_model.dart';
import 'auth_notice.dart';

class WebLoginPage extends StatefulWidget {
  const WebLoginPage({
    required this.profile,
    required this.viewModel,
    required this.usernameHint,
    super.key,
  });

  final SchoolConnection profile;
  final AuthViewModel viewModel;
  final String usernameHint;

  @override
  State<WebLoginPage> createState() => _WebLoginPageState();
}

class _WebLoginPageState extends State<WebLoginPage> {
  late final TextEditingController _usernameHint;
  ScaffoldMessengerState? _messenger;
  LoginBrowserSession? _session;
  InAppWebViewController? _controller;
  bool _initializing = true;
  bool _showBrowser = false;
  bool _verifying = false;
  bool _submitted = false;
  bool _verified = false;
  bool _needsUsername = false;
  bool _closing = false;
  bool _allowPop = false;
  int _progress = 0;
  late String _origin;
  String? _failure;

  @override
  void initState() {
    super.initState();
    _origin = widget.profile.browserUri.origin;
    _usernameHint = TextEditingController(text: widget.usernameHint);
    unawaited(_initialize());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.of(context);
  }

  Future<void> _initialize() async {
    try {
      final session = await LoginBrowserSession.open();
      if (!mounted || _closing) {
        await _disposeSession(session);
        return;
      }
      _session = session;
      setState(() => _showBrowser = true);
    } on LoginFailure catch (error) {
      if (mounted) setState(() => _failure = error.message);
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  Future<void> _verify() async {
    final session = _session;
    if (session == null || _verifying || _closing) return;
    setState(() {
      _verifying = true;
      _submitted = true;
      _failure = null;
    });
    try {
      final cookies = await session.readCookies(widget.profile);
      if (!mounted || _closing) return;
      _verified = await widget.viewModel.signInCookies(
        widget.profile,
        cookies,
        method: LoginMethod.web,
        usernameHint: _usernameHint.text.trim(),
      );
      if (mounted &&
          !_verified &&
          widget.viewModel.state.failure?.code ==
              LoginFailureCode.missingIdentity) {
        setState(() => _needsUsername = true);
      }
      if (_verified && mounted) await _leave(true);
    } on LoginFailure catch (error) {
      if (mounted) setState(() => _failure = error.message);
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _leave(bool success) async {
    if (_closing) return;
    if (!success) widget.viewModel.cancelSignIn();
    setState(() => _closing = true);
    final session = _session;
    if (session != null) {
      LoginFailure? cleanupFailure;
      try {
        // Keep the widget mounted until its native creation callback arrives.
        await session.waitForViewCreation();
      } on LoginFailure catch (error) {
        cleanupFailure = error;
      }
      if (mounted) {
        setState(() {
          _showBrowser = false;
          _controller = null;
        });
        await WidgetsBinding.instance.endOfFrame;
      }
      try {
        await session.close();
      } on LoginFailure catch (error) {
        cleanupFailure ??= error;
      }
      _session = null;
      if (cleanupFailure != null) _reportCleanupFailure(cleanupFailure);
    }
    // Pending environment creation is cleaned by _initialize after this return.
    if (!mounted) return;
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop(success || _verified);
  }

  Future<void> _reload() async {
    try {
      await _controller?.reload();
    } on PlatformException {
      if (mounted) setState(() => _failure = '网页登录组件无法刷新，请返回后重新打开');
    }
  }

  @override
  void dispose() {
    _usernameHint.dispose();
    final session = _session;
    if (!_closing && session != null) unawaited(_disposeSession(session));
    super.dispose();
  }

  Future<void> _disposeSession(LoginBrowserSession session) async {
    try {
      await session.close();
    } on LoginFailure catch (error) {
      _reportCleanupFailure(error);
    }
  }

  void _reportCleanupFailure(LoginFailure failure) {
    final messenger = _messenger;
    if (messenger != null && messenger.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: failure,
        library: 'ZFHelper web login cleanup',
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(_leave(false));
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('学校网页登录'),
        actions: [
          IconButton(
            tooltip: '刷新网页',
            onPressed: _controller == null || _closing ? null : _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: widget.viewModel,
          builder: (context, _) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  _origin,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_showBrowser && _progress < 100)
                LinearProgressIndicator(value: _progress / 100),
              Expanded(
                child: IgnorePointer(ignoring: _closing, child: _browser()),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .45,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _footer(),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _browser() {
    final session = _session;
    if (!_showBrowser || session == null) {
      return Center(
        child: _initializing || _closing
            ? const CircularProgressIndicator()
            : const Text('网页登录窗口已关闭'),
      );
    }
    session.beginViewCreation();
    return InAppWebView(
      webViewEnvironment: session.environment,
      keepAlive: session.keepAlive,
      initialSettings: session.settings,
      initialUrlRequest: URLRequest(url: WebUri('about:blank')),
      onWebViewCreated: (controller) async {
        if (!session.bindController(controller) || !mounted || _closing) return;
        _controller = controller;
        try {
          await controller.loadUrl(
            urlRequest: URLRequest(url: WebUri.uri(widget.profile.browserUri)),
          );
        } on PlatformException {
          if (mounted) setState(() => _failure = '无法打开学校网页，请返回后重试');
        }
      },
      onLoadStart: (controller, url) {
        if (!mounted || _closing) return;
        setState(() {
          _progress = 0;
          _failure = null;
          if (url != null && ['http', 'https'].contains(url.scheme)) {
            _origin = url.uriValue.origin;
          }
        });
      },
      onProgressChanged: (controller, progress) {
        if (mounted && !_closing) setState(() => _progress = progress);
      },
      onReceivedError: (controller, request, error) {
        if (!mounted || request.isForMainFrame != true || _closing) return;
        setState(() => _failure = '网页加载失败，请检查网络和教务地址后重试');
      },
      onReceivedHttpError: (controller, request, response) {
        if (!mounted || request.isForMainFrame != true || _closing) return;
        setState(() => _failure = '学校网页返回 HTTP ${response.statusCode}，请稍后重试');
      },
      shouldOverrideUrlLoading: (controller, action) async {
        final scheme = action.request.url?.scheme;
        if (scheme == 'http' || scheme == 'https' || scheme == 'about') {
          return NavigationActionPolicy.ALLOW;
        }
        if (mounted) setState(() => _failure = '该链接需要外部应用，当前网页登录窗口无法打开');
        return NavigationActionPolicy.CANCEL;
      },
    );
  }

  Widget _footer() {
    final failure =
        _failure ??
        (_submitted ? widget.viewModel.state.failure?.message : null);
    final busy = _initializing || _verifying || _closing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (failure != null) ...[
          AuthNotice(message: failure),
          const SizedBox(height: 12),
        ],
        if (_showBrowser) ...[
          if (_needsUsername) ...[
            TextField(
              key: const ValueKey('web-login-username'),
              controller: _usernameHint,
              enabled: !busy,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: '账号或学号',
                helperText: '学校未返回学号，补充后可继续验证当前会话',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
          ],
          const Text('在学校页面完成登录后，点击下方按钮验证教务账号。'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy ? null : _verify,
            child: Text(_verifying ? '正在验证教务会话…' : '已登录，验证并返回'),
          ),
        ] else if (!busy)
          FilledButton(
            onPressed: () => _leave(_verified),
            child: const Text('清理网页登录窗口并返回'),
          ),
      ],
    );
  }
}
