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

/// A saved account remains listed after its authentication has been cleared.
final class StoredAuthAccount {
  const StoredAuthAccount({
    required this.profile,
    required this.account,
    this.login,
  });

  factory StoredAuthAccount.fromLogin(StoredLogin login) => StoredAuthAccount(
    profile: login.profile,
    account: login.session.account,
    login: login,
  );

  final SchoolConnection profile;
  final LoginAccount account;
  final StoredLogin? login;

  AccountScope get scope =>
      AccountScope(schoolId: profile.school.id, accountId: account.id);

  StoredAuthAccount withoutLogin() =>
      StoredAuthAccount(profile: profile, account: account);

  StoredAuthAccount withProfile(SchoolConnection profile) => StoredAuthAccount(
    profile: profile,
    account: account,
    login: login == null || !this.profile.hasSameConnection(profile)
        ? null
        : StoredLogin(
            profile: profile,
            session: login!.session,
            method: login!.method,
            credentials: login!.credentials,
          ),
  );
}

final class StoredSchool {
  const StoredSchool({required this.profile, this.lastAccountId});

  final SchoolConnection profile;
  final String? lastAccountId;
}

final class StoredLoginLibrary {
  StoredLoginLibrary({
    List<StoredAuthAccount> accounts = const [],
    List<StoredSchool>? schools,
    String? selectedSchoolId,
    this.selectedScope,
  }) : accounts = List.unmodifiable(accounts),
       schools = List.unmodifiable(schools ?? _schoolsFromAccounts(accounts)),
       selectedSchoolId = selectedSchoolId ?? selectedScope?.schoolId;

  factory StoredLoginLibrary.fromLogin(StoredLogin? login) {
    if (login == null) return StoredLoginLibrary();
    final account = StoredAuthAccount.fromLogin(login);
    return StoredLoginLibrary(
      accounts: [account],
      selectedScope: account.scope,
    );
  }

  final List<StoredAuthAccount> accounts;
  final List<StoredSchool> schools;
  final String? selectedSchoolId;
  final AccountScope? selectedScope;

  StoredSchool? get selectedSchool => schools
      .where((school) => school.profile.school.id == selectedSchoolId)
      .firstOrNull;

  StoredAuthAccount? get selected =>
      accounts.where((account) => account.scope == selectedScope).firstOrNull;
}

List<StoredSchool> _schoolsFromAccounts(List<StoredAuthAccount> accounts) => {
  for (final account in accounts)
    account.scope.schoolId: StoredSchool(
      profile: account.profile,
      lastAccountId: account.account.id,
    ),
}.values.toList();

abstract interface class LoginVault {
  Future<SchoolConnection?> readSchool();
  Future<void> writeSchool(SchoolConnection profile);
  Future<StoredLoginLibrary> readAccounts();
  Future<void> writeAccounts(StoredLoginLibrary library);

  /// Compatibility accessors for the selected account in the same saved library.
  Future<StoredLogin?> read();
  Future<void> write(StoredLogin login);

  /// Clears the selected account's authentication, retaining its school and name.
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

  /// Retained by automatic renewal; replaced by explicit login, exit or deletion.
  final int generation;
}

/// Account-list data never contains a password, cookie or token.
final class AuthAccountSummary {
  const AuthAccountSummary({
    required this.profile,
    required this.account,
    required this.isSignedIn,
    required this.remembered,
    required this.phase,
    this.hasSavedPassword = false,
    this.failure,
  });

  final SchoolConnection profile;
  final LoginAccount account;
  final bool isSignedIn;
  final bool remembered;
  final AuthPhase phase;
  final bool hasSavedPassword;
  final LoginFailure? failure;

  AccountScope get scope =>
      AccountScope(schoolId: profile.school.id, accountId: account.id);
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
    this.accounts = const [],
    this.schools = const [],
    this.selectedScope,
    this.accountsLoaded = false,
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
  final List<AuthAccountSummary> accounts;
  final List<StoredSchool> schools;
  final AccountScope? selectedScope;
  final bool remembered;
  final bool accountsLoaded;

  AuthAccountSummary? get selectedAccount =>
      accounts.where((account) => account.scope == selectedScope).firstOrNull;

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
    this.owner,
  });

  final SchoolConnection profile;
  final LoginGateway gateway;
  final LoginMethod method;
  final bool rememberPassword;
  final LoginCredentials? credentials;
  final _AccountLogin? owner;
  CaptchaRequired? challenge;
  AuthPhase phase = AuthPhase.signingIn;
}

final class _ActiveLogin {
  const _ActiveLogin({
    required this.identity,
    required this.gateway,
    required this.session,
    required this.method,
    this.credentials,
  });

  final AuthIdentity identity;
  final LoginGateway gateway;
  final LoginSession session;
  final LoginMethod method;
  final LoginCredentials? credentials;

  StoredLogin snapshot(List<LoginCookie> cookies) => StoredLogin(
    profile: identity.profile,
    session: LoginSession(
      account: session.account,
      cookies: cookies,
      verifiedAt: session.verifiedAt,
    ),
    method: method,
    credentials: credentials,
  );
}

final class _AccountLogin {
  _AccountLogin(this.record, this.generation, {this.remembered = false});

  StoredAuthAccount record;
  final int generation;
  _ActiveLogin? active;
  _PendingLogin? pending;
  Future<void>? checking;
  AuthPhase phase = AuthPhase.idle;
  LoginFailure? failure;
  LoginFailure? storageFailure;
  bool remembered;

  AuthIdentity get identity => AuthIdentity(
    profile: record.profile,
    account: record.account,
    generation: generation,
  );

  AuthAccountSummary get summary => AuthAccountSummary(
    profile: record.profile,
    account: record.account,
    isSignedIn: active != null,
    remembered: remembered,
    phase: pending?.phase ?? phase,
    hasSavedPassword: remembered && record.login?.credentials != null,
    failure: failure,
  );

  void close() {
    pending?.gateway.close();
    active?.gateway.close();
    pending = null;
    active = null;
    checking = null;
  }
}

/// Owns every account's session; selection changes only the foreground view.
final class AuthRepository {
  AuthRepository({
    SchoolConnection? initialProfile,
    required this._gatewayFactory,
    required this._vault,
  }) : _profile = initialProfile {
    if (initialProfile != null) {
      _schools[initialProfile.school.id] = StoredSchool(
        profile: initialProfile,
      );
    }
  }

  final LoginGatewayFactory _gatewayFactory;
  final LoginVault _vault;
  final _changes = StreamController<AuthSnapshot>.broadcast(sync: true);
  final _accounts = <AccountScope, _AccountLogin>{};
  final _schools = <String, StoredSchool>{};
  final _mutationTurns = <AccountScope, Future<void>>{};
  SchoolConnection? _profile;
  AccountScope? _selectedScope;
  int _profileRevision = 0;
  int _generation = 0;
  _PendingLogin? _manualLogin;
  Object? _restoreMarker;
  LoginFailure? _failure;
  LoginFailure? _storageFailure;
  bool _loaded = false;
  bool _closed = false;
  Future<void> _storageTurn = Future<void>.value();
  Future<void>? _restoring;

  _AccountLogin? get _selected => _accounts[_selectedScope];
  _PendingLogin? get _visiblePending => _manualLogin ?? _selected?.pending;
  Stream<AuthSnapshot> get changes => _changes.stream;

  AuthSnapshot get state {
    final selected = _selected;
    final pending = _visiblePending;
    return AuthSnapshot(
      profile: selected?.record.profile ?? _profile,
      configuredProfile: _profile,
      phase: _restoreMarker != null
          ? AuthPhase.restoring
          : pending?.phase ?? selected?.phase ?? AuthPhase.idle,
      account: selected?.active?.session.account,
      knownIdentity: _selectedScope == null
          ? null
          : identityFor(_selectedScope!),
      challenge: pending?.challenge,
      failure: _failure ?? selected?.failure,
      storageFailure: _storageFailure ?? selected?.storageFailure,
      pendingUsername:
          pending?.credentials?.username ??
          (pending == null ? selected?.record.account.loginName : null),
      remembered: selected?.remembered ?? false,
      accounts: List.unmodifiable(
        _accounts.values.map((entry) => entry.summary),
      ),
      schools: List.unmodifiable(_schools.values),
      selectedScope: _selectedScope,
      accountsLoaded: _loaded,
    );
  }

  Future<void> configureSchool(SchoolConnection profile) async {
    _requireOpen();
    final revision = ++_profileRevision;
    try {
      await _withStorage(() async {
        await _loadAccounts();
        if (_closed || revision != _profileRevision) return;
        final id = profile.school.id;
        final previous = _schools[id];
        if (_schools.values.any(
          (school) =>
              school.profile.school.id != id &&
              school.profile.hasSameConnection(profile),
        )) {
          throw const LoginFailure(
            LoginFailureCode.protocol,
            '这个教务系统已经添加，请选择或编辑已有学校',
          );
        }
        final selectedScope = _schoolAccount(id, previous?.lastAccountId);
        final captured = _accounts.values.map((entry) => entry.record).toList();
        final updated = [
          for (final record in captured)
            record.scope.schoolId == id ? record.withProfile(profile) : record,
        ];
        // Publish a school edit only after the complete directory is durable.
        // A failed save must not expose a school that was never actually added.
        await _vault.writeAccounts(
          StoredLoginLibrary(
            accounts: updated,
            schools: [
              for (final school in _schools.values)
                if (school.profile.school.id != id) school,
              StoredSchool(
                profile: profile,
                lastAccountId: selectedScope?.accountId,
              ),
            ],
            selectedSchoolId: id,
            selectedScope: selectedScope,
          ),
        );
        if (_closed) return;
        for (var i = 0; i < captured.length; i++) {
          _markSaved(captured[i], saved: updated[i]);
        }
        if (previous != null && !previous.profile.hasSameConnection(profile)) {
          if (_manualLogin?.profile.school.id == id) {
            _closePending(_manualLogin!);
          }
          for (final scope
              in _accounts.keys
                  .where((scope) => scope.schoolId == id)
                  .toList()) {
            _forgetAuthentication(
              scope,
              reason: const LoginFailure(
                LoginFailureCode.expired,
                '学校连接设置已修改，请重新登录',
              ),
            );
          }
        }
        for (final entry in _accounts.values) {
          if (entry.record.scope.schoolId == id) {
            entry.record = entry.record.withProfile(profile);
          }
        }
        _schools[id] = StoredSchool(
          profile: profile,
          lastAccountId: _schoolAccount(
            id,
            _schools[id]?.lastAccountId,
          )?.accountId,
        );
        if (revision == _profileRevision) {
          if (_manualLogin case final pending?) _closePending(pending);
          _chooseSchool(id);
        } else if (_profile?.school.id == id) {
          _profile = profile;
        }
        _failure = null;
        _storageFailure = null;
        _emit();
      });
    } on LoginFailure catch (failure) {
      if (failure.code == LoginFailureCode.storage) {
        _storageFailure = failure;
        _emit();
      }
      rethrow;
    }
  }

  Future<bool> selectSchool(String schoolId) async {
    _requireOpen();
    if (!_schools.containsKey(schoolId)) return false;
    if (_manualLogin case final pending?) _closePending(pending);
    _restoreMarker = null;
    _profileRevision++;
    _chooseSchool(schoolId);
    _failure = null;
    _storageFailure = null;
    _emit();
    final entry = _selected;
    final saved = await _saveLibrary();
    await _restoreSelection(entry);
    return saved;
  }

  void _chooseSchool(String schoolId) {
    final school = _schools[schoolId]!;
    _selectedScope = _schoolAccount(schoolId, school.lastAccountId);
    _profile = school.profile;
    _rememberSelection();
  }

  AccountScope? _schoolAccount(String schoolId, String? lastAccountId) {
    final preferred = lastAccountId == null
        ? null
        : AccountScope(schoolId: schoolId, accountId: lastAccountId);
    return _accounts.containsKey(preferred)
        ? preferred
        : _accounts.keys
              .where((scope) => scope.schoolId == schoolId)
              .firstOrNull;
  }

  void _rememberSelection() {
    final selected = _selected;
    if (selected == null) return;
    final profile = selected.record.profile;
    _schools[profile.school.id] = StoredSchool(
      profile: profile,
      lastAccountId: selected.record.account.id,
    );
  }

  Future<void> _restoreSelection(_AccountLogin? entry) async {
    if (!_closed &&
        entry != null &&
        identical(_selected, entry) &&
        entry.record.login != null &&
        entry.active == null &&
        entry.pending == null) {
      await _checkAccount(entry);
    }
  }

  AuthIdentity? identityFor(AccountScope scope) {
    if (_closed) return null;
    final entry = _accounts[scope];
    return entry?.record.login == null ? null : entry!.identity;
  }

  /// Background work uses this check independently of the displayed account.
  bool isAccountIdentityCurrent(AuthIdentity identity) =>
      identityFor(identity.scope)?.generation == identity.generation;

  /// Foreground data must also still belong to the displayed account.
  bool isCurrentIdentity(AuthIdentity identity) =>
      _selectedScope == identity.scope && isAccountIdentityCurrent(identity);

  Future<T> runRead<T>(
    AccountScope scope,
    Future<T> Function(AuthenticatedReadClient client) operation,
  ) {
    if (_closed || (_selectedScope != null && _selectedScope != scope)) {
      return Future.error(_readCancelled);
    }
    final identity = identityFor(scope);
    if (identity == null) return Future.error(_unavailable(_accounts[scope]));
    return _runRead(identity, operation, selectedOnly: true);
  }

  Future<T> runAccountRead<T>(
    AuthIdentity identity,
    Future<T> Function(AuthenticatedReadClient client) operation,
  ) => _runRead(identity, operation, selectedOnly: false);

  /// Serializes submissions for one account and never repeats [operation].
  ///
  /// A restored session may be verified before submitting. Once the supplied
  /// client sends a request, errors and redirects belong to result verification;
  /// they must not cause authentication renewal to replay that submission.
  Future<T> runAccountMutation<T>(
    AuthIdentity identity,
    Future<T> Function(AuthenticatedReadClient client) operation,
  ) async {
    _requireAccount(identity);
    final previous = _mutationTurns[identity.scope] ?? Future<void>.value();
    final release = Completer<void>();
    _mutationTurns[identity.scope] = release.future;
    await previous;
    try {
      await _ensureSession(identity);
      final active = _activeFor(identity);
      try {
        return await _execute(active, operation, mutation: true);
      } on LoginFailure catch (failure) {
        _requireAccount(identity);
        if (failure.code == LoginFailureCode.expired) _expire(active, failure);
        rethrow;
      } on Object {
        _requireAccount(identity);
        rethrow;
      }
    } finally {
      release.complete();
      if (identical(_mutationTurns[identity.scope], release.future)) {
        _mutationTurns.remove(identity.scope);
      }
    }
  }

  Future<T> _runRead<T>(
    AuthIdentity identity,
    Future<T> Function(AuthenticatedReadClient client) operation, {
    required bool selectedOnly,
  }) async {
    void validate() => _validateIdentity(identity, selectedOnly: selectedOnly);
    validate();
    if (_requireAccount(identity).active == null) {
      await _ensureSession(identity);
    }
    for (var attempt = 0; ; attempt++) {
      validate();
      final active = _activeFor(identity);
      try {
        return await _execute(active, operation, validate: validate);
      } on LoginFailure catch (failure) {
        validate();
        if (failure.code != LoginFailureCode.expired) rethrow;
        if (attempt > 0) {
          _expire(active, failure);
          rethrow;
        }
        await _renewForRead(active);
      } on Object {
        validate();
        rethrow;
      }
    }
  }

  Future<bool> signInPassword(
    SchoolConnection profile,
    LoginCredentials credentials, {
    bool rememberPassword = false,
  }) {
    final pending = _beginManual(
      profile,
      method: LoginMethod.password,
      credentials: credentials,
      rememberPassword: rememberPassword,
    );
    return _runLogin(pending, () => pending.gateway.loginPassword(credentials));
  }

  Future<bool> signInCookies(
    SchoolConnection profile,
    List<LoginCookie> cookies, {
    required LoginMethod method,
    String usernameHint = '',
  }) {
    final pending = _beginManual(profile, method: method);
    return _runLogin(
      pending,
      () async => LoginSuccess(
        await pending.gateway.importCookies(
          cookies,
          usernameHint: usernameHint,
        ),
      ),
    );
  }

  Future<bool> submitCaptcha(String code) async {
    final pending = _visiblePending;
    if (pending == null || pending.challenge == null) {
      _failure = const LoginFailure(LoginFailureCode.captcha, '请重新开始登录');
      _emit();
      return false;
    }
    pending.phase = AuthPhase.signingIn;
    _setPendingFailure(pending, null);
    _emit();
    return _runLogin(pending, () => pending.gateway.submitCaptcha(code.trim()));
  }

  Future<void> refreshCaptcha() async {
    final pending = _visiblePending;
    if (pending == null || pending.challenge == null) return;
    pending.phase = AuthPhase.signingIn;
    _setPendingFailure(pending, null);
    _emit();
    try {
      final bytes = await pending.gateway.refreshCaptcha();
      if (!_isPending(pending)) return;
      pending.challenge = CaptchaRequired(image: bytes);
    } on LoginFailure catch (failure) {
      if (!_isPending(pending)) return;
      _setPendingFailure(pending, failure);
    }
    if (!_isPending(pending)) return;
    pending.phase = AuthPhase.captcha;
    _emit();
  }

  void cancelSignIn() {
    if (_restoreMarker == null && _visiblePending == null) return;
    _restoreMarker = null;
    final pending = _visiblePending;
    if (pending != null) _closePending(pending);
    _failure = null;
    _emit();
  }

  Future<void> restore() => _restoring ??= _restore().whenComplete(() {
    _restoring = null;
  });

  Future<void> _restore() async {
    if (_closed || _manualLogin != null || _selected?.active != null) return;
    final marker = Object();
    _restoreMarker = marker;
    _failure = null;
    _emit();
    try {
      await _withStorage(_loadAccounts);
      if (_closed || !identical(_restoreMarker, marker)) return;
      _restoreMarker = null;
      _storageFailure = null;
      _emit();
      final selected = _selected;
      if (selected?.record.login != null) await _checkAccount(selected!);
    } on LoginFailure catch (failure) {
      if (_closed || !identical(_restoreMarker, marker)) return;
      _restoreMarker = null;
      _storageFailure = failure;
      _emit();
    }
  }

  /// Only called with the storage turn held; merges without replacing live data.
  Future<void> _loadAccounts() async {
    if (_loaded) return;
    final revision = _profileRevision;
    final library = await _vault.readAccounts();
    if (_closed) return;
    for (final school in library.schools) {
      final id = school.profile.school.id;
      if (revision == 0 || !_schools.containsKey(id)) _schools[id] = school;
    }
    if (revision == _profileRevision &&
        _selectedScope == null &&
        _manualLogin == null) {
      _profile = library.selectedSchool?.profile ?? _profile;
      _selectedScope = library.selectedScope;
    }
    for (final record in library.accounts) {
      _accounts.putIfAbsent(
        record.scope,
        () => _AccountLogin(
          record.withProfile(_schools[record.scope.schoolId]!.profile),
          ++_generation,
          remembered: record.login != null,
        ),
      );
    }
    _rememberSelection();
    _loaded = true;
  }

  Future<bool> selectAccount(AccountScope scope) async {
    _requireOpen();
    final entry = _accounts[scope];
    if (entry == null) {
      _failure = const LoginFailure(
        LoginFailureCode.missingIdentity,
        '该账号已不在本机保存的列表中',
      );
      _emit();
      return false;
    }
    // Foreground forms can be cancelled; other accounts' renewal and requests
    // remain owned by their account entries after this selection.
    if (_manualLogin case final pending?) _closePending(pending);
    _restoreMarker = null;
    _selectedScope = scope;
    _profile = entry.record.profile;
    _profileRevision++;
    _rememberSelection();
    _failure = null;
    _storageFailure = null;
    _emit();
    final saved = await _saveLibrary();
    await _restoreSelection(entry);
    return saved;
  }

  Future<void> checkSession() {
    final entry = _selected;
    if (entry == null || _manualLogin != null) return Future.value();
    return _checkAccount(entry);
  }

  Future<void> _checkAccount(_AccountLogin entry) {
    if (entry.checking case final checking?) return checking;
    if (!_isEntryCurrent(entry) ||
        entry.pending != null ||
        entry.record.login == null) {
      return Future.value();
    }
    final completion = Completer<void>();
    entry.checking = completion.future;
    unawaited(_completeCheck(entry, completion));
    return completion.future;
  }

  Future<void> _completeCheck(
    _AccountLogin entry,
    Completer<void> completion,
  ) async {
    try {
      final active = entry.active;
      if (active == null) {
        await _restoreAccount(entry);
      } else {
        await _verifyAccount(entry, active);
      }
      completion.complete();
    } catch (error, stackTrace) {
      completion.completeError(error, stackTrace);
    } finally {
      if (identical(entry.checking, completion.future)) entry.checking = null;
    }
  }

  Future<void> _restoreAccount(_AccountLogin entry) async {
    final stored = entry.record.login;
    if (stored == null) return;
    final pending = _beginRenewal(entry, method: stored.method);
    await _runLogin(pending, () async {
      try {
        final session = await pending.gateway.importCookies(
          stored.session.cookies,
          usernameHint: stored.session.account.loginName,
        );
        _requireSameAccount(stored.session.account, session.account);
        return LoginSuccess(session);
      } on LoginFailure catch (failure) {
        if (failure.code != LoginFailureCode.expired ||
            stored.credentials == null) {
          rethrow;
        }
        if (!_isPending(pending)) throw _readCancelled;
        return pending.gateway.loginPassword(stored.credentials!);
      }
    });
  }

  Future<void> _verifyAccount(_AccountLogin entry, _ActiveLogin active) async {
    entry.phase = AuthPhase.checking;
    entry.failure = null;
    if (identical(entry, _selected)) _failure = null;
    _emit();
    try {
      final session = await active.gateway.verifySession(
        usernameHint: active.session.account.loginName,
      );
      if (!_isActive(active)) return;
      _requireSameAccount(active.session.account, session.account);
      final next = _ActiveLogin(
        identity: AuthIdentity(
          profile: entry.record.profile,
          account: session.account,
          generation: active.identity.generation,
        ),
        gateway: active.gateway,
        session: session,
        method: active.method,
        credentials: active.credentials,
      );
      entry.active = next;
      entry.record = StoredAuthAccount.fromLogin(
        next.snapshot(session.cookies),
      );
      entry.phase = AuthPhase.idle;
      _emit();
      await _persist(next);
    } on LoginFailure catch (failure) {
      if (!_isActive(active)) return;
      entry.phase = AuthPhase.idle;
      if (failure.code != LoginFailureCode.expired) {
        entry.failure = failure;
        _emit();
        return;
      }
      _expire(active, failure);
      if (active.credentials != null) {
        final pending = _beginRenewal(entry, method: LoginMethod.password);
        await _runLogin(
          pending,
          () => pending.gateway.loginPassword(active.credentials!),
        );
      }
    }
  }

  Future<void> signOut() async {
    _restoreMarker = null;
    if (_visiblePending case final pending?) _closePending(pending);
    if (!_loaded) {
      try {
        await _withStorage(_loadAccounts);
      } on LoginFailure catch (failure) {
        _storageFailure = failure;
        _emit();
        return;
      }
    }
    final scope = _selectedScope;
    if (scope != null) await signOutAccount(scope);
  }

  Future<bool> signOutAccount(AccountScope scope) async {
    _requireOpen();
    final entry = _accounts[scope];
    if (entry == null) return false;
    if (_selectedScope == scope && _manualLogin != null) {
      _closePending(_manualLogin!);
    }
    _forgetAuthentication(scope);
    _failure = null;
    _storageFailure = null;
    _emit();
    return _saveLibrary();
  }

  void _forgetAuthentication(AccountScope scope, {LoginFailure? reason}) {
    final entry = _accounts[scope]!;
    entry.close();
    _accounts[scope] = _AccountLogin(entry.record.withoutLogin(), ++_generation)
      ..failure = reason;
  }

  Future<bool> signOutSchool(String schoolId) async {
    _requireOpen();
    if (!_schools.containsKey(schoolId)) return false;
    if (_manualLogin?.profile.school.id == schoolId) {
      _closePending(_manualLogin!);
    }
    for (final scope
        in _accounts.keys
            .where((scope) => scope.schoolId == schoolId)
            .toList()) {
      _forgetAuthentication(scope);
    }
    _failure = null;
    _emit();
    return _saveLibrary();
  }

  Future<bool> removeSchool(String schoolId) async {
    _requireOpen();
    await _withStorage(_loadAccounts);
    final school = _schools.remove(schoolId);
    if (school == null) return false;
    if (_manualLogin?.profile.school.id == schoolId) {
      _closePending(_manualLogin!);
    }
    final removed = _accounts.entries
        .where((entry) => entry.key.schoolId == schoolId)
        .toList();
    for (final entry in removed) {
      _accounts.remove(entry.key);
      entry.value.close();
    }
    final wasSelected = _profile?.school.id == schoolId;
    if (wasSelected) {
      _selectedScope = null;
      _profile = null;
      if (_schools.isNotEmpty) _chooseSchool(_schools.keys.first);
    }
    final nextSelected = _selected;
    _profileRevision++;
    _emit();
    final saved = await _saveLibrary();
    if (!saved && !_closed) {
      _schools[schoolId] = school;
      for (final entry in removed) {
        _accounts.putIfAbsent(
          entry.key,
          () => _AccountLogin(entry.value.record.withoutLogin(), ++_generation),
        );
      }
      if (wasSelected && _profile == null) _chooseSchool(schoolId);
      _emit();
    }
    if (saved && wasSelected) await _restoreSelection(nextSelected);
    return saved;
  }

  Future<bool> removeAccount(AccountScope scope) async {
    _requireOpen();
    // Loading a legacy library must not put back the account being removed.
    if (!_loaded && !await signOutAccount(scope)) return false;
    final entry = _accounts.remove(scope);
    if (entry == null) return false;
    final wasSelected = _selectedScope == scope;
    entry.close();
    if (_selectedScope == scope) {
      if (_manualLogin case final pending?) _closePending(pending);
      _selectedScope = null;
    }
    final school = _schools[scope.schoolId];
    if (school?.lastAccountId == scope.accountId) {
      _schools[scope.schoolId] = StoredSchool(profile: school!.profile);
    }
    if (wasSelected && school != null) _chooseSchool(scope.schoolId);
    final nextSelected = _selected;
    _failure = null;
    _storageFailure = null;
    _emit();
    final saved = await _saveLibrary();
    if (!saved && !_closed && !_accounts.containsKey(scope)) {
      _accounts[scope] = _AccountLogin(
        entry.record.withoutLogin(),
        ++_generation,
      );
      if (wasSelected && _selectedScope == null) _selectedScope = scope;
      _rememberSelection();
      _emit();
    }
    if (saved && wasSelected) await _restoreSelection(nextSelected);
    return saved;
  }

  Future<bool> retryStorage() async {
    final active = _selected?.active;
    if (!_loaded && active == null) {
      await restore();
      return state.storageFailure == null;
    }
    if (active == null) return _saveLibrary();
    await _persist(active);
    return state.storageFailure == null;
  }

  _PendingLogin _beginManual(
    SchoolConnection profile, {
    required LoginMethod method,
    LoginCredentials? credentials,
    bool rememberPassword = false,
  }) {
    _requireOpen();
    final configured = _schools[profile.school.id]?.profile;
    if (configured != null && !configured.hasSameConnection(profile)) {
      throw const LoginFailure(
        LoginFailureCode.cancelled,
        '学校连接设置已更改，请重新打开登录页面',
      );
    }
    if (_manualLogin case final previous?) _closePending(previous);
    _restoreMarker = null;
    final pending = _PendingLogin(
      profile: profile,
      gateway: _gatewayFactory(profile),
      method: method,
      credentials: credentials,
      rememberPassword: rememberPassword,
    );
    _manualLogin = pending;
    _profileRevision++;
    _profile = profile;
    _failure = null;
    _emit();
    return pending;
  }

  _PendingLogin _beginRenewal(
    _AccountLogin entry, {
    required LoginMethod method,
  }) {
    final stored = entry.record.login!;
    final pending = _PendingLogin(
      profile: stored.profile,
      gateway: _gatewayFactory(stored.profile),
      method: method,
      credentials: stored.credentials,
      rememberPassword: stored.credentials != null,
      owner: entry,
    );
    entry.pending = pending;
    entry.failure = null;
    if (identical(entry, _selected) && _manualLogin == null) _failure = null;
    _emit();
    return pending;
  }

  Future<bool> _runLogin(
    _PendingLogin pending,
    Future<LoginStep> Function() operation,
  ) async {
    try {
      final result = await operation();
      if (!_isPending(pending)) return false;
      if (result case CaptchaRequired()) {
        pending.challenge = result;
        pending.phase = AuthPhase.captcha;
        _emit();
        return false;
      }
      final session = (result as LoginSuccess).session;
      final owner = pending.owner;
      if (owner != null) {
        _requireSameAccount(owner.record.account, session.account);
      }
      final identity = AuthIdentity(
        profile:
            _schools[pending.profile.school.id]?.profile ?? pending.profile,
        account: session.account,
        generation: owner?.generation ?? ++_generation,
      );
      final active = _ActiveLogin(
        identity: identity,
        gateway: pending.gateway,
        session: session,
        method: pending.method,
        credentials: pending.rememberPassword ? pending.credentials : null,
      );
      final record = StoredAuthAccount.fromLogin(
        active.snapshot(session.cookies),
      );
      final entry = owner ?? _AccountLogin(record, identity.generation);
      if (owner == null) {
        _accounts[identity.scope]?.close();
        _accounts[identity.scope] = entry;
        _selectedScope = identity.scope;
        _profile = identity.profile;
        _rememberSelection();
        _manualLogin = null;
        _failure = null;
        _storageFailure = null;
      }
      entry.active = active;
      entry.record = record;
      entry.pending = null;
      entry.failure = null;
      entry.storageFailure = null;
      entry.phase = AuthPhase.saving;
      _emit();
      await _persist(active);
      if (!_isActive(active)) return false;
      entry.phase = AuthPhase.idle;
      _emit();
      return true;
    } on LoginFailure catch (failure) {
      if (!_isPending(pending)) return false;
      _setPendingFailure(pending, failure);
      if (failure.code != LoginFailureCode.network &&
          failure.code != LoginFailureCode.captcha) {
        pending.challenge = null;
      }
      pending.phase = pending.challenge == null
          ? AuthPhase.idle
          : AuthPhase.captcha;
      if (pending.challenge == null) _closePending(pending);
      _emit();
      return false;
    }
  }

  void _setPendingFailure(_PendingLogin pending, LoginFailure? failure) {
    final owner = pending.owner;
    if (owner == null) {
      _failure = failure;
    } else {
      owner.failure = failure;
    }
  }

  void _closePending(_PendingLogin pending) {
    pending.gateway.close();
    if (identical(_manualLogin, pending)) _manualLogin = null;
    if (identical(pending.owner?.pending, pending)) {
      pending.owner!.pending = null;
      pending.owner!.phase = AuthPhase.idle;
    }
  }

  bool _isPending(_PendingLogin pending) =>
      !_closed &&
      (pending.owner == null
          ? identical(_manualLogin, pending)
          : _isEntryCurrent(pending.owner!) &&
                identical(pending.owner!.pending, pending));

  Future<void> _persist(_ActiveLogin active) async {
    try {
      await _withStorage(() async {
        if (!_isActive(active)) return;
        await _loadAccounts();
        final cookies = await active.gateway.exportCookies();
        if (!_isActive(active)) return;
        final entry = _requireAccount(active.identity);
        entry.record = StoredAuthAccount.fromLogin(active.snapshot(cookies))
            .withProfile(_schools[active.identity.scope.schoolId]!.profile);
        await _writeLibrary();
      });
      if (!_isActive(active)) return;
      final entry = _requireAccount(active.identity);
      entry.remembered = true;
      entry.storageFailure = null;
      _storageFailure = null;
    } on LoginFailure catch (failure) {
      if (!_isActive(active)) return;
      final entry = _requireAccount(active.identity);
      entry.remembered = false;
      entry.storageFailure = failure;
    }
    _emit();
  }

  Future<bool> _saveLibrary() async {
    try {
      await _withStorage(() async {
        await _loadAccounts();
        if (!_closed) await _writeLibrary();
      });
      if (_closed) return false;
      _storageFailure = null;
      _emit();
      return true;
    } on LoginFailure catch (failure) {
      if (!_closed) {
        _storageFailure = failure;
        _emit();
      }
      return false;
    }
  }

  Future<void> _writeLibrary() async {
    final library = StoredLoginLibrary(
      accounts: _accounts.values.map((entry) => entry.record).toList(),
      schools: _schools.values.toList(),
      selectedSchoolId: state.profile?.school.id,
      selectedScope: _selectedScope,
    );
    await _vault.writeAccounts(library);
    if (_closed) return;
    for (final saved in library.accounts) {
      _markSaved(saved);
    }
  }

  void _markSaved(StoredAuthAccount captured, {StoredAuthAccount? saved}) {
    final entry = _accounts[captured.scope];
    if (entry != null && identical(entry.record, captured)) {
      entry.remembered = (saved ?? captured).login != null;
      entry.storageFailure = null;
    }
  }

  // Queue lock completions, leaving failures visible to the actual caller.
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

  Future<T> _execute<T>(
    _ActiveLogin active,
    Future<T> Function(AuthenticatedReadClient client) operation, {
    bool mutation = false,
    void Function()? validate,
  }) async {
    final gateway = active.gateway;
    final Future<AuthHttpResponse> Function(AuthHttpRequest) send;
    if (mutation) {
      if (gateway is! AuthenticatedMutationClient) {
        throw const LoginFailure(LoginFailureCode.protocol, '当前登录适配器不支持选课提交');
      }
      send = (gateway as AuthenticatedMutationClient).sendMutation;
    } else {
      if (gateway is! AuthenticatedReadClient) {
        throw const LoginFailure(LoginFailureCode.protocol, '当前登录适配器不支持教务数据查询');
      }
      send = (gateway as AuthenticatedReadClient).sendRead;
    }
    void validateClient() {
      validate?.call();
      _validateGateway(active);
    }

    final client = _ScopedReadClient(
      send: send,
      validate: validateClient,
      oneShot: mutation,
    );
    try {
      final result = await operation(client);
      validateClient();
      await _persist(_activeFor(active.identity));
      validateClient();
      return result;
    } finally {
      client.close();
    }
  }

  Future<void> _ensureSession(AuthIdentity identity) async {
    final entry = _requireAccount(identity);
    if (entry.active != null) return;
    if (entry.checking case final checking?) {
      await checking;
    } else if (entry.pending == null &&
        (entry.failure == null ||
            (entry.failure?.code == LoginFailureCode.expired &&
                entry.record.login?.credentials != null))) {
      await _checkAccount(entry);
    }
    _activeFor(identity);
  }

  Future<void> _renewForRead(_ActiveLogin failed) async {
    final entry = _requireAccount(failed.identity);
    if (_isActive(failed) || entry.checking != null) {
      await _checkAccount(entry);
      _requireAccount(failed.identity);
      if (entry.pending?.challenge != null) throw _unavailable(entry);
      if (entry.failure case final failure?) throw failure;
    }
    _activeFor(failed.identity);
  }

  _ActiveLogin _activeFor(AuthIdentity identity) {
    final entry = _requireAccount(identity);
    return entry.active ?? (throw _unavailable(entry));
  }

  _AccountLogin _requireAccount(AuthIdentity identity) {
    if (!isAccountIdentityCurrent(identity)) throw _readCancelled;
    return _accounts[identity.scope]!;
  }

  bool _isEntryCurrent(_AccountLogin entry) =>
      !_closed && identical(_accounts[entry.record.scope], entry);

  bool _isActive(_ActiveLogin active) =>
      isAccountIdentityCurrent(active.identity) &&
      identical(_accounts[active.identity.scope]?.active, active);

  void _validateIdentity(AuthIdentity identity, {required bool selectedOnly}) {
    if (!(selectedOnly
        ? isCurrentIdentity(identity)
        : isAccountIdentityCurrent(identity))) {
      throw _readCancelled;
    }
  }

  void _validateGateway(_ActiveLogin active) {
    final entry = _requireAccount(active.identity);
    if (!identical(entry.active?.gateway, active.gateway)) {
      throw const LoginFailure(LoginFailureCode.expired, '教务会话已更新，请重新读取');
    }
  }

  void _expire(_ActiveLogin active, LoginFailure failure) {
    if (!_isActive(active)) return;
    final entry = _accounts[active.identity.scope]!;
    entry.active = null;
    entry.failure = failure;
    entry.phase = AuthPhase.idle;
    active.gateway.close();
    _emit();
  }

  LoginFailure _unavailable(_AccountLogin? entry) =>
      entry?.pending?.challenge != null
      ? const LoginFailure(LoginFailureCode.captcha, '请先完成该教务账号的登录验证码')
      : entry?.failure ??
            const LoginFailure(LoginFailureCode.expired, '请先恢复或重新登录教务账号');

  static void _requireSameAccount(LoginAccount expected, LoginAccount actual) {
    if (expected.id == actual.id) return;
    throw const LoginFailure(LoginFailureCode.expired, '教务会话返回了不同的账号，请重新登录');
  }

  void _requireOpen() {
    if (_closed) throw StateError('Authentication repository is closed.');
  }

  void _emit() {
    if (!_closed) _changes.add(state);
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _restoreMarker = null;
    _manualLogin?.gateway.close();
    _manualLogin = null;
    for (final account in _accounts.values) {
      account.close();
    }
    _accounts.clear();
    await _storageTurn;
    await _changes.close();
  }
}

const _readCancelled = LoginFailure(
  LoginFailureCode.cancelled,
  '账号已切换、退出或重新登录，本次操作已取消',
);

final class _ScopedReadClient implements AuthenticatedReadClient {
  _ScopedReadClient({
    required this.send,
    required this.validate,
    this.oneShot = false,
  });

  final Future<AuthHttpResponse> Function(AuthHttpRequest) send;
  final void Function() validate;
  final bool oneShot;
  bool _closed = false;
  bool _sent = false;

  @override
  Future<AuthHttpResponse> sendRead(AuthHttpRequest request) async {
    _validate();
    if (oneShot && _sent) {
      throw const LoginFailure(
        LoginFailureCode.protocol,
        '一次选课操作只能提交一个请求，请先核实学校结果',
      );
    }
    _sent = true;
    try {
      final response = await send(request);
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
