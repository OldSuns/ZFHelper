import 'package:zf_core/zf_core.dart';

import '../storage/schedule_store.dart';
import 'academic_source.dart';

export 'academic_source.dart' show AcademicAccountChange;

abstract interface class ScheduleReadSession {
  bool get isCurrent;
  Future<ScheduleImportResult> read({AcademicTerm? term});
}

abstract interface class ScheduleSource {
  AcademicAccountRecord? get connectedAccount;
  Stream<AcademicAccountChange> get accountChanges;
  ScheduleReadSession open(AccountScope scope);
}

final class AuthenticatedScheduleSource implements ScheduleSource {
  AuthenticatedScheduleSource({
    required AuthRepository auth,
    required this._clock,
  }) : _source = AuthenticatedAcademicSource(auth: auth);

  final AuthenticatedAcademicSource _source;
  final DateTime Function() _clock;

  @override
  AcademicAccountRecord? get connectedAccount => _source.connectedAccount;

  @override
  Stream<AcademicAccountChange> get accountChanges => _source.accountChanges;

  @override
  ScheduleReadSession open(AccountScope scope) =>
      _AuthenticatedScheduleRead(_source.open(scope), _clock);
}

final class _AuthenticatedScheduleRead implements ScheduleReadSession {
  _AuthenticatedScheduleRead(this._session, this._clock);

  final AcademicReadSession _session;
  final DateTime Function() _clock;

  @override
  bool get isCurrent => _session.isCurrent;

  @override
  Future<ScheduleImportResult> read({AcademicTerm? term}) => _session.read(
    (client) => ZhengfangScheduleGateway(
      profile: _session.profile,
      client: client,
      clock: _clock,
      studentId: _session.studentId,
    ).importSchedule(term: term),
  );
}
