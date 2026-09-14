import '../schedule/academic_term.dart';

enum SelectionFailureCode {
  protocol,
  roundClosed,
  schoolRejected,
  identityMismatch,
  incompleteResponse,
}

final class SelectionException implements Exception {
  const SelectionException(this.code, this.message);

  final SelectionFailureCode code;
  final String message;

  @override
  String toString() => 'SelectionException(${code.name}): $message';
}

/// A school's selection category and round, with its original request codes.
final class SelectionRound {
  SelectionRound({
    required this.controlKey,
    required this.controlId,
    required this.categoryCode,
    this.categoryLabel = '',
    String? label,
    this.term,
    this.gradeId = '',
    this.majorId = '',
    Map<String, String> form = const {},
  }) : label = label ?? (categoryLabel.isEmpty ? categoryCode : categoryLabel),
       form = Map.unmodifiable(form);

  final String controlKey;
  final String controlId;
  final String categoryCode;
  final String categoryLabel;
  final String label;
  final AcademicTerm? term;
  final String gradeId;
  final String majorId;

  /// Live page fields, including any request tokens. Never persist this map.
  final Map<String, String> form;

  String get key => _key([
    term?.key ?? '',
    controlKey,
    controlId,
    categoryCode,
    gradeId,
    majorId,
  ]);
}

/// Live school page context. This object must be read again before a write.
final class SelectionContext {
  SelectionContext({
    required List<SelectionRound> rounds,
    required this.fetchedAt,
    required this.pageUri,
    Map<String, String> form = const {},
    this.studentId,
  }) : rounds = List.unmodifiable(rounds),
       form = Map.unmodifiable(form);

  final List<SelectionRound> rounds;
  final DateTime fetchedAt;
  final Uri pageUri;
  final String? studentId;
  final Map<String, String> form;

  /// Local provenance only; this is neither a cookie nor a school token.
  final Object token = Object();
}

final class CourseOffering {
  CourseOffering({
    required this.roundKey,
    required this.courseId,
    required this.name,
    this.sectionId,
    this.teacher,
    this.time,
    this.location,
    this.credit,
    this.capacity,
    this.selected,
    this.isSelected,
    Map<String, String> form = const {},
    this.contextToken,
  }) : form = Map.unmodifiable(form);

  final String roundKey;
  final String courseId;
  final String name;
  final String? sectionId;
  final String? teacher;
  final String? time;
  final String? location;
  final String? credit;
  final int? capacity;
  final int? selected;
  final bool? isSelected;

  /// Transient response fields needed to request fresh teaching-class details.
  final Map<String, String> form;
  final Object? contextToken;

  String get key => _key([roundKey, courseId, sectionId ?? '']);
  int? get available =>
      capacity == null || selected == null ? null : capacity! - selected!;
}

final class CourseSection {
  CourseSection({
    required this.roundKey,
    required this.courseId,
    required this.sectionId,
    required this.name,
    this.teacher,
    this.time,
    this.location,
    this.capacity,
    this.selected,
    this.isSelected,
    this.submitId,
    Map<String, String> form = const {},
    this.contextToken,
  }) : form = Map.unmodifiable(form);

  final String roundKey;
  final String courseId;

  /// The stable jxb_id, kept separately from the encrypted submission value.
  final String sectionId;
  final String name;
  final String? teacher;
  final String? time;
  final String? location;
  final int? capacity;
  final int? selected;
  final bool? isSelected;

  /// The fresh do_jxb_id (or school's jxb_id). Never persist this value.
  final String? submitId;
  final Map<String, String> form;
  final Object? contextToken;

  String get key => _key([roundKey, courseId, sectionId]);
  int? get available =>
      capacity == null || selected == null ? null : capacity! - selected!;
}

final class SelectedCourse {
  const SelectedCourse({
    required this.courseId,
    required this.sectionId,
    required this.name,
    this.term,
    this.teacher,
    this.time,
    this.location,
  });

  final String courseId;
  final String sectionId;
  final String name;
  final AcademicTerm? term;
  final String? teacher;
  final String? time;
  final String? location;

  String get key => _key([term?.key ?? '', courseId, sectionId]);

  bool matches(CourseSection section) =>
      sectionId.isNotEmpty &&
      courseId == section.courseId &&
      sectionId == section.sectionId;
}

enum SelectionSubmissionStatus { accepted, rejected, unknown }

/// A submission response is not evidence that the school enrolled the student.
final class SelectionSubmission {
  const SelectionSubmission(this.status, this.message);

  final SelectionSubmissionStatus status;
  final String message;
}

String _key(List<String> parts) => parts.map(Uri.encodeComponent).join('|');
