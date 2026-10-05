import 'dart:async';

import 'package:zf_core/zf_core.dart';
import 'package:zfhelper/data/repositories/academic_source.dart';
import 'package:zfhelper/data/repositories/grade_repository.dart';
import 'package:zfhelper/data/repositories/grade_source.dart';
import 'package:zfhelper/data/storage/academic_account.dart';
import 'package:zfhelper/data/storage/grade_store.dart';

final class TestGradeStore implements GradeStore {
  TestGradeStore({GradeLibrary? library}) : library = library ?? GradeLibrary();

  GradeLibrary library;
  GradeStorageException? failure;
  Future<void> Function(GradeLibrary)? beforeWrite;
  int reads = 0;
  int writes = 0;
  bool closed = false;

  void _check() {
    if (closed) throw StateError('Test grade store is closed.');
    if (failure case final error?) throw error;
  }

  @override
  Future<GradeLibrary> read() async {
    _check();
    reads++;
    return library;
  }

  @override
  Future<void> write(GradeLibrary value) async {
    _check();
    await beforeWrite?.call(value);
    writes++;
    library = value;
  }

  @override
  Future<void> close() async => closed = true;
}

final class TestGradeSource implements GradeSource {
  TestGradeSource({this._account});
  final _changes = StreamController<AcademicAccountChange>.broadcast(
    sync: true,
  );
  AcademicAccountRecord? _account;
  int generation = 0;
  int requests = 0;
  Future<GradeSnapshot> Function()? onRead;

  @override
  AcademicAccountRecord? get connectedAccount => _account;
  @override
  Stream<AcademicAccountChange> get accountChanges => _changes.stream;

  void connect(AcademicAccountRecord? account, {bool selectForViewing = true}) {
    _account = account;
    generation++;
    _changes.add(
      AcademicAccountChange(account, selectForViewing: selectForViewing),
    );
  }

  @override
  GradeReadSession open(AccountScope scope) {
    if (scope != _account?.scope) {
      throw const LoginFailure(LoginFailureCode.expired, '请登录成绩所属账号');
    }
    return _TestGradeRead(this, scope, generation);
  }

  Future<void> dispose() => _changes.close();
}

final class _TestGradeRead implements GradeReadSession {
  _TestGradeRead(this.source, this.scope, this.generation);
  final TestGradeSource source;
  final AccountScope scope;
  final int generation;

  @override
  bool get isCurrent =>
      source.generation == generation &&
      source.connectedAccount?.scope == scope;

  @override
  Future<GradeSnapshot> read() {
    source.requests++;
    return source.onRead?.call() ??
        (throw StateError('Unexpected grade query.'));
  }
}

GradeRepository testGradeRepository({
  TestGradeStore? store,
  TestGradeSource? source,
}) => GradeRepository(
  store: store ?? TestGradeStore(),
  source: source ?? TestGradeSource(),
);

AcademicAccountRecord gradeAccount({
  String school = 'https://school.example/jwglxt/',
  String id = 'student',
}) => AcademicAccountRecord(
  scope: AccountScope(schoolId: school, accountId: id),
  schoolName: '示例大学',
  accountName: '学生',
  loginName: id,
);

AcademicTerm gradeTerm({
  String year = '2025',
  ZhengfangSemester semester = ZhengfangSemester.first,
}) => AcademicTerm.zhengfang(startYear: year, semester: semester);

GradeSnapshot gradeSnapshot({
  List<GradeRecord>? records,
  DateTime? fetchedAt,
}) => GradeSnapshot(
  records:
      records ??
      [
        GradeRecord(
          id: 'one',
          name: '高等数学',
          term: gradeTerm(),
          score: '85',
          credits: '4',
          gradePoint: '3.5',
        ),
      ],
  fetchedAt: fetchedAt ?? DateTime.utc(2026, 9, 14),
  sourceLabel: '示例大学教务系统',
);
