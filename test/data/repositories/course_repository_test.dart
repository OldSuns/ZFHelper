import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zf_core/src/selection/zhengfang_selection_parser.dart';
import 'package:zf_core/zf_core.dart';
import 'package:zfhelper/data/repositories/academic_source.dart';
import 'package:zfhelper/data/repositories/course_source.dart';
import 'package:zfhelper/data/storage/academic_account.dart';
import 'package:zfhelper/data/storage/course_library_codec.dart';

import '../../support/course_fakes.dart';

// Constructed PartDisplay/detail fields from zhengfang-apk 1ff0815, no account.
void main() {
  test(
    'course list preserves teaching-class vacancies across detail reads',
    () async {
      final source = _Source();
      var now = DateTime.utc(2026, 9, 14);
      final repository = testCourseRepository(source: source, clock: () => now);
      addTearDown(repository.dispose);

      expect(await repository.refresh(), isTrue);
      var course = repository.state.catalog!.courses.single;
      expect((course.capacity, course.selected, course.available), (50, 48, 2));
      expect(source.sectionReads, 1);

      source.enrollments = [22, 26];
      final details = await repository.sections(course);
      expect(details!.sections.last.available, 4);
      course = repository.state.catalog!.courses.single;
      expect((course.capacity, course.selected, course.available), (50, 48, 4));
      final saved = CourseLibraryCodec.decode(
        CourseLibraryCodec.encode(repository.state.library),
      );
      expect(
        saved.accounts.single.selectedCatalog!.courses.single.available,
        4,
      );

      source.failDetails = true;
      expect(await repository.refresh(), isFalse);
      expect(repository.state.failure, contains('读取教学班失败'));
      expect(repository.state.catalog!.courses.single.available, 4);

      source.failDetails = false;
      source.enrollments = [20, 29];
      final fetched = Completer<void>();
      final resume = Completer<void>();
      source.beforeSelectedRead = () async {
        fetched.complete();
        await resume.future;
      };
      final refreshing = repository.refresh();
      await fetched.future;
      source.enrollments = [20, 25];
      now = now.add(const Duration(seconds: 1));
      await repository.sections(course);
      source.beforeSelectedRead = null;
      resume.complete();
      expect(await refreshing, isTrue);
      expect(repository.state.catalog!.courses.single.available, 5);

      source.enrollments = [20, null];
      expect(await repository.refresh(), isTrue);
      expect(repository.state.catalog!.courses.single.available, isNull);

      source.closed = true;
      source.selectedCourses = const [
        SelectedCourse(courseId: 'course', sectionId: 'class-0', name: '算法'),
      ];
      expect(await repository.refresh(), isTrue);
      expect(repository.state.catalog!.courses.single.name, '算法');
      expect(repository.state.catalog!.selectedCourses.single.name, '算法');
    },
  );
}

final class _Source implements CourseSource, SelectionAccessSession {
  final _round = SelectionRound(
    controlKey: 'xkkz_id',
    controlId: 'round',
    categoryCode: '01',
  );
  static const _parser = ZhengfangSelectionParser();
  List<int?> enrollments = [20, 28];
  List<SelectedCourse> selectedCourses = const [];
  int sectionReads = 0;
  bool failDetails = false;
  bool closed = false;
  Future<void> Function()? beforeSelectedRead;

  @override
  AcademicAccountRecord get connectedAccount => const AcademicAccountRecord(
    scope: AccountScope(
      schoolId: 'school-fixture',
      accountId: 'student-fixture',
    ),
    schoolName: '测试学校',
    accountName: '测试学生',
    loginName: 'student-fixture',
  );
  @override
  Stream<AcademicAccountChange> get accountChanges => const Stream.empty();
  @override
  Stream<void> get accessChanges => const Stream.empty();
  @override
  bool canAccess(AccountScope scope) => scope == connectedAccount.scope;
  @override
  SelectionAccessSession open(AccountScope scope) => this;
  @override
  bool get isCurrent => true;
  @override
  Future<SelectionContext> readContext() async => SelectionContext(
    rounds: closed ? const [] : [_round],
    fetchedAt: DateTime.utc(2026, 9, 14),
    pageUri: Uri.parse('https://jw.example.test/jwglxt/xsxk/index.html'),
  );
  @override
  Future<List<CourseOffering>> readCourses(
    SelectionContext context,
    SelectionRound round, {
    String keyword = '',
  }) async => _parser.parseCourses(
    '{"tmpList":[{"kch_id":"course","kcmc":"算法","xf":"2"}]}',
    context: context,
    round: round,
  );
  @override
  Future<List<CourseSection>> readSections(
    SelectionContext context,
    CourseOffering course,
  ) async {
    sectionReads++;
    if (failDetails) {
      throw const SelectionException(
        SelectionFailureCode.schoolRejected,
        '读取教学班失败',
      );
    }
    return _parser.parseSections(
      jsonEncode([
        for (var index = 0; index < enrollments.length; index++)
          {
            'kch_id': 'course',
            'jxb_id': 'class-$index',
            'jxbrl': index == 0 ? '20' : '30',
            'yxzrs': enrollments[index]?.toString(),
          },
      ]),
      context: context,
      course: course,
    );
  }

  @override
  Future<List<SelectedCourse>> readSelected(
    SelectionContext context, {
    SelectionRound? round,
  }) async {
    await beforeSelectedRead?.call();
    return selectedCourses;
  }

  @override
  Future<SelectionSubmission> submit(
    SelectionContext context,
    CourseOffering course,
    CourseSection section, {
    required bool Function() shouldSend,
  }) => throw StateError('Read-only fixture must not submit');
}
