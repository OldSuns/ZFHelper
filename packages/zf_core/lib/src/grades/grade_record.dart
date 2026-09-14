import '../schedule/academic_term.dart';
import 'grade_term_group.dart';

/// One school-published assessment, including repeated course attempts.
final class GradeRecord {
  GradeRecord({
    required this.id,
    required this.name,
    this.term,
    this.score,
    this.credits,
    this.gradePoint,
    this.courseCode,
    this.teachingClassId,
    this.courseNature,
    this.courseCategory,
    this.examNature,
    this.assessmentMethod,
    this.gradeStatus,
    this.retake,
    this.college,
    this.teacher,
    this.passed,
    Map<String, String> details = const {},
  }) : details = Map.unmodifiable(details) {
    if (id.trim().isEmpty || name.trim().isEmpty) {
      throw ArgumentError('A grade record needs an ID and course name.');
    }
  }

  final String id;
  final String name;
  final AcademicTerm? term;
  final String? score;
  final String? credits;
  final String? gradePoint;
  final String? courseCode;
  final String? teachingClassId;
  final String? courseNature;
  final String? courseCategory;
  final String? examNature;
  final String? assessmentMethod;
  final String? gradeStatus;
  final String? retake;
  final String? college;
  final String? teacher;

  /// Only a school-provided pass status, never a universal score threshold.
  final bool? passed;
  final Map<String, String> details;

  GradeTermGroup? get termGroup => term == null ? null : GradeTermGroup(term!);
  String get termKey => termGroup?.key ?? unassignedGradeTermKey;

  double? get numericScore => _number(score);
  double? get creditValue => _number(credits);
  double? get gradePointValue => _number(gradePoint);

  static double? _number(String? source) {
    if (source == null) return null;
    final value = double.tryParse(source.trim());
    return value != null && value.isFinite ? value : null;
  }
}
