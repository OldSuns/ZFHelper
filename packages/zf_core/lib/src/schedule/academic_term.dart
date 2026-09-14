/// A school-defined term whose request codes retain their original meaning.
final class AcademicTerm {
  AcademicTerm({
    required this.yearCode,
    required this.termCode,
    required this.label,
  }) {
    if (yearCode.trim().isEmpty ||
        termCode.trim().isEmpty ||
        label.trim().isEmpty) {
      throw ArgumentError('Academic term codes and label must not be empty.');
    }
  }

  factory AcademicTerm.zhengfang({
    required String startYear,
    required ZhengfangSemester semester,
  }) {
    final text = startYear.trim();
    final year = int.tryParse(text);
    if (!RegExp(r'^[1-9]\d{3}$').hasMatch(text) ||
        year == null ||
        year == 9999) {
      throw const FormatException('请填写学年开始的四位年份');
    }
    return AcademicTerm(
      yearCode: text,
      termCode: semester.code,
      label: '$year–${year + 1} 学年 ${semester.label}',
    );
  }

  final String yearCode;
  final String termCode;
  final String label;

  /// A stable key independent of changes to the school's display label.
  String get key =>
      '${Uri.encodeComponent(yearCode)}|${Uri.encodeComponent(termCode)}';

  @override
  bool operator ==(Object other) =>
      other is AcademicTerm &&
      yearCode == other.yearCode &&
      termCode == other.termCode;

  @override
  int get hashCode => Object.hash(yearCode, termCode);
}

/// Standard request codes used by the reference's new-Zhengfang reader.
enum ZhengfangSemester {
  first('3', '第一学期'),
  second('12', '第二学期'),
  third('16', '第三学期 / 小学期');

  const ZhengfangSemester(this.code, this.label);
  final String code;
  final String label;
}

/// An option supplied by a school year or term selector.
final class TermOption {
  const TermOption({required this.code, required this.label});

  final String code;
  final String label;
}

/// Available selectors and explicitly known year/term combinations.
///
/// [selectedTerm] is the school's page selection, not proof of today's term.
/// Independent [yearOptions] and [termOptions] do not establish every possible
/// year/term combination as a real academic term.
final class TermCatalog {
  TermCatalog({
    List<AcademicTerm> terms = const [],
    this.selectedTerm,
    List<TermOption> yearOptions = const [],
    List<TermOption> termOptions = const [],
  }) : terms = List.unmodifiable(terms),
       yearOptions = List.unmodifiable(yearOptions),
       termOptions = List.unmodifiable(termOptions);

  final List<AcademicTerm> terms;
  final AcademicTerm? selectedTerm;
  final List<TermOption> yearOptions;
  final List<TermOption> termOptions;
}
