import 'grade_record.dart';
import 'grade_term_group.dart';

/// A complete successful query, scoped to a school and account by its store.
final class GradeSnapshot {
  GradeSnapshot({
    required List<GradeRecord> records,
    required this.fetchedAt,
    required this.sourceLabel,
  }) : records = List.unmodifiable(records) {
    if (records.map((record) => record.id).toSet().length != records.length) {
      throw ArgumentError('Grade record IDs must distinguish every attempt.');
    }
    if (sourceLabel.trim().isEmpty) {
      throw ArgumentError('A grade snapshot needs its school source.');
    }
  }

  final List<GradeRecord> records;
  final DateTime fetchedAt;
  final String sourceLabel;

  List<GradeTermGroup> get terms {
    final groups = <String, GradeTermGroup>{
      for (final group in records.map((record) => record.termGroup).nonNulls)
        group.key: group,
    };
    return List.unmodifiable(
      groups.values.toList()..sort((a, b) {
        final year = b.yearCode.compareTo(a.yearCode);
        if (year != 0) return year;
        final aCode = int.tryParse(a.termCode);
        final bCode = int.tryParse(b.termCode);
        return aCode != null && bCode != null
            ? bCode.compareTo(aCode)
            : b.termCode.compareTo(a.termCode);
      }),
    );
  }

  /// Resolves both current group keys and raw term keys saved by older versions.
  String? resolveTermKey(String key) {
    if (records.any((record) => record.termKey == key)) return key;
    for (final record in records) {
      if (record.term?.key == key) return record.termKey;
    }
    return null;
  }
}
