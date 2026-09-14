import 'dart:async';

import 'account_scope.dart';
import 'authenticated_read_client.dart';
import 'login_gateway.dart';
import 'login_models.dart';
import 'school_connection.dart';

enum AuthPhase { idle, restoring, signingIn, captcha, checking, saving }

final class StoredLogin {
  const StoredLogin({
    required this.profile,
    required this.session,
    required this.method,
    this.credentials,
  });

  final SchoolConnection profile;
  final LoginSession session;
  final LoginMethod method;
  final LoginCredentials? credentials;
}

abstract interface class LoginVault {
  Future<SchoolConnection?> readSchool();
  Future<void> writeSchool(SchoolConnection profile);
  Future<StoredLogin?> read();
  Future<void> write(StoredLogin login);

  /// Deletes authentication only; the selected school remains configured.
  Future<void> clear();
}

/// A locally known identity without credentials or a claim of online validity.
final class AuthIdentity {
  AuthIdentity({
    required this.profile,
    required this.account,
    required this.generation,
  }) : scope = AccountScope(schoolId: profile.school.id, accountId: account.id);

  final SchoolConnection profile;
  final LoginAccount account;
  final AccountScope scope;

  /// The runtime identity generation, retained during automatic renewal.
  final int generation;
}

final class AuthSnapshot {
  const AuthSnapshot({
    required this.profile,
    required this.phase,
    required this.remembered,
    this.configuredProfile,
    this.account,
    this.knownIdentity,
    this.challenge,
    this.failure,
    this.storageFailure,
    this.pendingUsername,
  });

  final SchoolConnection? profile;
  final SchoolConnection? configuredProfile;
  final AuthPhase phase;
  final LoginAccount? account;
  final AuthIdentity? knownIdentity;
  final CaptchaRequired? challenge;
  final LoginFailure? failure;
  final LoginFailure? storageFailure;
  final String? pendingUsername;

  /// A saved login can be retained even after the school invalidates its session.
  final bool remembered;

  bool get isSignedIn => account != null;
  bool get isBusy => phase != AuthPhase.idle && phase != AuthPhase.captcha;
  bool get needsSignIn => switch (failure?.code) {
    LoginFailureCode.expired ||
    LoginFailureCode.invalidCredentials ||
    LoginFailureCode.accountLocked ||
    LoginFailureCode.browserRequired => true,
    _ => false,
  };
  bool get canRestoreSession =>
      !isSignedIn &&
      remembered &&
      knownIdentity != null &&
      challenge == null &&
      !needsSignIn;
}

final class _PendingLogin {
  _PendingLogin({
    required this.profile,
    required this.gateway,
    required this.method,
    required this.rememberPassword,
    this.credentials,
    this.expectedAccount,
    this.generation,
  });

  final SchoolConnection profile;
  final LoginGateway gateway;
  final LoginMethod method;
  final bool rememberPassword;
  final LoginCredentials? credentials;
  final LoginAccount? expectedAccount;
  final int? generation;
}

final class _ActiveLogin {
  const _ActiveLogin({
    required this.profile,
    required this.gateway,
    required this.session,
    required this.method,
    required this.generation,
    this.credentials,
  });

  final SchoolConnection profile;
  final LoginGateway gateway;
  final LoginSession session;
  final LoginMethod method;
  final int generation;
  final LoginCredentials? credentials;

  AuthIdentity get identity => AuthIdentity(
    profile: profile,
    account: session.account,
    generation: generation,
  );

  StoredLogin snapshot(List<LoginCookie> cookies) => StoredLogin(
    profile: profile,
    session: LoginSession(
      account: session.account,
      cookies: cookies,
      verifiedAt: session.verifiedAt,
    ),
    method: method,
    credentials: credentials,
  );
}

/// Owns verified authentication and cancellable sign-in attempts separately.
final class AuthRepository {
  AuthRepository({
    SchoolConnection? initialProfile,
    required this._gatewayFactory,
    required this._vault,
  }) : _profile = initialProfile;

  final LoginGatewayFactory _gatewayFactory;
  final LoginVault _vault;
  final _changes = StreamController<AuthSnapshot>.broadcast(sync: true);
  SchoolConnection? _profile;
  int _profileRevision = 0;
  _ActiveLogin? _active;
  AuthIdentity? _knownIdentity;
  int _generation = 0;
  _PendingLogin? _pending;
  Object? _attempt;
  AuthPhase _phase = AuthPhase.idle;
  CaptchaRequired? _challenge;
  LoginFailure? _failure;
  LoginFailure? _storageFailure;
  bool _remembered = false;
  bool _closed = false;
  Future<void> _storageTurn = Future<void>.value();
  Future<void>? _restoring;
  ({int generation, Future<void> future})? _checking;

  Stream<AuthSnapshot> get changes => _changes.stream;

  Future<void> configureSchool(SchoolConnection profile) async {
    if (_closed) throw StateError('Authentication repository is closed.');
    final revision = ++_profileRevision;
    await _withStorage(() async {
      await _vault.writeSchool(profile);
      if (_closed || revision != _profileRevision) return;
      _profile = profile;
      _emit();
    });
  }

  AuthSnapshot get state => AuthSnapshot(
    profile: _active?.profile ?? _knownIdentity?.profile ?? _profile,
    configuredProfile: _profile,
    phase: _phase,
    account: _active?.session.account,
    knownIdentity: _knownIdentity,
    challenge: _challenge,
    failure: _failure,
    storageFailure: _storageFailure,
    pendingUsername: _pending?.credentials?.username,
    remembered: _remembered,
  );

  /// Checks whether a captured identity may still publish local business data.
  ///
  /// Automatic renewal preserves the generation. Signing out, disposal, and a
  /// successful manual login invalidate it, including login to the same account.
  bool isCurrentIdentity(AuthIdentity identity) =>
      !_closed &&
      _knownIdentity?.generation == identity.generation &&
      _knownIdentity?.scope == identity.scope;

  /// Runs an account-bound read, retrying once after authentication renewal.
  ///
  /// [operation] must only query school data. A POST query is eligible, but a
  /// mutation is not. The supplied client expires when [operation] returns and
  /// never exposes cookies. A missing session, unsupported gateway, or stale
  /// account generation throws [LoginFailure] instead of producing cached data.
  Future<T> runRead<T>(
    AccountScope scope,
    Future<T> Function(AuthenticatedReadClient client) operation,
  ) async {
    var initial = _active;
    final known = _knownIdentity;
    if (_closed || (known != null && known.scope != scope)) {
      throw _readCancelled;
    }
    final checking = _checking;
    if (initial == null &&
        known != null &&
        checking?.generation == known.generation) {
      await checking!.future;
      _requireCurrentIdentity(known);
      initial = _active;
    }
    if (initial == null) throw _sessionUnavailable;
    final identity = initial.identity;
    for (var attempt = 0; ; attempt++) {
      final active = _readActive(identity);
      try {
        return await _executeRead(active, operation);
      } on LoginFailure catch (failure) {
        _requireCurrentIdentity(identity);
        if (failure.code != LoginFailureCode.expired) rethrow;
        if (attempt > 0) {
          if (identical(_active?.gateway, active.gateway)) {
            _expire(active, failure);
          }
          rethrow;
        }
        await _renewForRead(active);
      } on Object {
        _requireCurrentIdentity(identity);
        rethrow;
      }
    }
  }

  Future<bool> signInPassword(
    SchoolConnection profile,
    LoginCredentials credentials, {
    bool rememberPassword = false,
  }) async {
    final pending = _begin(
      profile,
      method: LoginMethod.password,
      credentials: credentials,
      rememberPassword: rememberPassword,
    );
    return _run(pending, () => pending.gateway.loginPassword(credentials));
  }

  Future<bool> signInCookies(
    SchoolConnection profile,
    List<LoginCookie> cookies, {
    required LoginMethod method,
    String usernameHint = '',
  }) async {
    final pending = _begin(profile, method: method);
    return _run(pending, () async {
      final session = await pending.gateway.importCookies(
        cookies,
        usernameHint: usernameHint,
      );
      return LoginSuccess(session);
    });
  }

  Future<bool> submitCaptcha(String code) async {
    final pending = _pending;
    if (pending == null || _challenge == null) {
      _failure = const LoginFailure(LoginFailureCode.captcha, '请重新开始登录');
      _emit();
      return false;
    }
    _phase = AuthPhase.signingIn;
    _failure = null;
    _emit();
    return _run(pending, () => pending.gateway.submitCaptcha(code.trim()));
  }

  Future<void> refreshCaptcha() async {
    final pending = _pending;
    if (pending == null || _challenge == null) return;
    _phase = AuthPhase.signingIn;
    _failure = null;
    _emit();
    try {
      final bytes = await pending.gateway.refreshCaptcha();
      if (!_isCurrent(pending)) return;
      _challenge = CaptchaRequired(image: bytes);
    } on LoginFailure catch (failure) {
      if (!_isCurrent(pending)) return;
      _failure = failure;
    }
    if (!_isCurrent(pending)) return;
    _phase = AuthPhase.captcha;
    _emit();
  }

  void cancelSignIn() {
    if (_pending == null && _phase != AuthPhase.restoring) return;
    _attempt = null;
    _pending?.gateway.close();
    _pending = null;
    _challenge = null;
    _failure = null;
    _phase = AuthPhase.idle;
    _emit();
  }

  Future<void> restore() => _restoring ??= _restore().whenComplete(() {
    _restoring = null;
  });

  Future<void> _restore() async {
    if (_closed ||
        _active != null ||
        _pending != null ||
        _phase == AuthPhase.restoring) {
      return;
    }
    final marker = Object();
    final profileRevision = _profileRevision;
    _attempt = marker;
    _phase = AuthPhase.restoring;
    _failure = null;
    _emit();
    StoredLogin? stored;
    SchoolConnection? savedSchool;
    try {
      stored = await _withStorage(() async {
        savedSchool = await _vault.readSchool();
        if (!_closed && profileRevision == _profileRevision) {
          _profile = savedSchool ?? _profile;
        }
        final record = await _vault.read();
        // Older installations stored the school only inside the login record.
        if (savedSchool == null && record != null) {
          await _vault.writeSchool(record.profile);
          savedSchool = record.profile;
        }
        return record;
      });
    } on LoginFailure catch (failure) {
      if (_closed || !identical(_attempt, marker)) return;
      _phase = AuthPhase.idle;
      _storageFailure = failure;
      _emit();
      return;
    }
    if (_closed || !identical(_attempt, marker)) return;
    _storageFailure = null;
    if (profileRevision == _profileRevision) {
      _profile = savedSchool ?? _profile;
    }
    if (stored == null) {
      _knownIdentity = null;
      _remembered = false;
      _generation++;
      _phase = AuthPhase.idle;
      _emit();
      return;
    }
    final record = stored;
    _remembered = true;
    final scope = AccountScope(
      schoolId: record.profile.school.id,
      accountId: record.session.account.id,
    );
    final previous = _knownIdentity;
    final identity = AuthIdentity(
      profile: record.profile,
      account: record.session.account,
      generation: previous?.scope == scope
          ? previous!.generation
          : ++_generation,
    );
    _knownIdentity = identity;
    final pending = _begin(
      record.profile,
      method: record.method,
      credentials: record.credentials,
      rememberPassword: record.credentials != null,
      expectedAccount: record.session.account,
      generation: identity.generation,
    );
    await _run(pending, () async {
      try {
        final session = await pending.gateway.importCookies(
          record.session.cookies,
          usernameHint: record.session.account.loginName,
        );
        _requireSameAccount(record.session.account, session.account);
        return LoginSuccess(session);
      } on LoginFailure catch (failure) {
        if (failure.code != LoginFailureCode.expired ||
            record.credentials == null) {
          rethrow;
        }
        if (!_isCurrent(pending)) {
          throw const LoginFailure(LoginFailureCode.cancelled, '登录已取消');
        }
        return pending.gateway.loginPassword(record.credentials!);
      }
    });
  }

  Future<void> checkSession() {
    final checking = _checking;
    if (checking != null && checking.generation == _knownIdentity?.generation) {
      return checking.future;
    }
    final active = _active;
    if (active == null || _pending != null) return Future<void>.value();
    final completion = Completer<void>();
    _checking = (
      generation: active.identity.generation,
      future: completion.future,
    );
    unawaited(_completeCheck(active, completion));
    return completion.future;
  }

  Future<void> _completeCheck(
    _ActiveLogin active,
    Completer<void> completion,
  ) async {
    try {
      await _check(active);
      completion.complete();
    } catch (error, stackTrace) {
      completion.completeError(error, stackTrace);
    } finally {
      if (identical(_checking?.future, completion.future)) _checking = null;
    }
  }

  Future<void> _check(_ActiveLogin active) async {
    _phase = AuthPhase.checking;
    _failure = null;
    _emit();
    try {
      final refreshed = await active.gateway.verifySession(
        usernameHint: active.session.account.loginName,
      );
      if (_closed || !identical(_active, active) || _pending != null) return;
      _requireSameAccount(active.session.account, refreshed.account);
      final next = _ActiveLogin(
        profile: active.profile,
        gateway: active.gateway,
        session: refreshed,
        method: active.method,
        generation: active.generation,
        credentials: active.credentials,
      );
      _active = next;
      _knownIdentity = next.identity;
      _phase = AuthPhase.idle;
      _emit();
      await _persist(next);
    } on LoginFailure catch (failure) {
      if (_closed || !identical(_active, active) || _pending != null) return;
      _phase = AuthPhase.idle;
      if (failure.code == LoginFailureCode.expired) {
        _expire(active, failure);
        final credentials = active.credentials;
        if (credentials != null) {
          final pending = _begin(
            active.profile,
            method: LoginMethod.password,
            credentials: credentials,
            rememberPassword: true,
            expectedAccount: active.session.account,
            generation: active.identity.generation,
          );
          await _run(pending, () => pending.gateway.loginPassword(credentials));
        }
        return;
      }
      _failure = failure;
      _emit();
    }
  }

  Future<void> signOut() async {
    _attempt = null;
    _checking = null;
    _knownIdentity = null;
    _generation++;
    _pending?.gateway.close();
    _active?.gateway.close();
    _pending = null;
    _active = null;
    _challenge = null;
    _failure = null;
    _storageFailure = null;
    _remembered = false;
    _phase = AuthPhase.idle;
    _emit();
    try {
      await _withStorage(_vault.clear);
    } on LoginFailure catch (failure) {
      if (_closed || _active != null) return;
      _storageFailure = failure;
      _emit();
    }
  }

  _PendingLogin _begin(
    SchoolConnection profile, {
    required LoginMethod method,
    bool rememberPassword = false,
    LoginCredentials? credentials,
    LoginAccount? expectedAccount,
    int? generation,
  }) {
    if (_closed) throw StateError('Authentication repository is closed.');
    _pending?.gateway.close();
    final pending = _PendingLogin(
      profile: profile,
      gateway: _gatewayFactory(profile),
      method: method,
      credentials: credentials,
      rememberPassword: rememberPassword,
      expectedAccount: expectedAccount,
      generation: generation,
    );
    _pending = pending;
    _attempt = pending;
    if (generation == null) {
      _profileRevision++;
      _profile = profile;
    }
    _phase = AuthPhase.signingIn;
    _challenge = null;
    _failure = null;
    _emit();
    return pending;
  }

  Future<bool> _run(
    _PendingLogin pending,
    Future<LoginStep> Function() operation,
  ) async {
    try {
      final result = await operation();
      if (!_isCurrent(pending)) return false;
      if (result case CaptchaRequired()) {
        _challenge = result;
        _phase = AuthPhase.captcha;
        _emit();
        return false;
      }
      final session = (result as LoginSuccess).session;
      if (pending.expectedAccount case final expected?) {
        _requireSameAccount(expected, session.account);
      }
      _active?.gateway.close();
      final active = _ActiveLogin(
        profile: pending.profile,
        gateway: pending.gateway,
        session: session,
        method: pending.method,
        generation: pending.generation ?? ++_generation,
        credentials: pending.rememberPassword ? pending.credentials : null,
      );
      _active = active;
      _knownIdentity = active.identity;
      _pending = null;
      _attempt = null;
      _challenge = null;
      _failure = null;
      _storageFailure = null;
      _remembered = false;
      _phase = AuthPhase.saving;
      _emit();
      await _persist(active);
      if (_closed || !identical(_active, active)) return false;
      if (_pending == null) _phase = AuthPhase.idle;
      _emit();
      return true;
    } on LoginFailure catch (failure) {
      if (!_isCurrent(pending)) return false;
      _failure = failure;
      if (failure.code != LoginFailureCode.network &&
          failure.code != LoginFailureCode.captcha) {
        _challenge = null;
      }
      _phase = _challenge == null ? AuthPhase.idle : AuthPhase.captcha;
      if (_challenge == null) {
        pending.gateway.close();
        _pending = null;
        _attempt = null;
      }
      _emit();
      return false;
    }
  }

  Future<void> _persist(_ActiveLogin active) async {
    try {
      await _withStorage(() async {
        if (_closed || !identical(_active, active)) return;
        final cookies = await active.gateway.exportCookies();
        if (_closed || !identical(_active, active)) return;
        await _vault.writeSchool(_profile ?? active.profile);
        await _vault.write(active.snapshot(cookies));
      });
      if (_closed || !identical(_active, active)) return;
      _remembered = true;
      _storageFailure = null;
    } on LoginFailure catch (failure) {
      if (_closed || !identical(_active, active)) return;
      _remembered = false;
      _storageFailure = failure;
    }
    _emit();
  }

  // Only the lock completion is queued; operation errors still reach the caller.
  Future<T> _withStorage<T>(Future<T> Function() operation) async {
    final previous = _storageTurn;
    final release = Completer<void>();
    _storageTurn = release.future;
    await previous;
    try {
      return await operation();
    } finally {
      release.complete();
    }
  }

  bool _isCurrent(_PendingLogin pending) =>
      !_closed && identical(_pending, pending) && identical(_attempt, pending);

  Future<T> _executeRead<T>(
    _ActiveLogin active,
    Future<T> Function(AuthenticatedReadClient client) operation,
  ) async {
    final gateway = active.gateway;
    if (gateway is! AuthenticatedReadClient) {
      throw const LoginFailure(LoginFailureCode.protocol, '当前登录适配器不支持教务数据查询');
    }
    final client = _ScopedReadClient(
      delegate: gateway as AuthenticatedReadClient,
      validate: () => _validateReadGateway(active),
    );
    try {
      final result = await operation(client);
      _validateReadGateway(active);
      // Schools may rotate session cookies during an ordinary timetable query.
      // Save the transport's latest cookies while keeping the verified identity.
      await _persist(_readActive(active.identity));
      _validateReadGateway(active);
      return result;
    } finally {
      client.close();
    }
  }

  Future<void> _renewForRead(_ActiveLogin failed) async {
    _requireCurrentIdentity(failed.identity);
    if (identical(_active, failed) ||
        _checking?.generation == failed.identity.generation) {
      await checkSession();
      _requireCurrentIdentity(failed.identity);
      if (_failure case final failure?) throw failure;
    }
    _readActive(failed.identity);
  }

  _ActiveLogin _readActive(AuthIdentity identity) {
    _requireCurrentIdentity(identity);
    return _active ?? (throw _sessionUnavailable);
  }

  void _validateReadGateway(_ActiveLogin active) {
    _requireCurrentIdentity(active.identity);
    if (!identical(_active?.gateway, active.gateway)) {
      throw const LoginFailure(LoginFailureCode.expired, '教务会话已更新，请重新读取');
    }
  }

  void _requireCurrentIdentity(AuthIdentity identity) {
    if (!isCurrentIdentity(identity)) throw _readCancelled;
  }

  void _expire(_ActiveLogin active, LoginFailure failure) {
    if (!isCurrentIdentity(active.identity) ||
        !identical(_active?.gateway, active.gateway)) {
      return;
    }
    _active = null;
    _failure = failure;
    if (_pending == null) _phase = AuthPhase.idle;
    active.gateway.close();
    _emit();
  }

  LoginFailure get _sessionUnavailable =>
      _failure ??
      (_challenge == null
          ? const LoginFailure(LoginFailureCode.expired, '请先恢复或重新登录教务账号')
          : const LoginFailure(LoginFailureCode.captcha, '请先完成教务登录验证码'));

  static void _requireSameAccount(LoginAccount expected, LoginAccount actual) {
    if (expected.id == actual.id) return;
    throw const LoginFailure(LoginFailureCode.expired, '教务会话返回了不同的账号，请重新登录');
  }

  void _emit() {
    if (!_closed) _changes.add(state);
  }

  Future<void> dispose() async {
    _closed = true;
    _attempt = null;
    _checking = null;
    _knownIdentity = null;
    _generation++;
    _pending?.gateway.close();
    _active?.gateway.close();
    _pending = null;
    _active = null;
    await _changes.close();
  }
}

const _readCancelled = LoginFailure(
  LoginFailureCode.cancelled,
  '账号已切换或退出，本次查询已取消',
);

final class _ScopedReadClient implements AuthenticatedReadClient {
  _ScopedReadClient({required this.delegate, required this.validate});

  final AuthenticatedReadClient delegate;
  final void Function() validate;
  bool _closed = false;

  @override
  Future<AuthHttpResponse> sendRead(AuthHttpRequest request) async {
    _validate();
    try {
      final response = await delegate.sendRead(request);
      _validate();
      return response;
    } on LoginFailure {
      _validate();
      rethrow;
    }
  }

  void _validate() {
    if (_closed) throw _readCancelled;
    validate();
  }

  void close() => _closed = true;
}
