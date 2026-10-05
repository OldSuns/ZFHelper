import '../schedule/academic_term.dart';

/// A visible group for records that the school did not assign to a term.
const unassignedGradeTermKey = 'unassigned';

/// A grade filter identity; the original school's request codes stay on records.
final class GradeTermGroup {
  factory GradeTermGroup(AcademicTerm source) {
    final year = gradeYearCode(source.yearCode)!;
    final code = source.termCode.trim();
    // Older snapshots retain xq=3 (third) and xqm=3 (first) as the same code.
    // Their parsed labels preserve which field meaning the school supplied.
    final thirdAlias =
        code == '3' && RegExp(r'第三学期|第3学期|小学期|夏季学期').hasMatch(source.label);
    final semester = thirdAlias
        ? ZhengfangSemester.third
        : gradeSemester(code, zhengfangCode: true);
    final number = int.tryParse(year);
    final yearLabel = number != null && year.length == 4
        ? '$number–${number + 1}'
        : year;
    return GradeTermGroup._(
      yearCode: year,
      termCode: semester?.code ?? code,
      label: semester == null
          ? source.label
          : '$yearLabel 学年 ${semester.label}',
    );
  }

  const GradeTermGroup._({
    required this.yearCode,
    required this.termCode,
    required this.label,
  });

  final String yearCode;
  final String termCode;
  final String label;
  // Raw AcademicTerm keys have one separator. This namespace prevents an old
  // xq=3 selection from colliding with the new first-semester group.
  String get key =>
      'grade-term|${Uri.encodeComponent(yearCode)}|${Uri.encodeComponent(termCode)}';
}

String? gradeYearCode(String? value) {
  if (value == null) return null;
  final text = value.trim();
  return RegExp(r'^(\d{4})(?:\s*[-–—/]\s*\d{4})?(?:\s*学年)?$')
          .firstMatch(text)
          ?.group(1) ??
      text;
}

ZhengfangSemester? gradeNamedSemester(String value) => switch (value.trim()) {
  '第一学期' || '第1学期' => ZhengfangSemester.first,
  '第二学期' || '第2学期' => ZhengfangSemester.second,
  '第三学期' ||
  '第3学期' ||
  '小学期' ||
  '夏季学期' ||
  '第三学期 / 小学期' => ZhengfangSemester.third,
  _ => null,
};

ZhengfangSemester? gradeSemester(String value, {bool zhengfangCode = false}) =>
    gradeNamedSemester(value) ??
    switch (value.trim()) {
      '3' when zhengfangCode => ZhengfangSemester.first,
      '1' => ZhengfangSemester.first,
      '2' || '12' => ZhengfangSemester.second,
      '3' || '16' => ZhengfangSemester.third,
      _ => null,
    };
