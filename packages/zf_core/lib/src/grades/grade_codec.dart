import 'dart:convert';

import '../schedule/academic_term.dart';
import 'grade_record.dart';
import 'grade_snapshot.dart';

/// Versioned persistence that keeps the school's displayed grade values.
abstract final class GradeSnapshotCodec {
  static const _version = 1;

  static String encode(GradeSnapshot snapshot) => jsonEncode({
    'version': _version,
    'kind': 'gradeSnapshot',
    'records': snapshot.records.map(_writeRecord).toList(),
    'fetchedAt': snapshot.fetchedAt.toUtc().toIso8601String(),
    'sourceLabel': snapshot.sourceLabel,
  });

  static GradeSnapshot decode(String source) {
    try {
      final data = _map(jsonDecode(source));
      if (data['version'] != _version || data['kind'] != 'gradeSnapshot') {
        throw const FormatException('Unsupported saved grade format.');
      }
      final records = data['records'];
      if (records is! List<Object?>) _invalid('records');
      final stamp = _string(data, 'fetchedAt');
      final fetchedAt = DateTime.tryParse(stamp);
      if (fetchedAt == null || fetchedAt.toUtc().toIso8601String() != stamp) {
        _invalid('fetchedAt');
      }
      return GradeSnapshot(
        records: records.map(_readRecord).toList(),
        fetchedAt: fetchedAt,
        sourceLabel: _string(data, 'sourceLabel'),
      );
    } on FormatException catch (error) {
      // Decoder errors can include the JSON source; keep cached data private.
      if (error.source != null) {
        throw const FormatException('Invalid saved grade JSON.');
      }
      rethrow;
    } on ArgumentError {
      throw const FormatException('Saved grades violate their model rules.');
    }
  }

  static Map<String, Object?> _writeRecord(GradeRecord record) => {
    'id': record.id,
    'name': record.name,
    'term': record.term == null
        ? null
        : {
            'yearCode': record.term!.yearCode,
            'termCode': record.term!.termCode,
            'label': record.term!.label,
          },
    'score': record.score,
    'credits': record.credits,
    'gradePoint': record.gradePoint,
    'courseCode': record.courseCode,
    'teachingClassId': record.teachingClassId,
    'courseNature': record.courseNature,
    'courseCategory': record.courseCategory,
    'examNature': record.examNature,
    'assessmentMethod': record.assessmentMethod,
    'gradeStatus': record.gradeStatus,
    'retake': record.retake,
    'college': record.college,
    'teacher': record.teacher,
    'passed': record.passed,
    'details': record.details,
  };

  static GradeRecord _readRecord(Object? source) {
    final data = _map(source);
    final term = data['term'] == null ? null : _map(data['term']);
    final details = _map(data['details']);
    final passed = data['passed'];
    if (passed != null && passed is! bool) _invalid('passed');
    return GradeRecord(
      id: _string(data, 'id'),
      name: _string(data, 'name'),
      term: term == null
          ? null
          : AcademicTerm(
              yearCode: _string(term, 'yearCode'),
              termCode: _string(term, 'termCode'),
              label: _string(term, 'label'),
            ),
      score: _optionalString(data, 'score'),
      credits: _optionalString(data, 'credits'),
      gradePoint: _optionalString(data, 'gradePoint'),
      courseCode: _optionalString(data, 'courseCode'),
      teachingClassId: _optionalString(data, 'teachingClassId'),
      courseNature: _optionalString(data, 'courseNature'),
      courseCategory: _optionalString(data, 'courseCategory'),
      examNature: _optionalString(data, 'examNature'),
      assessmentMethod: _optionalString(data, 'assessmentMethod'),
      gradeStatus: _optionalString(data, 'gradeStatus'),
      retake: _optionalString(data, 'retake'),
      college: _optionalString(data, 'college'),
      teacher: _optionalString(data, 'teacher'),
      passed: passed as bool?,
      details: {
        for (final key in details.keys)
          key: _string(details, key, allowEmpty: true),
      },
    );
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('Invalid saved grade structure.');
    }
    return value;
  }

  static String _string(
    Map<String, Object?> data,
    String key, {
    bool allowEmpty = false,
  }) {
    final value = data[key];
    if (value is! String || (!allowEmpty && value.trim().isEmpty)) {
      _invalid(key);
    }
    return value;
  }

  static String? _optionalString(Map<String, Object?> data, String key) {
    final value = data[key];
    if (value != null && value is! String) _invalid(key);
    return value as String?;
  }

  static Never _invalid(String key) =>
      throw FormatException('Invalid saved grade field: $key.');
}
