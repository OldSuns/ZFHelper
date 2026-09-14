import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:zf_core/zf_core.dart';

final class AuthViewModel extends ChangeNotifier {
  AuthViewModel(this._repository) {
    _subscription = _repository.changes.listen((_) => notifyListeners());
  }

  final AuthRepository _repository;
  late final StreamSubscription<AuthSnapshot> _subscription;

  AuthSnapshot get state => _repository.state;
  Future<void> configureSchool(SchoolConnection profile) =>
      _repository.configureSchool(profile);
  Future<void> restore() => _repository.restore();
  Future<void> checkSession() => _repository.checkSession();
  Future<void> signOut() => _repository.signOut();
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

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
