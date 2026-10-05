import 'dart:async';

import 'package:test/test.dart';
import 'package:zf_core/zf_core.dart';

// Explicit in-memory school responses; these do not represent real enrollment.
void main() {
  test(
    'accepted responses need class evidence; restart never replays',
    () async {
      final school = _School();
      final store = _Store();
      final coordinator = _coordinator(school, store);
      await coordinator.start(_target, mode: SelectionMode.immediate);
      await _until(
        coordinator,
        () => coordinator.operations.single.status == SelectionStatus.uncertain,
      );
      expect(school.submissions, 1);
      expect(store.operations.single.status, SelectionStatus.uncertain);
      await coordinator.dispose();

      store.operations = [
        store.operations.single.copyWith(status: SelectionStatus.submitting),
      ];
      final restored = _coordinator(school, store);
      addTearDown(restored.dispose);
      await restored.initialize();
      expect(restored.operations.single.status, SelectionStatus.uncertain);
      expect(school.submissions, 1);
      school.selected = true;
      await restored.verify(restored.operations.single.id);
      await _until(
        restored,
        () => restored.operations.single.status == SelectionStatus.succeeded,
      );
      expect(school.submissions, 1);
    },
  );

  test(
    'cancel before dispatch and failed intent persistence prevent sending',
    () async {
      final school = _School()..sendGate = Completer<void>();
      final store = _Store();
      final coordinator = _coordinator(school, store);
      addTearDown(coordinator.dispose);
      await coordinator.start(_target, mode: SelectionMode.immediate);
      await school.entered.future;
      await coordinator.stop(coordinator.operations.single.id);
      school.sendGate!.complete();
      await _until(
        coordinator,
        () => coordinator.operations.single.status == SelectionStatus.cancelled,
      );
      expect(school.submissions, 0);

      store.failIntent = true;
      await coordinator.resume(coordinator.operations.single.id);
      await _until(coordinator, () => coordinator.failure != null);
      expect(school.submissions, 0);
      store.failIntent = false;
      await coordinator.clearHistory();
      expect(coordinator.failure, isNotNull);
      await Future<void>(
        () {},
      ); // Let the already-stopped runner release its slot.
      await coordinator.initialize();
      expect(coordinator.operations.single.status, SelectionStatus.paused);
      await coordinator.stop(coordinator.operations.single.id);
      expect(coordinator.operations.single.status, SelectionStatus.cancelled);
    },
  );
}

SelectionCoordinator _coordinator(_School school, _Store store) =>
    SelectionCoordinator(
      access: school,
      store: store,
      clock: DateTime.now,
      syncRuntime: (_) async {},
    );

Future<void> _until(
  SelectionCoordinator coordinator,
  bool Function() ready,
) async {
  if (ready()) return;
  await coordinator.changes
      .firstWhere((_) => ready())
      .timeout(const Duration(seconds: 3));
}

final _round = SelectionRound(
  controlKey: 'xkkz_id',
  controlId: 'round',
  categoryCode: 'type',
);
final _target = SelectionTarget(
  scope: const AccountScope(schoolId: 'school', accountId: 'student'),
  schoolName: '测试学校',
  accountName: '测试账号',
  round: _round,
  courseId: 'course',
  sectionId: 'class',
  name: '课程',
);

final class _Store implements SelectionOperationStore {
  List<SelectionOperation> operations = const [];
  bool failIntent = false;
  @override
  Future<List<SelectionOperation>> readOperations() async => operations;
  @override
  Future<void> writeOperations(List<SelectionOperation> value) async {
    if (failIntent &&
        value.any((item) => item.status == SelectionStatus.submitting)) {
      throw const SelectionStorageException('构造的存储写入失败');
    }
    operations = value;
  }
}

final class _School implements SelectionAccess, SelectionAccessSession {
  int submissions = 0;
  bool selected = false;
  Completer<void>? sendGate;
  final entered = Completer<void>();
  @override
  bool get isCurrent => true;
  @override
  SelectionAccessSession open(AccountScope scope) => this;
  @override
  Future<SelectionContext> readContext() async => SelectionContext(
    rounds: [_round],
    fetchedAt: DateTime.now(),
    pageUri: Uri.parse('https://school.example/selection'),
  );
  @override
  Future<List<CourseOffering>> readCourses(
    SelectionContext context,
    SelectionRound round, {
    String keyword = '',
  }) async => [
    CourseOffering(roundKey: round.key, courseId: 'course', name: '课程'),
  ];
  @override
  Future<List<CourseSection>> readSections(
    SelectionContext context,
    CourseOffering course,
  ) async => [
    CourseSection(
      roundKey: course.roundKey,
      courseId: course.courseId,
      sectionId: 'class',
      name: '教学班',
      capacity: 20,
      selected: 19,
    ),
  ];
  @override
  Future<List<SelectedCourse>> readSelected(
    SelectionContext context, {
    SelectionRound? round,
  }) async => [
    SelectedCourse(
      courseId: 'course',
      sectionId: selected ? 'class' : 'other-class',
      name: '课程',
    ),
  ];
  @override
  Future<SelectionSubmission> submit(
    SelectionContext context,
    CourseOffering course,
    CourseSection section, {
    required bool Function() shouldSend,
  }) async {
    if (!entered.isCompleted) entered.complete();
    await sendGate?.future;
    if (!shouldSend()) throw const SelectionNotSentException();
    submissions++;
    return const SelectionSubmission(
      SelectionSubmissionStatus.accepted,
      'accepted',
    );
  }
}
