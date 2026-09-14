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
    this.sectionCount,
    this.sectionAvailability,
    this.availabilityFetchedAt,
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
  final int? sectionCount;

  /// Sum of per-class vacancies; an overbooked class cannot consume seats in
  /// another class. Null means at least one class did not provide its counts.
  final int? sectionAvailability;
  final DateTime? availabilityFetchedAt;
  final bool? isSelected;

  /// Transient response fields needed to request fresh teaching-class details.
  final Map<String, String> form;
  final Object? contextToken;

  String get key => _key([roundKey, courseId, sectionId ?? '']);
  int? get available => sectionCount != null
      ? sectionAvailability
      : capacity == null || selected == null
      ? null
      : capacity! - selected!;

  CourseOffering withSectionAvailability(
    List<CourseSection> sections, {
    required DateTime fetchedAt,
  }) {
    final classes = <String, CourseSection>{};
    for (final section in sections) {
      if (section.roundKey != roundKey || section.courseId != courseId) {
        throw const SelectionException(
          SelectionFailureCode.protocol,
          '教学班与课程或轮次不一致，无法汇总余量',
        );
      }
      if (sectionId != null && section.sectionId != sectionId) continue;
      final previous = classes[section.sectionId];
      if (previous != null &&
          (previous.capacity != section.capacity ||
              previous.selected != section.selected)) {
        throw const SelectionException(
          SelectionFailureCode.protocol,
          '学校重复返回的教学班人数不一致，请重新查询',
        );
      }
      classes[section.sectionId] = section;
    }
    int? totalCapacity = 0;
    int? totalSelected = 0;
    int? totalAvailable = 0;
    for (final section in classes.values) {
      totalCapacity = totalCapacity == null || section.capacity == null
          ? null
          : totalCapacity + section.capacity!;
      totalSelected = totalSelected == null || section.selected == null
          ? null
          : totalSelected + section.selected!;
      final available = section.available;
      totalAvailable = totalAvailable == null || available == null
          ? null
          : totalAvailable + (available > 0 ? available : 0);
    }
    return withAvailability(
      capacity: totalCapacity,
      selected: totalSelected,
      sectionCount: classes.length,
      sectionAvailability: totalAvailable,
      fetchedAt: fetchedAt,
    );
  }

  CourseOffering withAvailability({
    required int? capacity,
    required int? selected,
    required DateTime fetchedAt,
    int? sectionCount,
    int? sectionAvailability,
  }) => CourseOffering(
    roundKey: roundKey,
    courseId: courseId,
    name: name,
    sectionId: sectionId,
    teacher: teacher,
    time: time,
    location: location,
    credit: credit,
    capacity: capacity,
    selected: selected,
    sectionCount: sectionCount,
    sectionAvailability: sectionAvailability,
    availabilityFetchedAt: fetchedAt,
    isSelected: isSelected,
    form: form,
    contextToken: contextToken,
  );
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

  CourseSchedule get schedule => CourseSchedule.fromText(time, location);
}

typedef CourseMeeting = ({String? time, String? location});

final class CourseSchedule {
  CourseSchedule._(List<CourseMeeting> meetings, this.hasAmbiguousPairing)
    : meetings = List.unmodifiable(meetings);

  factory CourseSchedule.fromText(String? time, String? location) {
    final times = _scheduleLines(time);
    final locations = _scheduleLines(location);
    if (times.isNotEmpty &&
        locations.isNotEmpty &&
        times.length != locations.length) {
      // Different lengths do not establish which location belongs to a time.
      return CourseSchedule._([
        for (final time in times) (time: time, location: null),
        for (final location in locations) (time: null, location: location),
      ], true);
    }
    final count = times.length > locations.length
        ? times.length
        : locations.length;
    final meetings = [
      for (var index = 0; index < count; index++)
        (
          time: index < times.length ? times[index] : null,
          location: index < locations.length ? locations[index] : null,
        ),
    ];
    return CourseSchedule._(
      meetings
          .where((part) => part.time != null || part.location != null)
          .toList(),
      false,
    );
  }

  final List<CourseMeeting> meetings;
  final bool hasAmbiguousPairing;
}

List<String?> _scheduleLines(String? value) {
  if (value == null || value.trim().isEmpty) return const [];
  final lines = value.split(RegExp(r'\r\n?|\n')).map((line) {
    final text = line.trim();
    return text.isEmpty ? null : text;
  }).toList();
  // A terminal line break ends the field. Keep leading/interior empty slots
  // because removing those shifts the subsequent time/place pairs.
  while (lines.isNotEmpty && lines.last == null) {
    lines.removeLast();
  }
  return lines;
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

  CourseSchedule get schedule => CourseSchedule.fromText(time, location);

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
