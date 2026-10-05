import 'package:test/test.dart';
import 'package:zf_core/zf_core.dart';

void main() {
  test('weights only school points and keeps failed and repeated attempts', () {
    final summary = GradeSummary([
      GradeRecord(
        id: 'first',
        name: '数学',
        score: '不及格',
        credits: '4',
        gradePoint: '0',
      ),
      GradeRecord(
        id: 'retake',
        name: '数学',
        score: '85',
        credits: '4',
        gradePoint: '3.5',
        retake: '是',
      ),
      GradeRecord(id: 'text', name: '实践', score: '优秀', credits: '2'),
      GradeRecord(id: 'missing', name: '讲座', gradePoint: '4'),
    ]);
    expect(summary.recordCount, 4);
    expect(summary.creditsCount, 3);
    expect(summary.totalCredits, 10);
    expect(summary.gradePointCount, 2);
    expect(summary.gradePointCredits, 8);
    expect(summary.weightedGradePoint, 1.75);
  });

  test('unavailable or invalid values do not produce a zero GPA', () {
    final summary = GradeSummary([
      GradeRecord(id: 'zero-credit', name: '讲座', credits: '0', gradePoint: '4'),
      GradeRecord(
        id: 'unknown',
        name: '实践',
        score: '良好',
        credits: '2',
        gradePoint: '--',
      ),
      GradeRecord(id: 'invalid', name: '待定', credits: '-1', gradePoint: 'NaN'),
    ]);
    expect(summary.gradePointCount, 0);
    expect(summary.weightedGradePoint, isNull);
    expect(summary.totalCredits, 2);
  });
}
