import 'package:zf_core/zf_core.dart';

import '../storage/schedule_store.dart';

abstract interface class ScheduleReadSession {
  bool get isCurrent;
  Future<ScheduleImportResult> read({AcademicTerm? term});
}

final class ScheduleAccountChange {
  const ScheduleAccountChange(this.account, {required this.selectForViewing});

  final ScheduleAccountRecord? account;
  final bool selectForViewing;
}

abstract interface class ScheduleSource {
  ScheduleAccountRecord? get connectedAccount;
  Stream<ScheduleAccountChange> get accountChanges;
  ScheduleReadSession open(AccountScope scope);
}

final class AuthenticatedScheduleSource implements ScheduleSource {
  AuthenticatedScheduleSource({required this._auth, required this._clock});

  final AuthRepository _auth;
  final DateTime Function() _clock;

  @override
  ScheduleAccountRecord? get connectedAccount =>
      _record(_auth.state.knownIdentity);

  @override
  Stream<ScheduleAccountChange> get accountChanges {
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
          (state) => ScheduleAccountChange(
            _record(state.knownIdentity),
            // Restoring credentials exposes the local identity before contacting the
            // school. It must not change which saved timetable the user was viewing.
            selectForViewing: state.isSignedIn,
          ),
        );
  }

  @override
  ScheduleReadSession open(AccountScope scope) {
    final identity = _auth.state.knownIdentity;
    if (identity == null || identity.scope != scope) {
      throw const LoginFailure(
        LoginFailureCode.expired,
        '请先连接此课表所属的教务账号，已保存的课程仍可查看',
      );
    }
    return _AuthenticatedScheduleRead(_auth, identity, _clock);
  }

  static ScheduleAccountRecord? _record(AuthIdentity? identity) =>
      identity == null
      ? null
      : ScheduleAccountRecord(
          scope: identity.scope,
          schoolName: identity.profile.name,
          accountName: identity.account.displayName,
          loginName: identity.account.loginName,
        );
}

final class _AuthenticatedScheduleRead implements ScheduleReadSession {
  _AuthenticatedScheduleRead(this._auth, this._identity, this._clock);

  final AuthRepository _auth;
  final AuthIdentity _identity;
  final DateTime Function() _clock;

  @override
  bool get isCurrent => _auth.isCurrentIdentity(_identity);

  @override
  Future<ScheduleImportResult> read({AcademicTerm? term}) async {
    _requireCurrent();
    if (!_auth.state.isSignedIn) await _auth.restore();
    _requireCurrent();
    final result = await _auth.runRead(
      _identity.scope,
      (client) => ZhengfangScheduleGateway(
        profile: _identity.profile,
        client: client,
        clock: _clock,
        studentId: _identity.account.studentId,
      ).importSchedule(term: term),
    );
    _requireCurrent();
    return result;
  }

  void _requireCurrent() {
    if (!isCurrent) {
      throw const LoginFailure(LoginFailureCode.cancelled, '账号已切换，本次课表导入已取消');
    }
  }
}
