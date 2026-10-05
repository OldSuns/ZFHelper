import 'package:zf_core/zf_core.dart';

import '../storage/academic_account.dart';
import 'academic_source.dart';

abstract interface class CourseSource implements SelectionAccess {
  AcademicAccountRecord? get connectedAccount;
  Stream<AcademicAccountChange> get accountChanges;
  Stream<void> get accessChanges;
  bool canAccess(AccountScope scope);
}

final class AuthenticatedCourseSource implements CourseSource {
  AuthenticatedCourseSource({
    required AuthRepository auth,
    required this._clock,
  }) : _auth = auth,
       _source = AuthenticatedAcademicSource(auth: auth);
  final AuthRepository _auth;
  final DateTime Function() _clock;
  final AuthenticatedAcademicSource _source;

  @override
  AcademicAccountRecord? get connectedAccount => _source.connectedAccount;
  @override
  Stream<AcademicAccountChange> get accountChanges => _source.accountChanges;
  @override
  Stream<void> get accessChanges => _auth.changes.map((_) {});
  @override
  bool canAccess(AccountScope scope) => _auth.identityFor(scope) != null;
  @override
  SelectionAccessSession open(AccountScope scope) {
    final identity = _auth.identityFor(scope);
    if (identity == null) {
      throw const LoginFailure(LoginFailureCode.expired, '请先登录此课程所属的账号');
    }
    return _CourseSession(_auth, identity, _clock);
  }
}

final class _CourseSession implements SelectionAccessSession {
  _CourseSession(this._auth, this._identity, this._clock);
  final AuthRepository _auth;
  final AuthIdentity _identity;
  final DateTime Function() _clock;
  @override
  bool get isCurrent => _auth.isAccountIdentityCurrent(_identity);

  ZhengfangSelectionGateway _gateway(AuthenticatedReadClient client) =>
      ZhengfangSelectionGateway(
        profile: _identity.profile,
        client: client,
        clock: _clock,
        studentId: _identity.account.studentId,
      );

  @override
  Future<SelectionContext> readContext() => _auth.runAccountRead(
    _identity,
    (client) => _gateway(client).readContext(),
  );
  @override
  Future<List<CourseOffering>> readCourses(
    SelectionContext context,
    SelectionRound round, {
    String keyword = '',
  }) => _auth.runAccountRead(
    _identity,
    (client) => _gateway(client).readCourses(context, round, keyword: keyword),
  );
  @override
  Future<List<CourseSection>> readSections(
    SelectionContext context,
    CourseOffering course,
  ) => _auth.runAccountRead(
    _identity,
    (client) => _gateway(client).readSections(context, course),
  );
  @override
  Future<List<SelectedCourse>> readSelected(
    SelectionContext context, {
    SelectionRound? round,
  }) => _auth.runAccountRead(
    _identity,
    (client) => _gateway(client).readSelected(context, round: round),
  );
  @override
  Future<SelectionSubmission> submit(
    SelectionContext context,
    CourseOffering course,
    CourseSection section, {
    required bool Function() shouldSend,
  }) => _auth.runAccountMutation(_identity, (client) {
    // Authentication/another submission may have delayed entry to this scope.
    if (!shouldSend()) throw const SelectionNotSentException();
    return _gateway(client).submit(context, course, section);
  });
}
