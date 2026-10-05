import 'dart:convert';

import 'package:html/parser.dart' as html;

import '../auth/login_html_parser.dart';
import '../auth/login_models.dart';
import '../schedule/academic_term.dart';
import 'grade_parse_exception.dart';
import 'grade_record.dart';
import 'grade_term_group.dart';

/// One verified page; pagination metadata is separate from grade values.
final class GradeQueryPage {
  GradeQueryPage({
    required List<Map<String, Object?>> rows,
    this.totalRecords,
    this.studentId,
  }) : rows = List.unmodifiable(rows.map(Map<String, Object?>.unmodifiable));

  final List<Map<String, Object?>> rows;
  final int? totalRecords;
  final String? studentId;

  String get fingerprint => jsonEncode(_canonical(rows));
}

/// Parses the new-Zhengfang grade query used by zhengfang-apk v1.0.76.
final class ZhengfangGradeParser {
  const ZhengfangGradeParser();

  GradeQueryPage parsePage(String source, {String? expectedStudentId}) {
    final decoded = _decode(source);
    final scopes = <_GradeRow>[];
    List<Object?>? rawRows;
    if (decoded is List<Object?>) {
      rawRows = decoded;
    } else {
      final root = _GradeRow(decoded);
      scopes.add(root);
      for (final key in const ['data', 'result']) {
        if (root.value(key) is Map<String, Object?>) {
          scopes.add(_GradeRow(root.value(key)));
        }
      }
      for (final scope in scopes) {
        _checkAccepted(scope);
        if (rawRows != null) continue;
        // Match the reference priority; unused list fields can be placeholders.
        for (final key in const ['items', 'data', 'aadata', 'rows', 'list']) {
          final value = scope.value(key);
          if (value is List<Object?>) {
            rawRows = value;
            break;
          }
        }
      }
    }
    if (rawRows == null) {
      throw const GradeParseException(
        GradeParseCode.invalidResponse,
        '学校没有返回可识别的成绩列表，请在教务页面核对',
      );
    }

    final rows = [
      for (var i = 0; i < rawRows.length; i++) _GradeRow(rawRows[i], index: i),
    ];
    final identities = <String>{};
    for (final scope in [...scopes, ...rows]) {
      final student = scope.text(const ['xh', 'studentid']);
      if (student != null) identities.add(student);
      final info = scope.value('xsxx');
      if (info != null) {
        final id = _GradeRow(info).text(const ['xh', 'studentid']);
        if (id != null) identities.add(id);
      }
    }
    final expected = expectedStudentId?.trim();
    if (identities.length > 1 ||
        (expected != null &&
            expected.isNotEmpty &&
            identities.any((id) => id != expected))) {
      throw const GradeParseException(
        GradeParseCode.identityMismatch,
        '学校返回的成绩不属于当前账号，未保存这次查询',
        field: 'xh',
      );
    }

    return GradeQueryPage(
      rows: rows.map((row) => row.values).toList(),
      totalRecords: _totalRecords(scopes.firstOrNull),
      studentId: identities.firstOrNull,
    );
  }

  List<GradeRecord> parseRecords(List<Map<String, Object?>> rows) {
    final occurrences = <String, int>{};
    final records = <GradeRecord>[];
    for (var index = 0; index < rows.length; index++) {
      final row = _GradeRow(rows[index], index: index);
      final name = row.text(const ['kc_mc', 'kcmc', 'coursename']);
      if (name == null) {
        row.fail(
          'kcmc',
          '一条成绩缺少课程名称，未保存不完整的查询结果',
          code: GradeParseCode.missingField,
        );
      }
      final term = _term(row);
      final courseCode = row.text(const ['kch', 'kch_id']);
      final sectionId = row.text(const ['jxb_id', 'jx0404id']);
      final examNature = row.text(const ['ksxzmc', 'ksxz']);
      final retake = row.text(const [
        'sfcxmc',
        'cxbj',
        'sfcx',
      ], allowBoolean: true);
      final identity = [
        term?.yearCode,
        term?.termCode,
        courseCode,
        sectionId,
        name,
        examNature,
        retake,
      ].map((part) => '${part?.length ?? 0}:${part ?? ''}').join();
      final occurrence = occurrences.update(
        identity,
        (n) => n + 1,
        ifAbsent: () => 0,
      );
      final details = <String, String>{};
      for (final field in _detailFields.entries) {
        final value = row.text(field.value, allowBoolean: true);
        if (value != null) details[field.key] = value;
      }
      if (term == null) {
        final year = row.text(const ['xnm', 'xn', 'xnmc']);
        final semester = row.text(const [
          'xqm',
          'xq',
          'xqmc',
          'xnxqid',
          'xnxq01id',
          'xnxq',
        ]);
        if (year != null) details['学年'] = year;
        if (semester != null) details['学期'] = semester;
      }
      records.add(
        GradeRecord(
          id: 'grade:$identity#$occurrence',
          name: name,
          term: term,
          score: row.text(const ['zcjstr', 'cj', 'zcj']),
          credits: row.text(const ['xf']),
          gradePoint: row.text(const ['jd']),
          courseCode: courseCode,
          teachingClassId: sectionId,
          courseNature: row.text(const ['kcxzmc', 'kcxz', 'kcsx']),
          courseCategory: row.text(const ['kclbmc', 'kclb']),
          examNature: examNature,
          assessmentMethod: row.text(const [
            'ksfsmc',
            'ksfs',
            'khfsmc',
            'khfs',
          ]),
          gradeStatus: row.text(const ['cjbs', 'cjzt']),
          retake: retake,
          college: row.text(const ['kkbmmc', 'ksdw', 'jgmc']),
          teacher: row.text(const ['jsxm', 'jsmc']),
          passed: _passed(row),
          details: details,
        ),
      );
    }
    return List.unmodifiable(records);
  }
}

AcademicTerm? _term(_GradeRow row) {
  final rawYear = row.text(const ['xnm']);
  final yearName = row.text(const ['xnmc', 'xn']);
  final rawSemester = row.text(const ['xqm']);
  final semesterAlias = row.text(const ['xq']);
  final semesterName = row.text(const ['xqmc']);
  final combined = row.text(const ['xnxqid', 'xnxq01id', 'xnxq', 'term']);
  final match = combined == null
      ? null
      : RegExp(r'^(\d{4})[-–—/](\d{4})[-–—/]([123])$').firstMatch(combined);
  final combinedYear = match?.group(1);
  final combinedSemester = match?.group(3);
  final combinedIdentity = combinedSemester == null
      ? null
      : gradeSemester(combinedSemester);
  final year = rawYear ?? gradeYearCode(yearName) ?? combinedYear;
  final semester =
      rawSemester ?? semesterAlias ?? combinedIdentity?.code ?? semesterName;
  final years = [
    rawYear,
    yearName,
    combinedYear,
  ].nonNulls.map(gradeYearCode).nonNulls.toSet();
  // Custom school codes have no known ordinal to compare with a term label.
  final semesters = <ZhengfangSemester>{
    if (rawSemester != null) ?gradeSemester(rawSemester, zhengfangCode: true),
    if (semesterAlias != null) ?gradeSemester(semesterAlias),
    ?combinedIdentity,
    if (semesterName != null) ?gradeNamedSemester(semesterName),
  };
  if (years.length > 1 || semesters.length > 1) {
    row.fail('xnm/xqm', '同一条成绩的学年或学期字段相互矛盾');
  }
  if (year == null || semester == null) return null;
  final startYear = int.tryParse(year);
  final yearLabel =
      yearName ??
      (startYear != null && year.length == 4
          ? '$startYear–${startYear + 1}'
          : year);
  final semesterLabel =
      semesterName ??
      gradeSemester(
        semester,
        zhengfangCode: rawSemester != null || combinedSemester != null,
      )?.label ??
      '学期 $semester';
  return AcademicTerm(
    yearCode: year,
    termCode: semester,
    label:
        '${yearLabel.endsWith('学年') ? yearLabel : '$yearLabel 学年'} $semesterLabel',
  );
}

bool? _passed(_GradeRow row) =>
    switch (row.text(const ['sfjg'], allowBoolean: true)?.toLowerCase()) {
      '1' || 'true' || '是' || '及格' || '合格' || '通过' => true,
      '0' || 'false' || '否' || '不及格' || '不合格' || '未通过' => false,
      _ => null,
    };

Object? _decode(String source) {
  final text = source.replaceFirst(RegExp(r'^\uFEFF'), '').trim();
  if (text.startsWith('<')) {
    if (isLoginDocument(html.parse(text)) ||
        RegExp(
          r'''location(?:\.href)?\s*=\s*['"][^'"]*(?:login_slogin|cas/login)''',
          caseSensitive: false,
        ).hasMatch(text)) {
      _expired();
    }
  }
  try {
    final value = jsonDecode(text);
    if (value is String && _loginMessage.hasMatch(value)) _expired();
    return value;
  } on FormatException {
    throw const GradeParseException(
      GradeParseCode.invalidResponse,
      '学校没有返回有效的成绩 JSON 数据，请在教务页面核对',
    );
  }
}

final _loginMessage = RegExp(
  r'请先登[录陆]|未登[录陆]|请重新登[录陆]|登[录陆].{0,8}(?:超时|失效|过期)|会话.{0,8}(?:失效|过期)|notlogin',
  caseSensitive: false,
);

void _checkAccepted(_GradeRow row) {
  final message = row.text(const ['message', 'msg', 'msgcontent']);
  if (message != null && _loginMessage.hasMatch(message)) _expired();
  const falseValues = {false, 0, '0', 'false'};
  final code = row.value('code')?.toString();
  if (code == '401') _expired();
  final error = row.value('error');
  final rejected =
      falseValues.contains(row.value('success')) ||
      falseValues.contains(row.value('flag')) ||
      (code != null && !const {'', '0', '200'}.contains(code)) ||
      const {
        'error',
        'failed',
        'failure',
        'forbidden',
        'false',
      }.contains(row.value('status')?.toString().toLowerCase()) ||
      error == true ||
      (error is String &&
          error.trim().isNotEmpty &&
          !const {'false', '0'}.contains(error.trim().toLowerCase())) ||
      (error is Map<String, Object?> && error.isNotEmpty);
  if (!rejected) return;
  throw GradeParseException(
    GradeParseCode.schoolRejected,
    message != null && RegExp(r'评教|教学评价').hasMatch(message)
        ? '学校要求完成教学评价后才能查询成绩，请先到教务页面处理'
        : '学校未接受本次成绩查询，请在教务页面查看原因',
  );
}

int? _totalRecords(_GradeRow? root) {
  if (root == null) return null;
  // zhengfang-apk reads the first numeric count on the response root. Other
  // pagination fields and queryModel may contain unrelated framework defaults.
  for (final key in const ['count', 'totalcount', 'totalresult', 'records']) {
    final source = root.value(key);
    final int? value = source is int
        ? source
        : source is num &&
              source.isFinite &&
              source == source.truncateToDouble()
        ? source.toInt()
        : source is String
        ? int.tryParse(source.trim())
        : null;
    if (value == null) continue;
    if (value < 0) root.fail(key, '学校返回了无效的成绩总记录数');
    return value;
  }
  return null;
}

Never _expired() =>
    throw const LoginFailure(LoginFailureCode.expired, '教务登录已失效，请重新登录后更新成绩');

Object? _canonical(Object? value) {
  if (value is List<Object?>) return value.map(_canonical).toList();
  if (value is! Map<String, Object?>) return value;
  final keys = value.keys.toList()..sort();
  return {for (final key in keys) key: _canonical(value[key])};
}

final class _GradeRow {
  _GradeRow(Object? value, {this.index}) {
    if (value is! Map<String, Object?>) {
      fail('record', '学校返回的成绩记录结构无法识别', code: GradeParseCode.invalidResponse);
    }
    for (final entry in value.entries) {
      final key = entry.key.toLowerCase();
      if (values.containsKey(key) && values[key] != entry.value) {
        fail(key, '学校返回了重复且内容矛盾的成绩字段');
      }
      values[key] = entry.value;
    }
  }

  final int? index;
  final values = <String, Object?>{};
  Object? value(String key) => values[key];

  String? text(List<String> keys, {bool allowBoolean = false}) {
    for (final key in keys) {
      final value = values[key];
      if (value == null) continue;
      if (value is! String &&
          value is! num &&
          !(allowBoolean && value is bool)) {
        fail(key, '学校成绩字段的类型无法识别');
      }
      final fragment = html.parseFragment(value.toString());
      for (final element in fragment.querySelectorAll('script, style')) {
        element.remove();
      }
      final text = fragment.text?.trim();
      if (text != null && text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }
    return null;
  }

  Never fail(
    String field,
    String message, {
    GradeParseCode code = GradeParseCode.invalidValue,
  }) => throw GradeParseException(
    code,
    message,
    field: field,
    recordIndex: index,
  );
}

const _detailFields = <String, List<String>>{
  '平时成绩': ['pscj'],
  '期中成绩': ['qzcj'],
  '期末成绩': ['qmcj'],
  '实验成绩': ['sycj'],
  '实践成绩': ['sjcj'],
  '补考成绩': ['bkcj'],
  '重修成绩': ['cxcj'],
  '学分绩点': ['xfjd'],
  '学时': ['zxs', 'xs'],
  '教学班': ['jxbmc'],
  '备注': ['bz', 'cjbz'],
  '是否通过': ['sfjg'],
  '成绩分项': ['xmblmc'],
  '分项成绩': ['xmcj'],
  '分项占比（%）': ['xmbl'],
};
