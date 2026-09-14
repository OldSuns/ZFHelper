import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:zf_core/zf_core.dart';

final class AuthViewModel extends ChangeNotifier {
  AuthViewModel(this._repository, {this._onRemoveAccountData}) {
    _subscription = _repository.changes.listen((_) => notifyListeners());
  }

  final AuthRepository _repository;
  final Future<void> Function(AccountScope scope)? _onRemoveAccountData;
  late final StreamSubscription<AuthSnapshot> _subscription;
  bool _managingAccounts = false;
  bool _disposed = false;
  String? _accountActionFailure;

  AuthSnapshot get state => _repository.state;
  bool get isManagingAccounts => _managingAccounts;
  String? get accountActionFailure => _accountActionFailure;
  Future<void> configureSchool(SchoolConnection profile) =>
      _repository.configureSchool(profile);
  Future<void> restore() => _repository.restore();
  Future<void> checkSession() => _repository.checkSession();
  Future<void> signOut() => _repository.signOut();
  Future<bool> retryStorage() => _repository.retryStorage();
  Future<bool> selectAccount(AccountScope scope) =>
      _manageAccount(() => _repository.selectAccount(scope));
  Future<bool> signOutAccount(AccountScope scope) =>
      _manageAccount(() => _repository.signOutAccount(scope));
  Future<bool> removeAccount(AccountScope scope) => _manageAccount(() async {
    if (!await _repository.signOutAccount(scope)) return false;
    await _onRemoveAccountData?.call(scope);
    return _repository.removeAccount(scope);
  });
  void cancelSignIn() => _repository.cancelSignIn();
  Future<void> refreshCaptcha() => _repository.refreshCaptcha();
  Future<bool> submitCaptcha(String value) => _repository.submitCaptcha(value);

  Future<bool> signInPassword(
    SchoolConnection profile,
    LoginCredentials credentials, {
    bool rememberPassword = false,
  }) => _repository.signInPassword(
    profile,
    credentials,
    rememberPassword: rememberPassword,
  );

  Future<bool> signInCookies(
    SchoolConnection profile,
    List<LoginCookie> cookies, {
    required LoginMethod method,
    String usernameHint = '',
  }) => _repository.signInCookies(
    profile,
    cookies,
    method: method,
    usernameHint: usernameHint,
  );

  Future<bool> _manageAccount(Future<bool> Function() operation) async {
    if (_managingAccounts) return false;
    _managingAccounts = true;
    _accountActionFailure = null;
    notifyListeners();
    try {
      return await operation();
    } on LoginFailure catch (failure) {
      _accountActionFailure = failure.message;
      return false;
    } finally {
      _managingAccounts = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
