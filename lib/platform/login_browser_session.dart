import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:zf_core/zf_core.dart';

const _cookieInfoChannel = MethodChannel('zfhelper/login_cookies');
const _environmentChannelPrefix =
    'com.pichillilorenzo/flutter_webview_environment_';
const _millisecondsPerSecond = 1000;
const _directoryPrefix = 'zfhelper-login-';
const _viewCreationWait = Duration(seconds: 3);
const _nativeDisposalWait = Duration(seconds: 5);
const _directoryDeleteWaits = [
  Duration(milliseconds: 50),
  Duration(milliseconds: 100),
  Duration(milliseconds: 200),
  Duration(milliseconds: 350),
  Duration(milliseconds: 500),
  Duration(milliseconds: 700),
];
const _retryableWindowsFileErrors = {5, 32, 145};
const _cookieInfoUnavailable = LoginFailure(
  LoginFailureCode.browserRequired,
  '当前 Android System WebView 无法提供完整会话信息，请更新后重试或使用密码登录',
);
const _invalidBrowserCookies = LoginFailure(
  LoginFailureCode.protocol,
  '网页登录返回的会话信息不完整或格式无效',
);

/// Owns the browser data used during one interactive login.
///
/// The view uses [environment], [settings] and [keepAlive], initially loading
/// only `about:blank`. Call [beginViewCreation] before creating the widget and
/// [bindController] when native creation finishes. Load the school URL only
/// if binding returns `true`. Remove the widget before calling [close].
final class LoginBrowserSession {
  LoginBrowserSession._({
    required this._platform,
    required this.environment,
    required this._directory,
  }) : _cookies = CookieManager.fromPlatformCreationParams(
         PlatformCookieManagerCreationParams(
           webViewEnvironment: environment?.platform,
         ),
       );

  static Object? _androidOwner;
  static final Set<LoginBrowserSession> _pendingCleanup = {};

  final TargetPlatform _platform;
  final io.Directory? _directory;
  final CookieManager _cookies;
  final InAppWebViewKeepAlive _keepAlive = InAppWebViewKeepAlive();
  final Completer<void> _viewCreated = Completer<void>();
  Future<void>? _creationWaitInProgress;
  InAppWebViewController? _controller;
  bool _creationRequested = false;
  bool _viewDisposed = false;

  /// The private Windows environment shared with the view and CookieManager.
  final WebViewEnvironment? environment;

  /// The native view lease owned and explicitly disposed by this session.
  InAppWebViewKeepAlive get keepAlive => _keepAlive;

  bool _closing = false;
  bool _closed = false;
  bool _cookiesCleared = false;
  bool _environmentDisposed = false;
  bool _androidStorageCleared = false;
  bool _androidCacheCleared = false;
  Future<void>? _closeInProgress;

  /// Records that the UI is creating the view associated with [keepAlive].
  void beginViewCreation() {
    if (_creationRequested) return;
    _ensureReadable();
    _creationRequested = true;
  }

  /// Waits briefly for creation while the UI keeps the initial view mounted.
  ///
  /// Binding during this wait cannot start school navigation. On completion,
  /// the UI can remove the widget and call [close] to await native disposal.
  Future<void> waitForViewCreation() async {
    _closing = true;
    try {
      await _awaitViewCreation();
    } on TimeoutException {
      _pendingCleanup.add(this);
      if (identical(_androidOwner, this)) _androidOwner = null;
      throw const LoginFailure(
        LoginFailureCode.storage,
        '网页登录组件尚未完成创建；可以返回，创建完成后将清理',
      );
    }
  }

  Future<void> _awaitViewCreation() {
    if (!_creationRequested || _viewCreated.isCompleted) {
      return Future<void>.value();
    }
    return _creationWaitInProgress ??= _viewCreated.future.timeout(
      _viewCreationWait,
    );
  }

  /// Binds native ownership and permits navigation only while still open.
  bool bindController(InAppWebViewController controller) {
    _controller = controller;
    _creationRequested = true;
    if (!_viewCreated.isCompleted) _viewCreated.complete();
    if (!_closing && !_closed) return true;
    if (_closeInProgress != null || _pendingCleanup.contains(this) || _closed) {
      _viewDisposed = false;
      _closed = false;
      _pendingCleanup.add(this);
      unawaited(_finishLateCleanup());
    }
    return false;
  }

  /// Retries retained cleanup before opening another browser login.
  static Future<void> retryPendingCleanup() async {
    for (final session in List<LoginBrowserSession>.of(_pendingCleanup)) {
      await session.close();
    }
  }

  /// The view configuration compatible with this session's cookie reader.
  InAppWebViewSettings get settings => InAppWebViewSettings(
    javaScriptEnabled: true,
    domStorageEnabled: true,
    useShouldOverrideUrlLoading: true,
    saveFormData: false,
    cacheEnabled: false,
    // Windows 0.6.0's CookieManager uses the environment's regular hidden
    // controller. Its cookies cannot be read from a separate InPrivate view.
    incognito: _platform == TargetPlatform.android,
    isInspectable: false,
  );

  /// Opens a clean browser session without loading a school or login URL.
  static Future<LoginBrowserSession> open() async {
    _disablePluginLogs();
    final platform = defaultTargetPlatform;
    if (kIsWeb ||
        ![TargetPlatform.android, TargetPlatform.windows].contains(platform)) {
      throw const LoginFailure(
        LoginFailureCode.browserRequired,
        '当前平台尚不支持网页登录，请使用密码登录',
      );
    }
    if (platform == TargetPlatform.android && _androidOwner != null) {
      throw const LoginFailure(
        LoginFailureCode.browserRequired,
        '请先关闭已有的网页登录页面',
      );
    }
    final reservation = Object();
    if (platform == TargetPlatform.android) _androidOwner = reservation;

    io.Directory? directory;
    WebViewEnvironment? environment;
    LoginBrowserSession? session;
    try {
      await retryPendingCleanup();
      if (platform == TargetPlatform.android) {
        if (!await WebViewFeature.isFeatureSupported(
          WebViewFeature.GET_COOKIE_INFO,
        )) {
          throw _cookieInfoUnavailable;
        }
        await InAppWebViewController.setWebContentsDebuggingEnabled(false);
      } else {
        directory = await io.Directory.systemTemp.createTemp(_directoryPrefix);
        environment = await WebViewEnvironment.create(
          settings: WebViewEnvironmentSettings(
            userDataFolder: directory.path,
            allowSingleSignOnUsingOSPrimaryAccount: false,
          ),
        );
      }

      session = LoginBrowserSession._(
        platform: platform,
        environment: environment,
        directory: directory,
      );
      if (platform == TargetPlatform.android) _androidOwner = session;
      await session._clearBrowserData();
      // The same cleanup must run again after the user visits login pages.
      session._cookiesCleared = false;
      session._androidStorageCleared = false;
      session._androidCacheCleared = false;
      return session;
    } on Exception catch (error) {
      try {
        if (session != null) {
          await session.close();
        } else {
          if (environment != null) await _disposeEnvironment(environment);
          if (directory != null) await _deleteOwnDirectory(directory);
        }
      } on Exception {
        throw const LoginFailure(
          LoginFailureCode.storage,
          '网页登录启动失败，临时浏览器数据未能完成清理，请重试',
        );
      } finally {
        if (identical(_androidOwner, reservation) ||
            identical(_androidOwner, session)) {
          _androidOwner = null;
        }
      }
      throw _safeFailure(error, '无法启动网页登录，请检查系统 WebView 后重试');
    }
  }

  /// Reads only cookies applicable to the profile's identity endpoint.
  Future<List<LoginCookie>> readCookies(SchoolConnection profile) async {
    _ensureReadable();
    try {
      final List<LoginCookie> result;
      if (_platform == TargetPlatform.android) {
        final raw = await _cookieInfoChannel.invokeListMethod<String>(
          'getCookieInfo',
          {'url': profile.accountUri.toString()},
        );
        if (raw == null) throw _invalidBrowserCookies;
        final readAt = DateTime.now().toUtc();
        result = raw.map((value) => _androidCookie(value, readAt)).toList();
      } else {
        final values = await _cookies.getCookies(
          url: WebUri.uri(profile.accountUri),
        );
        result = values.map(_windowsCookie).toList();
      }
      _ensureReadable();
      return List<LoginCookie>.unmodifiable(result);
    } on FormatException {
      throw _invalidBrowserCookies;
    } on ArgumentError {
      throw _invalidBrowserCookies;
    } on TypeError {
      throw _invalidBrowserCookies;
    } on Exception catch (error) {
      throw _safeFailure(error, '无法读取网页登录会话，请重试');
    }
  }

  /// Awaits native view disposal, then clears data and releases the environment.
  ///
  /// Concurrent calls share one cleanup. A failed cleanup can be retried;
  /// completed stages are not replayed against an already disposed profile.
  /// Failures retain cleanup ownership but release the Android page lease;
  /// the UI may report the error and return without trapping the user here.
  Future<void> close() {
    if (_closed) return Future<void>.value();
    final pending = _closeInProgress;
    if (pending != null) return pending;
    _closing = true;
    final operation = _close();
    _closeInProgress = operation;
    return operation;
  }

  Future<void> _close() async {
    try {
      await _disposeNativeView();
      await _clearBrowserData();
      final browserEnvironment = environment;
      if (browserEnvironment != null && !_environmentDisposed) {
        await _disposeEnvironment(browserEnvironment);
        _environmentDisposed = true;
      }
      final directory = _directory;
      if (directory != null) await _deleteOwnDirectory(directory);
      _closed = true;
      _pendingCleanup.remove(this);
    } on TimeoutException {
      _pendingCleanup.add(this);
      throw const LoginFailure(
        LoginFailureCode.storage,
        '网页登录组件尚未完成创建或关闭；可以返回，稍后将重试清理',
      );
    } on Exception {
      _pendingCleanup.add(this);
      throw const LoginFailure(
        LoginFailureCode.storage,
        '网页登录数据清理失败；可以返回，重新打开网页前将重试清理',
      );
    } finally {
      _closeInProgress = null;
      if (identical(_androidOwner, this)) _androidOwner = null;
    }
  }

  Future<void> _disposeNativeView() async {
    if (_viewDisposed || !_creationRequested) return;
    await _awaitViewCreation();
    if (_platform == TargetPlatform.android) {
      final viewId = _controller?.getViewId();
      if (viewId is! String || viewId.isEmpty) {
        throw const LoginFailure(LoginFailureCode.storage, '网页登录组件标识无效');
      }
      // Android 1.1.3 disposeKeepAlive acknowledges before its about:blank
      // onPageFinished calls destroy(). The bridge completes destruction on
      // the UI thread, preserving the plugin's own resource cleanup first.
      await _cookieInfoChannel
          .invokeMethod<void>('destroyLoginWebView', {'keepAliveId': viewId})
          .timeout(_nativeDisposalWait);
    } else {
      // Windows 0.6.0 erases the owned view and closes its native controller
      // before acknowledging this public operation.
      await InAppWebViewController.disposeKeepAlive(_keepAlive)
          .timeout(_nativeDisposalWait);
    }
    _viewDisposed = true;
    _controller = null;
  }

  Future<void> _finishLateCleanup() async {
    try {
      await close();
    } on LoginFailure catch (error, stackTrace) {
      // Keep the failed resource in _pendingCleanup and surface only the
      // sanitized failure; no URL, native exception text or cookies are logged.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'ZFHelper deferred browser cleanup',
        ),
      );
    }
  }

  Future<void> _clearBrowserData() async {
    if (!_cookiesCleared) {
      final removed = await _cookies.deleteAllCookies();
      // Android reports false when there were no cookies to remove. Windows
      // 0.6.0 instead returns the success of Network.clearBrowserCookies.
      if (_platform == TargetPlatform.windows && !removed) {
        throw const LoginFailure(LoginFailureCode.storage, '网页登录 Cookie 清理失败');
      }
      _cookiesCleared = true;
    }
    if (_platform != TargetPlatform.android) return;
    if (!_androidStorageCleared) {
      await WebStorageManager.instance().deleteAllData();
      _androidStorageCleared = true;
    }
    if (!_androidCacheCleared) {
      await InAppWebViewController.clearAllCache();
      _androidCacheCleared = true;
    }
  }

  static Future<void> _disposeEnvironment(WebViewEnvironment environment) {
    // Windows 0.6.0 binds its Dart dispose channel to the factory object's id
    // in WindowsWebViewEnvironment.create(), while native uses env.id.
    return MethodChannel('$_environmentChannelPrefix${environment.id}')
        .invokeMethod<void>('dispose', const <String, Object?>{});
  }

  static Future<void> _deleteOwnDirectory(io.Directory directory) async {
    // This handle came only from createTemp; never delete a path from a URL,
    // school profile, plugin response or persisted user setting.
    for (var attempt = 0; ; attempt++) {
      if (!await directory.exists()) return;
      final allowedParent = await io.Directory.systemTemp
          .resolveSymbolicLinks();
      final resolved = io.Directory(await directory.resolveSymbolicLinks());
      final name = resolved.uri.pathSegments
          .where((part) => part.isNotEmpty)
          .last;
      if (resolved.parent.path != allowedParent ||
          !name.startsWith(_directoryPrefix)) {
        throw const LoginFailure(
          LoginFailureCode.storage,
          '临时浏览器数据目录不在本次会话的清理范围内',
        );
      }
      try {
        await resolved.delete(recursive: true);
        return;
      } on io.FileSystemException catch (error) {
        if (!io.Platform.isWindows ||
            !_retryableWindowsFileErrors.contains(error.osError?.errorCode) ||
            attempt >= _directoryDeleteWaits.length) {
          rethrow;
        }
        // WebView2 process teardown may outlive controller.Close. The waits
        // total 1.9 seconds and never cover unrelated filesystem failures.
        await Future<void>.delayed(_directoryDeleteWaits[attempt]);
      }
    }
  }

  static LoginCookie _androidCookie(String raw, DateTime readAt) {
    if (!raw.split(';').first.contains('=')) throw _invalidBrowserCookies;
    final cookie = io.Cookie.fromSetCookieValue(raw);
    final maxAge = cookie.maxAge;
    final expiry = maxAge == null
        ? cookie.expires
        : maxAge <= 0
        ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
        : readAt.add(Duration(seconds: maxAge));
    return LoginCookie(
      name: cookie.name,
      value: cookie.value,
      domain: cookie.domain,
      path: cookie.path,
      secure: cookie.secure,
      httpOnly: cookie.httpOnly,
      expiresAt: expiry,
    );
  }

  static LoginCookie _windowsCookie(Cookie cookie) {
    final value = cookie.value;
    final secure = cookie.isSecure;
    final httpOnly = cookie.isHttpOnly;
    final sessionOnly = cookie.isSessionOnly;
    if (value is! String ||
        secure == null ||
        httpOnly == null ||
        sessionOnly == null ||
        cookie.path == null ||
        cookie.domain == null) {
      throw _invalidBrowserCookies;
    }
    DateTime? expiry;
    if (!sessionOnly) {
      final seconds = cookie.expiresDate;
      if (seconds == null || seconds < 0) throw _invalidBrowserCookies;
      // Windows 0.6.0 cookie_manager.cpp forwards CDP expires in seconds,
      // despite the platform Cookie DTO documenting milliseconds.
      expiry = DateTime.fromMillisecondsSinceEpoch(
        seconds * _millisecondsPerSecond,
        isUtc: true,
      );
    }
    return LoginCookie(
      name: cookie.name,
      value: value,
      domain: cookie.domain,
      path: cookie.path,
      secure: secure,
      httpOnly: httpOnly,
      expiresAt: expiry,
    );
  }

  static void _disablePluginLogs() {
    PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
    PlatformInAppBrowser.debugLoggingSettings.enabled = false;
    PlatformWebViewEnvironment.debugLoggingSettings.enabled = false;
  }

  static LoginFailure _safeFailure(Object error, String message) {
    if (error is LoginFailure) return error;
    if (error is PlatformException && error.code == 'cookie_info_unavailable') {
      return _cookieInfoUnavailable;
    }
    return LoginFailure(LoginFailureCode.browserRequired, message);
  }

  void _ensureReadable() {
    if (_closing || _closed) {
      throw const LoginFailure(LoginFailureCode.cancelled, '网页登录已结束');
    }
  }
}
