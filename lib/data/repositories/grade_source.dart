import 'package:zf_core/zf_core.dart';

import '../storage/academic_account.dart';
import 'academic_source.dart';

abstract interface class GradeReadSession {
  bool get isCurrent;
  Future<GradeSnapshot> read();
}

abstract interface class GradeSource {
  AcademicAccountRecord? get connectedAccount;
  Stream<AcademicAccountChange> get accountChanges;
  GradeReadSession open(AccountScope scope);
}

final class AuthenticatedGradeSource implements GradeSource {
  AuthenticatedGradeSource({required AuthRepository auth, required this._clock})
    : _source = AuthenticatedAcademicSource(auth: auth);

  final AuthenticatedAcademicSource _source;
  final DateTime Function() _clock;

  @override
  AcademicAccountRecord? get connectedAccount => _source.connectedAccount;

  @override
  Stream<AcademicAccountChange> get accountChanges => _source.accountChanges;

  @override
  GradeReadSession open(AccountScope scope) =>
      _AuthenticatedGradeRead(_source.open(scope), _clock);
}

final class _AuthenticatedGradeRead implements GradeReadSession {
  _AuthenticatedGradeRead(this._session, this._clock);

  final AcademicReadSession _session;
  final DateTime Function() _clock;

  @override
  bool get isCurrent => _session.isCurrent;

  @override
  Future<GradeSnapshot> read() => _session.read(
    (client) => ZhengfangGradeGateway(
      profile: _session.profile,
      client: client,
      clock: _clock,
      studentId: _session.studentId,
    ).readGrades(),
  );
}
