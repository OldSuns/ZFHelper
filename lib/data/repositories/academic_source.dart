import 'package:zf_core/zf_core.dart';

import '../storage/academic_account.dart';

final class AcademicAccountChange {
  const AcademicAccountChange(this.account, {required this.selectForViewing});

  final AcademicAccountRecord? account;
  final bool selectForViewing;
}

/// Keeps identity projections retryable until their cache writes succeed.
final class PendingAcademicAccountChanges {
  final _changes = <AcademicAccountChange>[];

  bool get isEmpty => _changes.isEmpty;
  void add(AcademicAccountChange change) => _changes.add(change);
  void remove(AccountScope scope) =>
      _changes.removeWhere((change) => change.account?.scope == scope);

  Future<void> drain(Future<void> Function(AcademicAccountChange) apply) async {
    while (_changes.isNotEmpty) {
      final change = _changes.first;
      await apply(change);
      _changes.remove(change);
    }
  }
}

/// Projects the single authentication owner into cacheable academic identities.
final class AuthenticatedAcademicSource {
  AuthenticatedAcademicSource({required this._auth});

  final AuthRepository _auth;

  AcademicAccountRecord? get connectedAccount =>
      _record(_auth.state.knownIdentity);

  Stream<AcademicAccountChange> get accountChanges {
    return Stream<AcademicAccountChange>.multi((controller) {
      AuthSnapshot? previous;
      void publish(AuthSnapshot state) {
        if (!state.accountsLoaded) return;
        final before = previous;
        previous = state;
        final oldAccounts = {
          for (final account in before?.accounts ?? <AuthAccountSummary>[])
            account.scope: account,
        };
        for (final account in state.accounts) {
          if (account.scope == state.selectedScope) continue;
          if (!_sameLabels(oldAccounts[account.scope], account)) {
            controller.addSync(
              AcademicAccountChange(
                _savedRecord(account),
                selectForViewing: false,
              ),
            );
          }
        }
        final selectionChanged =
            before == null ||
            before.selectedScope != state.selectedScope ||
            before.profile?.school.id != state.profile?.school.id;
        if (selectionChanged ||
            before.knownIdentity?.generation !=
                state.knownIdentity?.generation ||
            !_sameLabels(before.selectedAccount, state.selectedAccount)) {
          controller.addSync(
            AcademicAccountChange(
              _savedRecord(state.selectedAccount),
              selectForViewing: selectionChanged,
            ),
          );
        }
      }

      final subscription = _auth.changes.listen(
        publish,
        onError: controller.addErrorSync,
        onDone: controller.closeSync,
      );
      controller.onCancel = subscription.cancel;
      publish(_auth.state);
    }, isBroadcast: true);
  }

  static bool _sameLabels(AuthAccountSummary? a, AuthAccountSummary? b) =>
      a?.scope == b?.scope &&
      a?.profile.name == b?.profile.name &&
      a?.account.displayName == b?.account.displayName &&
      a?.account.loginName == b?.account.loginName;

  static AcademicAccountRecord? _savedRecord(AuthAccountSummary? saved) =>
      saved == null
      ? null
      : AcademicAccountRecord(
          scope: saved.scope,
          schoolName: saved.profile.name,
          accountName: saved.account.displayName,
          loginName: saved.account.loginName,
        );

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
