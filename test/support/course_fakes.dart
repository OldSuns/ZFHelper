import 'package:zf_core/zf_core.dart';
import 'package:zfhelper/data/repositories/academic_source.dart';
import 'package:zfhelper/data/repositories/course_repository.dart';
import 'package:zfhelper/data/repositories/course_source.dart';
import 'package:zfhelper/data/storage/academic_account.dart';
import 'package:zfhelper/data/storage/course_store.dart';
import 'package:zfhelper/platform/selection_runtime.dart';

CourseRepository testCourseRepository() {
  final store = _Store();
  return CourseRepository(
    store: store,
    operationStore: store,
    source: _Source(),
    runtime: _Runtime(),
    clock: DateTime.now,
  );
}

final class _Store implements CourseStore, SelectionOperationStore {
  CourseLibrary library = CourseLibrary();
  List<SelectionOperation> operations = const [];
  @override
  Future<CourseLibrary> read() async => library;
  @override
  Future<void> write(CourseLibrary value) async => library = value;
  @override
  Future<List<SelectionOperation>> readOperations() async => operations;
  @override
  Future<void> writeOperations(List<SelectionOperation> value) async =>
      operations = value;
  @override
  Future<void> close() async {}
}

final class _Source implements CourseSource {
  @override
  AcademicAccountRecord? get connectedAccount => null;
  @override
  Stream<AcademicAccountChange> get accountChanges => const Stream.empty();
  @override
  Stream<void> get accessChanges => const Stream.empty();
  @override
  bool canAccess(AccountScope scope) => false;
  @override
  SelectionAccessSession open(AccountScope scope) =>
      throw StateError('Unexpected school access');
}

final class _Runtime implements SelectionRuntime {
  @override
  Stream<SelectionRuntimeEvent> get events => const Stream.empty();
  @override
  Future<SelectionRuntimeCapabilities> capabilities() async =>
      const SelectionRuntimeCapabilities(
        mode: SelectionRuntimeMode.process,
        notificationsGranted: true,
        running: false,
        canStart: true,
      );
  @override
  Future<SelectionRuntimeCapabilities> prepare() => capabilities();
  @override
  Future<void> sync({required int activeWorkCount}) async {}
  @override
  Future<void> dispose() async {}
}
