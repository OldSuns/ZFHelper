import 'dart:convert';

import 'package:test/test.dart';
import 'package:zf_core/src/grades/grade_codec.dart';
import 'package:zf_core/src/grades/grade_record.dart';
import 'package:zf_core/src/grades/grade_snapshot.dart';
import 'package:zf_core/src/schedule/academic_term.dart';

void main() {
  test(
    'preserves school values, unknowns and repeated attempts across storage',
    () {
      final details = {'平时成绩': '0', '补考成绩': '通过'};
      final record = GradeRecord(
        id: 'attempt-a',
        name: '测试课程',
        term: AcademicTerm(yearCode: '2025', termCode: '12', label: '学校第二学期'),
        score: '优秀',
        credits: '2.5',
        gradePoint: '0',
        courseCode: 'course',
        teachingClassId: 'section',
        courseNature: '必修',
        courseCategory: '专业课',
        examNature: '补考',
        assessmentMethod: '考试',
        gradeStatus: '已公布',
        retake: '是',
        college: '测试学院',
        teacher: '测试教师',
        passed: true,
        details: details,
      );
      final records = [record, GradeRecord(id: 'attempt-b', name: '测试课程')];
      final snapshot = GradeSnapshot(
        records: records,
        fetchedAt: DateTime.utc(2026, 9, 14),
        sourceLabel: '测试学校教务系统',
      );
      details.clear();
      records.clear();
      final encoded = GradeSnapshotCodec.encode(snapshot);
      final restored = GradeSnapshotCodec.decode(encoded);
      expect(GradeSnapshotCodec.encode(restored), encoded);
      expect(restored.records, hasLength(2));
      expect(restored.records.first.score, '优秀');
      expect(restored.records.first.numericScore, isNull);
      expect(restored.records.first.creditValue, 2.5);
      expect(restored.records.first.gradePointValue, 0);
      expect(restored.records.first.details, {'平时成绩': '0', '补考成绩': '通过'});
      expect(restored.records.last.term, isNull);
      expect(restored.records.last.score, isNull);
      expect(restored.records.last.passed, isNull);
      expect(() => restored.records.clear(), throwsUnsupportedError);
      expect(
        () => restored.records.first.details.clear(),
        throwsUnsupportedError,
      );
    },
  );

  test('rejects corrupt persistence without including the stored payload', () {
    final valid = GradeSnapshotCodec.encode(
      GradeSnapshot(
        records: [GradeRecord(id: 'grade', name: '课程')],
        fetchedAt: DateTime.utc(2026, 9, 14),
        sourceLabel: '测试学校',
      ),
    );
    for (final modify in <void Function(Map<String, Object?>)>[
      (data) => data['version'] = 999,
      (data) => data['fetchedAt'] = '2026-99-99',
      (data) => data['records'] = [
        {
          'id': 'grade',
          'name': '课程',
          'details': <String, String>{},
          'passed': 'true',
        },
      ],
    ]) {
      final data = jsonDecode(valid) as Map<String, Object?>;
      modify(data);
      expect(
        () => GradeSnapshotCodec.decode(jsonEncode(data)),
        throwsFormatException,
      );
    }
    expect(
      () => GradeSnapshotCodec.decode('{"fixture-secret": unfinished'),
      throwsA(
        isA<FormatException>()
            .having((error) => error.source, 'source', isNull)
            .having(
              (error) => error.toString(),
              'diagnostic',
              isNot(contains('fixture-secret')),
            ),
      ),
    );
  });
}
