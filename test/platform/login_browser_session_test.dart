import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zf_core/zf_core.dart';
import 'package:zfhelper/platform/login_browser_session.dart';

const _cookieChannel = MethodChannel('zfhelper/login_cookies');
const _environmentPrefix = 'com.pichillilorenzo/flutter_webview_environment_';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final backend = _FakePlatform(messenger);
  final originalPlatform = InAppWebViewPlatform.instance;
  final profile = SchoolConnection(
    name: 'Example university',
    baseUri: Uri.parse('https://school.example/jwglxt/'),
  );

  setUpAll(() => InAppWebViewPlatform.instance = backend);
  setUp(() {
    backend.reset();
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(_cookieChannel, null);
    for (final channel in backend.environmentChannels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });
  tearDownAll(() {
    if (originalPlatform != null) {
      InAppWebViewPlatform.instance = originalPlatform;
    }
  });

  test(
    'Windows uses an isolated regular profile and exports the account URL',
    () async {
      final session = await LoginBrowserSession.open();
      addTearDown(session.close);
      final environment = session.environment!;
      final folder = environment.settings!.userDataFolder!;
      expect(await io.Directory(folder).exists(), isTrue);
      expect(backend.cookieEnvironmentIds, [environment.id]);
      expect(session.settings.incognito, isFalse);
      expect(
        PlatformInAppWebViewController.debugLoggingSettings.enabled,
        isFalse,
      );
      expect(PlatformInAppBrowser.debugLoggingSettings.enabled, isFalse);
      expect(PlatformWebViewEnvironment.debugLoggingSettings.enabled, isFalse);

      final expiry = DateTime.utc(2035, 1, 2, 13, 45);
      backend.cookies = [
        Cookie(
          name: 'SID',
          value: 'specific',
          domain: 'school.example',
          path: '/jwglxt/',
          isSecure: true,
          isHttpOnly: true,
          isSessionOnly: false,
          expiresDate: expiry.millisecondsSinceEpoch ~/ 1000,
        ),
        Cookie(
          name: 'SID',
          value: 'root',
          domain: '.school.example',
          path: '/',
          isSecure: false,
          isHttpOnly: false,
          isSessionOnly: true,
          expiresDate: -1,
        ),
      ];
      final cookies = await session.readCookies(profile);
      expect(backend.readUrl, profile.accountUri.toString());
      expect(cookies, hasLength(2));
      expect(cookies.first.expiresAt, expiry);
      expect(cookies.first.domain, 'school.example');
      expect(cookies.first.path, '/jwglxt/');
      expect(cookies.first.secure, isTrue);
      expect(cookies.first.httpOnly, isTrue);
      expect(cookies.last.domain, '.school.example');
      expect(cookies.last.path, '/');
      expect(cookies.last.secure, isFalse);
      expect(cookies.last.httpOnly, isFalse);
      expect(cookies.last.expiresAt, isNull);

      await session.close();
      expect(await io.Directory(folder).exists(), isFalse);
      expect(backend.disposedIds, [environment.id]);
      await session.close();
      expect(backend.disposedIds, [environment.id]);
    },
  );

  test(
    'Windows profiles are distinct and closing one uses only its own id',
    () async {
      final first = await LoginBrowserSession.open();
      final second = await LoginBrowserSession.open();
      addTearDown(first.close);
      addTearDown(second.close);
      expect(first.environment!.id, isNot(second.environment!.id));
      expect(
        first.environment!.settings!.userDataFolder,
        isNot(second.environment!.settings!.userDataFolder),
      );
      await first.close();
      expect(backend.disposedIds, [first.environment!.id]);
      expect(
        await io.Directory(second.environment!.settings!.userDataFolder!)
            .exists(),
        isTrue,
      );
    },
  );

  test(
    'Windows cleanup can retry without repeating completed cookie clearing',
    () async {
      final session = await LoginBrowserSession.open();
      addTearDown(session.close);
      backend.disposeFailures = 1;
      await expectLater(
        session.close(),
        throwsA(_failure(LoginFailureCode.storage)),
      );
      final cookieCalls = backend.cookieClearCalls;
      await expectLater(
        session.readCookies(profile),
        throwsA(_failure(LoginFailureCode.cancelled)),
      );
      await session.close();
      expect(backend.cookieClearCalls, cookieCalls);
      expect(backend.disposeAttempts, 2);
      expect(backend.disposedIds, [session.environment!.id]);
    },
  );

  test(
    'Windows refuses missing security metadata instead of guessing',
    () async {
      final session = await LoginBrowserSession.open();
      addTearDown(session.close);
      backend.cookies = [
        Cookie(
          name: 'SID',
          value: 'opaque',
          domain: 'school.example',
          path: '/',
          isHttpOnly: true,
          isSessionOnly: true,
        ),
      ];
      await expectLater(
        session.readCookies(profile),
        throwsA(_failure(LoginFailureCode.protocol)),
      );
    },
  );

  test(
    'Android raw attributes retain expiry and duplicate cookie names',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final session = await LoginBrowserSession.open();
      addTearDown(session.close);
      expect(session.environment, isNull);
      expect(session.settings.incognito, isTrue);
      expect(backend.webContentsDebuggingEnabled, isFalse);
      final expiry = DateTime.utc(2035, 1, 2, 13, 45);
      MethodCall? received;
      messenger.setMockMethodCallHandler(_cookieChannel, (call) async {
        received = call;
        return [
          'SID=secure; Domain=school.example; Path=/jwglxt/; '
              'Secure; HttpOnly; Expires=${io.HttpDate.format(expiry)}',
          'SID=session; Path=/',
          'TTL=short; Path=/jwglxt/; Max-Age=120',
        ];
      });
      final beforeRead = DateTime.now().toUtc();
      final cookies = await session.readCookies(profile);
      final afterRead = DateTime.now().toUtc();
      expect(received!.method, 'getCookieInfo');
      expect(received!.arguments, {'url': profile.accountUri.toString()});
      expect(cookies.map((cookie) => cookie.name), ['SID', 'SID', 'TTL']);
      expect(cookies.first.expiresAt, expiry);
      expect(cookies.first.secure, isTrue);
      expect(cookies.first.httpOnly, isTrue);
      expect(cookies[1].domain, isNull);
      expect(cookies[1].expiresAt, isNull);
      expect(cookies[1].secure, isFalse);
      expect(cookies[1].httpOnly, isFalse);
      final ttl = cookies.last.expiresAt!;
      expect(
        ttl.isBefore(beforeRead.add(const Duration(seconds: 120))),
        isFalse,
      );
      expect(ttl.isAfter(afterRead.add(const Duration(seconds: 120))), isFalse);
      await session.close();
      expect(backend.storageClearCalls, 2);
      expect(backend.cacheClearCalls, 2);
    },
  );

  test(
    'Android missing GET_COOKIE_INFO fails explicitly and releases ownership',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      backend.cookieInfoSupported = false;
      await expectLater(
        LoginBrowserSession.open(),
        throwsA(_failure(LoginFailureCode.browserRequired)),
      );
      backend.cookieInfoSupported = true;
      final session = await LoginBrowserSession.open();
      addTearDown(session.close);
    },
  );

  test(
    'Android second session cannot clear the active session store',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final session = await LoginBrowserSession.open();
      addTearDown(session.close);
      final clears = backend.cookieClearCalls;
      await expectLater(
        LoginBrowserSession.open(),
        throwsA(_failure(LoginFailureCode.browserRequired)),
      );
      expect(backend.cookieClearCalls, clears);
      await session.close();
      final next = await LoginBrowserSession.open();
      addTearDown(next.close);
    },
  );

  test('platform exceptions do not expose cookies or ticket values', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final session = await LoginBrowserSession.open();
    addTearDown(session.close);
    const secret = 'synthetic-cookie-and-ticket';
    messenger.setMockMethodCallHandler(_cookieChannel, (_) async {
      throw PlatformException(code: 'read_failure', message: secret);
    });
    await expectLater(
      session.readCookies(profile),
      throwsA(
        _failure(LoginFailureCode.browserRequired).having(
          (error) => error.toString(),
          'safe error',
          isNot(contains(secret)),
        ),
      ),
    );
  });

  test(
    'Windows cleanup waits for native keepalive disposal before clearing',
    () async {
      final session = await LoginBrowserSession.open();
      addTearDown(session.close);
      session.beginViewCreation();
      expect(
        session.bindController(
          InAppWebViewController.fromPlatform(
            platform: _FakeController(backend),
          ),
        ),
        isTrue,
      );
      backend.viewDisposalGate = Completer<void>();
      final closing = session.close();
      await backend.viewDisposalStarted.future;
      expect(backend.cookieClearCalls, 1);
      expect(backend.disposedIds, isEmpty);
      backend.viewDisposalGate!.complete();
      await closing;
      expect(backend.viewDisposalCalls, 1);
      expect(backend.cookieClearCalls, 2);
      expect(backend.disposedIds, [session.environment!.id]);
    },
  );

  test(
    'creation finishing during close cannot start school navigation',
    () async {
      final session = await LoginBrowserSession.open();
      addTearDown(session.close);
      session.beginViewCreation();
      final closing = session.close();
      expect(
        session.bindController(
          InAppWebViewController.fromPlatform(
            platform: _FakeController(backend),
          ),
        ),
        isFalse,
      );
      await closing;
      expect(backend.viewDisposalCalls, 1);
      expect(backend.cookieClearCalls, 2);
    },
  );

  test(
    'waiting for creation keeps the native view until explicit close',
    () async {
      final session = await LoginBrowserSession.open();
      addTearDown(session.close);
      session.beginViewCreation();
      final creation = session.waitForViewCreation();
      // A rebuild of the still-mounted widget is harmless during the wait.
      session.beginViewCreation();
      expect(
        session.bindController(
          InAppWebViewController.fromPlatform(
            platform: _FakeController(backend),
          ),
        ),
        isFalse,
      );
      await creation;
      expect(backend.viewDisposalCalls, 0);
      expect(backend.cookieClearCalls, 1);
      await session.close();
      expect(backend.viewDisposalCalls, 1);
    },
  );

  test(
    'creation timeout is retryable and late Android creation is destroyed',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final session = await LoginBrowserSession.open();
      addTearDown(session.close);
      session.beginViewCreation();
      await expectLater(
        session.close(),
        throwsA(_failure(LoginFailureCode.storage)),
      );
      final nativeCalls = <MethodCall>[];
      messenger.setMockMethodCallHandler(_cookieChannel, (call) async {
        nativeCalls.add(call);
        return null;
      });
      expect(
        session.bindController(
          InAppWebViewController.fromPlatform(
            platform: _FakeController(backend),
          ),
        ),
        isFalse,
      );
      await LoginBrowserSession.retryPendingCleanup();
      expect(nativeCalls.single.method, 'destroyLoginWebView');
      expect(nativeCalls.single.arguments, {'keepAliveId': 'bound-view'});
      final next = await LoginBrowserSession.open();
      addTearDown(next.close);
    },
  );

  test(
    'failed Android cleanup releases the page lease and retries before open',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final session = await LoginBrowserSession.open();
      addTearDown(session.close);
      backend.cacheFailures = 1;
      await expectLater(
        session.close(),
        throwsA(_failure(LoginFailureCode.storage)),
      );
      final next = await LoginBrowserSession.open();
      addTearDown(next.close);
      expect(backend.cacheClearCalls, 4);
      // Retrying the previous session must not release the new session's lease.
      await expectLater(
        LoginBrowserSession.open(),
        throwsA(_failure(LoginFailureCode.browserRequired)),
      );
    },
  );
}

TypeMatcher<LoginFailure> _failure(LoginFailureCode code) =>
    isA<LoginFailure>().having((failure) => failure.code, 'code', code);

final class _FakePlatform extends InAppWebViewPlatform {
  _FakePlatform(this.messenger);
  final TestDefaultBinaryMessenger messenger;
  final List<MethodChannel> environmentChannels = [];
  final List<String?> cookieEnvironmentIds = [];
  final List<String> disposedIds = [];
  List<Cookie> cookies = [];
  String? readUrl;
  bool cookieInfoSupported = true;
  bool? webContentsDebuggingEnabled;
  int cookieClearCalls = 0;
  int storageClearCalls = 0;
  int cacheClearCalls = 0;
  int disposeFailures = 0;
  int disposeAttempts = 0;
  int viewDisposalCalls = 0;
  int cacheFailures = 0;
  Completer<void>? viewDisposalGate;
  Completer<void> viewDisposalStarted = Completer<void>();
  int _nextEnvironment = 0;

  void reset() {
    environmentChannels.clear();
    cookieEnvironmentIds.clear();
    disposedIds.clear();
    cookies = [];
    readUrl = null;
    cookieInfoSupported = true;
    webContentsDebuggingEnabled = null;
    cookieClearCalls = 0;
    storageClearCalls = 0;
    cacheClearCalls = 0;
    disposeFailures = 0;
    disposeAttempts = 0;
    viewDisposalCalls = 0;
    cacheFailures = 0;
    viewDisposalGate = null;
    viewDisposalStarted = Completer<void>();
  }

  _FakeEnvironment environment(WebViewEnvironmentSettings? settings) {
    final id = 'test-${_nextEnvironment++}';
    final channel = MethodChannel('$_environmentPrefix$id');
    environmentChannels.add(channel);
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'dispose');
      disposeAttempts++;
      if (disposeFailures > 0) {
        disposeFailures--;
        throw PlatformException(code: 'busy', message: 'synthetic-ticket');
      }
      disposedIds.add(id);
      return null;
    });
    return _FakeEnvironment(
      this,
      id,
      PlatformWebViewEnvironmentCreationParams(settings: settings),
    );
  }

  @override
  PlatformWebViewEnvironment createPlatformWebViewEnvironmentStatic() =>
      _FakeEnvironment(
        this,
        'factory',
        const PlatformWebViewEnvironmentCreationParams(),
      );

  @override
  PlatformCookieManager createPlatformCookieManager(
    PlatformCookieManagerCreationParams params,
  ) {
    cookieEnvironmentIds.add(params.webViewEnvironment?.id);
    return _FakeCookies(this, params);
  }

  @override
  PlatformWebViewFeature createPlatformWebViewFeatureStatic() =>
      _FakeFeatures(this);

  @override
  PlatformInAppWebViewController createPlatformInAppWebViewControllerStatic() =>
      _FakeController(this);

  @override
  PlatformWebStorageManager createPlatformWebStorageManager(
    PlatformWebStorageManagerCreationParams params,
  ) => _FakeStorage(this, params);
}

final class _FakeEnvironment extends PlatformWebViewEnvironment {
  _FakeEnvironment(
    this.backend,
    this.id,
    PlatformWebViewEnvironmentCreationParams params,
  ) : super.implementation(params);
  final _FakePlatform backend;
  @override
  final String id;

  @override
  Future<PlatformWebViewEnvironment> create({
    WebViewEnvironmentSettings? settings,
  }) async => backend.environment(settings);
}

final class _FakeCookies extends PlatformCookieManager {
  _FakeCookies(this.backend, PlatformCookieManagerCreationParams params)
    : super.implementation(params);
  final _FakePlatform backend;

  @override
  Future<bool> deleteAllCookies() async {
    backend.cookieClearCalls++;
    return true;
  }

  @override
  Future<List<Cookie>> getCookies({
    required WebUri url,
    PlatformInAppWebViewController? iosBelow11WebViewController,
    PlatformInAppWebViewController? webViewController,
  }) async {
    backend.readUrl = url.toString();
    return backend.cookies;
  }
}

final class _FakeFeatures extends PlatformWebViewFeature {
  _FakeFeatures(this.backend)
    : super.implementation(const PlatformWebViewFeatureCreationParams());
  final _FakePlatform backend;

  @override
  Future<bool> isFeatureSupported(WebViewFeature feature) async {
    expect(feature, WebViewFeature.GET_COOKIE_INFO);
    return backend.cookieInfoSupported;
  }
}

final class _FakeController extends PlatformInAppWebViewController {
  _FakeController(this.backend)
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 'test-static'),
      );
  final _FakePlatform backend;

  @override
  dynamic getViewId() => 'bound-view';

  @override
  Future<void> disposeKeepAlive(InAppWebViewKeepAlive keepAlive) async {
    backend.viewDisposalCalls++;
    if (!backend.viewDisposalStarted.isCompleted) {
      backend.viewDisposalStarted.complete();
    }
    final gate = backend.viewDisposalGate;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> setWebContentsDebuggingEnabled(bool debuggingEnabled) async {
    backend.webContentsDebuggingEnabled = debuggingEnabled;
  }

  @override
  Future<void> clearAllCache({bool includeDiskFiles = true}) async {
    backend.cacheClearCalls++;
    if (backend.cacheFailures > 0) {
      backend.cacheFailures--;
      throw PlatformException(
        code: 'cache_failure',
        message: 'synthetic-secret',
      );
    }
  }
}

final class _FakeStorage extends PlatformWebStorageManager {
  _FakeStorage(this.backend, PlatformWebStorageManagerCreationParams params)
    : super.implementation(params);
  final _FakePlatform backend;

  @override
  Future<void> deleteAllData() async {
    backend.storageClearCalls++;
  }
}
