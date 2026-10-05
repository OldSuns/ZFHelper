import 'grade_record.dart';

/// Descriptive totals for the visible records, not an official school GPA.
final class GradeSummary {
  factory GradeSummary(Iterable<GradeRecord> records) {
    var recordCount = 0;
    var creditsCount = 0;
    var totalCredits = 0.0;
    var gradePointCount = 0;
    var gradePointCredits = 0.0;
    var points = 0.0;
    for (final record in records) {
      recordCount++;
      final credit = record.creditValue;
      if (credit == null || credit < 0) continue;
      creditsCount++;
      totalCredits += credit;
      final point = record.gradePointValue;
      if (credit <= 0 || point == null || point < 0) continue;
      gradePointCount++;
      gradePointCredits += credit;
      points += credit * point;
    }
    return GradeSummary._(
      recordCount: recordCount,
      creditsCount: creditsCount,
      totalCredits: totalCredits,
      gradePointCount: gradePointCount,
      gradePointCredits: gradePointCredits,
      weightedGradePoint: gradePointCredits == 0
          ? null
          : points / gradePointCredits,
    );
  }

  const GradeSummary._({
    required this.recordCount,
    required this.creditsCount,
    required this.totalCredits,
    required this.gradePointCount,
    required this.gradePointCredits,
    required this.weightedGradePoint,
  });

  final int recordCount;
  final int creditsCount;
  final double totalCredits;
  final int gradePointCount;
  final double gradePointCredits;
  final double? weightedGradePoint;
}
