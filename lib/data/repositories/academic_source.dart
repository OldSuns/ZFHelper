import 'package:zf_core/zf_core.dart';

import '../storage/academic_account.dart';

final class AcademicAccountChange {
  const AcademicAccountChange(this.account, {required this.selectForViewing});

  final AcademicAccountRecord? account;
  final bool selectForViewing;
}

/// Projects the single authentication owner into cacheable academic identities.
final class AuthenticatedAcademicSource {
  AuthenticatedAcademicSource({required this._auth});

  final AuthRepository _auth;

  AcademicAccountRecord? get connectedAccount =>
      _record(_auth.state.knownIdentity);

  Stream<AcademicAccountChange> get accountChanges {
    var previous = _auth.state.knownIdentity;
    return _auth.changes
        .where((state) {
          final next = state.knownIdentity;
          final changed =
              previous?.scope != next?.scope ||
              previous?.generation != next?.generation;
          previous = next;
          return changed;
        })
        .map(
          (state) => AcademicAccountChange(
            _record(state.knownIdentity),
            // Offline restoration must preserve the account the user was viewing.
            selectForViewing: state.isSignedIn,
          ),
        );
  }

  AcademicReadSession open(AccountScope scope) {
    final identity = _auth.state.knownIdentity;
    if (identity == null || identity.scope != scope) {
      throw const LoginFailure(
        LoginFailureCode.expired,
        '请先连接此数据所属的教务账号，已保存的数据仍可查看',
      );
    }
    return AcademicReadSession._(_auth, identity);
  }

  static AcademicAccountRecord? _record(AuthIdentity? identity) =>
      identity == null
      ? null
      : AcademicAccountRecord(
          scope: identity.scope,
          schoolName: identity.profile.name,
          accountName: identity.account.displayName,
          loginName: identity.account.loginName,
        );
}

/// Captures one identity for an entire read, including all response pages.
final class AcademicReadSession {
  AcademicReadSession._(this._auth, this._identity);

  final AuthRepository _auth;
  final AuthIdentity _identity;

  bool get isCurrent => _auth.isCurrentIdentity(_identity);
  SchoolConnection get profile => _identity.profile;
  String? get studentId => _identity.account.studentId;

  Future<T> read<T>(
    Future<T> Function(AuthenticatedReadClient) operation,
  ) async {
    _requireCurrent();
    if (!_auth.state.isSignedIn) await _auth.restore();
    _requireCurrent();
    final result = await _auth.runRead(_identity.scope, operation);
    _requireCurrent();
    return result;
  }

  void _requireCurrent() {
    if (!isCurrent) {
      throw const LoginFailure(LoginFailureCode.cancelled, '账号已切换，本次教务查询已取消');
    }
  }
}
