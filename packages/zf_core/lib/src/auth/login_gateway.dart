import 'dart:typed_data';

import 'login_models.dart';
import 'school_connection.dart';

abstract interface class AuthTransport {
  Future<AuthHttpResponse> send(AuthHttpRequest request);
  Future<void> replaceCookies(Uri origin, List<LoginCookie> cookies);
  Future<List<LoginCookie>> cookiesFor(Uri uri);
  void close();
}

abstract interface class PasswordCipher {
  String encrypt({
    required String modulus,
    required String exponent,
    required String password,
  });
}

abstract interface class LoginGateway {
  Future<LoginStep> loginPassword(LoginCredentials credentials);
  Future<LoginStep> submitCaptcha(String captcha);
  Future<Uint8List> refreshCaptcha();
  Future<LoginSession> importCookies(
    List<LoginCookie> cookies, {
    String usernameHint = '',
  });
  Future<LoginSession> verifySession({String usernameHint = ''});

  /// Reads the latest session cookies locally, without a new school request.
  Future<List<LoginCookie>> exportCookies();
  void close();
}

typedef LoginGatewayFactory = LoginGateway Function(SchoolConnection profile);
