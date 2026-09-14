import 'login_models.dart';

/// Access to queries through the account owner's authenticated transport.
abstract interface class AuthenticatedReadClient {
  /// Sends a request whose documented operation does not change school data.
  ///
  /// Read-only POST queries are supported. Enrollment submissions and other
  /// mutations must not use this interface because the owner may replay reads
  /// once after renewing authentication. Cookies remain owned by the transport.
  Future<AuthHttpResponse> sendRead(AuthHttpRequest request);
}
