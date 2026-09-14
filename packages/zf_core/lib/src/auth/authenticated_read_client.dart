import 'login_models.dart';

/// Access to queries through the account owner's authenticated transport.
abstract interface class AuthenticatedReadClient {
  /// Sends a request whose documented operation does not change school data.
  ///
  /// Read-only POST queries are supported. Enrollment submissions and other
  /// mutations must enter through AuthRepository.runAccountMutation, which binds
  /// this request interface to a one-shot submission transport. Read scopes may
  /// replay once after renewal. Cookies remain owned by the transport.
  Future<AuthHttpResponse> sendRead(AuthHttpRequest request);
}

/// A submission transport that neither follows redirects nor repeats requests.
/// Repository operation scopes expose it only for one explicitly chosen action.
abstract interface class AuthenticatedMutationClient {
  Future<AuthHttpResponse> sendMutation(AuthHttpRequest request);
}
