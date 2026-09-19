import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../auth/login_html_parser.dart';
import '../auth/login_models.dart';
import '../schedule/academic_term.dart';
import 'selection_models.dart';

final class SelectionIndex {
  SelectionIndex({
    required List<SelectionRound> rounds,
    required Map<String, String> form,
  }) : rounds = List.unmodifiable(rounds),
       form = Map.unmodifiable(form);

  final List<SelectionRound> rounds;
  final Map<String, String> form;
}

/// New-Zhengfang forms and lists, following zhengfang-apk 1ff0815.
final class ZhengfangSelectionParser {
  const ZhengfangSelectionParser();

  SelectionIndex parseIndex(String source, {String? expectedStudentId}) {
    final document = _document(source);
    final form = _pageFields(document);
    _checkIdentity([form], expectedStudentId);
    final rounds = <String, SelectionRound>{};
    void collect(String script, String label) {
      for (final match in _queryCourse.allMatches(script)) {
        final values = [for (var i = 1; i <= 4; i++) match.group(i)!.trim()];
        if (values[0].isEmpty || values[1].isEmpty) continue;
        final round = _round(
          form,
          category: values[0],
          controlId: values[1],
          gradeId: values[2],
          majorId: values[3],
          categoryLabel: label,
        );
        rounds.putIfAbsent(round.key, () => round);
      }
    }

    for (final element in document.querySelectorAll('[onclick]')) {
      collect(element.attributes['onclick']!, _display(element.text));
    }
    collect(source, '');
    if (rounds.isEmpty) {
      final id = _first(form, const [
        'firstXkkzId',
        'firstXkkzXh',
        'xkkz_id',
        'xkkz_xh',
      ]);
      final category = _first(form, const ['firstKklxdm', 'kklxdm']);
      if (id != null && category != null) {
        final round = _round(
          form,
          category: category,
          controlId: id,
          gradeId: form['njdm_id'] ?? '',
          majorId: form['zyh_id'] ?? '',
          categoryLabel: _first(form, const ['kklxmc', 'xkkzmc']) ?? '',
        );
        rounds[round.key] = round;
      } else if (!_closedMessage.hasMatch(_visibleText(document))) {
        _protocol('学校选课页面没有提供可识别的轮次和课程类型，请在教务页面核对');
      }
    }
    return SelectionIndex(rounds: rounds.values.toList(), form: form);
  }

  SelectionRound parseDisplay(
    String source,
    SelectionRound round, {
    String? expectedStudentId,
  }) {
    final document = _document(source);
    final form = _merge(round.form, _pageFields(document));
    _checkIdentity([form], expectedStudentId);
    if (_closedMessage.hasMatch(_visibleText(document)) &&
        _first(form, const ['xkxnm', 'xkxqm', 'rwlx', 'xklc']) == null) {
      throw const SelectionException(
        SelectionFailureCode.roundClosed,
        '学校当前未开放此选课轮次，请在教务页面核对开放时间',
      );
    }
    return _round(
      form,
      category: round.categoryCode,
      controlId: round.controlId,
      gradeId: round.gradeId,
      majorId: round.majorId,
      categoryLabel: round.categoryLabel,
    );
  }

  List<CourseOffering> parseCourses(
    String source, {
    required SelectionContext context,
    required SelectionRound round,
    String? expectedStudentId,
  }) => List.unmodifiable(
    _rows(source, expectedStudentId: expectedStudentId).map((row) {
      final form = _scalarFields(row);
      return CourseOffering(
        roundKey: round.key,
        courseId: _required(row, const ['kch_id', 'kch'], '课程编号'),
        name: _required(row, const ['kcmc', 'kc_mc'], '课程名称'),
        sectionId: _text(row, const ['jxb_id']),
        teacher: _teacher(row),
        time: _text(row, const ['sksj', 'sksjmc'], preserveLines: true),
        location: _text(row, const ['jxdd', 'skdd'], preserveLines: true),
        credit: _text(row, const ['xf', 'jxbxf']),
        capacity: _number(row, const ['jxbrl', 'jxbrs', 'capacity']),
        selected: _number(row, const ['yxzrs', 'yxrs', 'selected']),
        isSelected: _selected(row),
        form: form,
        contextToken: context.token,
      );
    }),
  );

  List<CourseSection> parseSections(
    String source, {
    required SelectionContext context,
    required CourseOffering course,
    String? expectedStudentId,
  }) => List.unmodifiable(
    _rows(
      source,
      expectedStudentId: expectedStudentId,
      keys: const ['tmpList', 'data', 'courses', 'jxbList'],
    ).map((row) {
      final courseId = _text(row, const ['kch_id', 'kch']);
      if (courseId != null && courseId != course.courseId) {
        _protocol('学校返回的教学班不属于所选课程，请刷新课程列表');
      }
      final sectionId = _required(row, const ['jxb_id'], '教学班编号');
      return CourseSection(
        roundKey: course.roundKey,
        courseId: course.courseId,
        sectionId: sectionId,
        name: _text(row, const ['jxbmc']) ?? course.name,
        teacher: _teacher(row) ?? course.teacher,
        time: _text(row, const ['sksj', 'sksjmc'], preserveLines: true),
        location: _text(row, const ['jxdd', 'skdd'], preserveLines: true),
        capacity: _number(row, const ['jxbrl', 'jxbrs', 'capacity']),
        selected: _number(row, const ['yxzrs', 'yxrs', 'selected']),
        isSelected: _selected(row),
        submitId: _text(row, const ['do_jxb_id']) ?? sectionId,
        form: _scalarFields(row),
        contextToken: context.token,
      );
    }),
  );

  List<SelectedCourse> parseSelected(
    String source, {
    AcademicTerm? term,
    String? expectedStudentId,
  }) => List.unmodifiable(
    _rows(source, expectedStudentId: expectedStudentId).map((row) {
      final recordTerm = _term(_scalarFields(row));
      if (term != null && recordTerm != null && term != recordTerm) {
        _protocol('学校返回的已选记录属于其他学期，请重新读取选课页面');
      }
      return SelectedCourse(
        courseId: _required(row, const ['kch_id', 'kch'], '已选课程编号'),
        // Some schools omit this field. Such records cannot verify a class.
        sectionId: _text(row, const ['jxb_id']) ?? '',
        name: _required(row, const ['kcmc', 'kc_mc'], '已选课程名称'),
        term: recordTerm ?? term,
        teacher: _teacher(row),
        time: _text(row, const ['sksj', 'sksjmc'], preserveLines: true),
        location: _text(row, const ['jxdd', 'skdd'], preserveLines: true),
      );
    }),
  );

  SelectionSubmission parseSubmission(String source) {
    final Object? decoded;
    try {
      decoded = _decode(source);
    } on SelectionException {
      return const SelectionSubmission(
        SelectionSubmissionStatus.unknown,
        '学校返回的提交结果无法识别，需要核对已选课程',
      );
    }
    if (decoded == 1 || decoded == '1') {
      return const SelectionSubmission(
        SelectionSubmissionStatus.accepted,
        '学校已接受选课请求，正在核实已选记录',
      );
    }
    if (decoded is Map<String, Object?>) {
      final message = _text(decoded, const ['message', 'msg', 'msgContent']);
      _checkLoginMessage(message);
      if (_rejected(decoded)) {
        return SelectionSubmission(
          SelectionSubmissionStatus.rejected,
          message ?? '学校拒绝了此次选课请求，请在教务页面查看原因',
        );
      }
      if (const {true, 'true', 1, '1'}.contains(decoded['success']) ||
          const {true, 'true', 1, '1'}.contains(decoded['flag']) ||
          const {0, '0'}.contains(decoded['code'])) {
        return SelectionSubmission(
          SelectionSubmissionStatus.accepted,
          message ?? '学校已接受选课请求，正在核实已选记录',
        );
      }
      return SelectionSubmission(
        SelectionSubmissionStatus.unknown,
        message ?? '学校未明确返回此次选课结果，需要核对已选课程',
      );
    }
    if (decoded == 0 || decoded == '0' || decoded == false) {
      return const SelectionSubmission(
        SelectionSubmissionStatus.rejected,
        '学校拒绝了此次选课请求，请在教务页面查看原因',
      );
    }
    return const SelectionSubmission(
      SelectionSubmissionStatus.unknown,
      '学校未明确返回此次选课结果，需要核对已选课程',
    );
  }
}

final _queryCourse = RegExp(
  r'''queryCourse\s*\(\s*(?:this\s*,\s*)?['"]([^'"]*)['"]\s*,\s*['"]([^'"]*)['"]\s*,\s*['"]([^'"]*)['"]\s*,\s*['"]([^'"]*)['"]''',
);

final _closedMessage = RegExp(
  r'(?:选课|轮次).{0,18}(?:未开始|未开放|已结束|已关闭|未到|尚未开始)|'
  r'不在选课时间|不属于选课阶段|只可退课|暂无.{0,5}选课',
);
final _loginMessage = RegExp(
  r'请先登[录陆]|未登[录陆]|请重新登[录陆]|登[录陆].{0,8}(?:超时|失效|过期)|会话.{0,8}(?:失效|过期)|notlogin',
  caseSensitive: false,
);

Document _document(String source) {
  final document = html.parse(source);
  if (isLoginDocument(document) ||
      RegExp(
        r'''location(?:\.href)?\s*=\s*['"][^'"]*(?:login_slogin|cas/login)''',
        caseSensitive: false,
      ).hasMatch(source)) {
    _expired();
  }
  _checkLoginMessage(_visibleText(document));
  return document;
}

String _visibleText(Document document) {
  final copy = document.clone(true);
  for (final element in copy.querySelectorAll('script, style')) {
    element.remove();
  }
  return copy.body?.text ?? copy.text ?? '';
}

Map<String, String> _pageFields(Document document) {
  final result = <String, String>{};
  for (final element in document.querySelectorAll('input')) {
    final type = element.attributes['type']?.toLowerCase();
    if (element.attributes.containsKey('disabled') ||
        (type != null && type != 'hidden')) {
      continue;
    }
    final name = element.attributes['name'] ?? element.id;
    if (name.isNotEmpty) result[name] = element.attributes['value'] ?? '';
  }
  return result;
}

SelectionRound _round(
  Map<String, String> form, {
  required String category,
  required String controlId,
  required String gradeId,
  required String majorId,
  required String categoryLabel,
}) {
  final key = _controlKey(form);
  final term = _term(form);
  final title = categoryLabel.isEmpty ? '课程类型 $category' : categoryLabel;
  return SelectionRound(
    controlKey: key,
    controlId: controlId,
    categoryCode: category,
    categoryLabel: title,
    label: term == null ? title : '${term.label} · $title',
    term: term,
    gradeId: gradeId,
    majorId: majorId,
    form: form,
  );
}

String _controlKey(Map<String, String> form) {
  if (_first(form, const ['firstXkkzId', 'xkkz_id']) != null) return 'xkkz_id';
  if (_first(form, const ['firstXkkzXh', 'xkkz_xh']) != null ||
      form.containsKey('firstXkkzXh') ||
      form.containsKey('xkkz_xh')) {
    return 'xkkz_xh';
  }
  return 'xkkz_id';
}

AcademicTerm? _term(Map<String, String> form) {
  final year = _first(form, const ['xkxnm', 'xnm']);
  final semester = _first(form, const ['xkxqm', 'xqm']);
  if (year == null || semester == null) return null;
  final semesterLabel =
      _first(form, const ['xkxqmc', 'xqmc']) ??
      switch (semester) {
        '3' => '第一学期',
        '12' => '第二学期',
        '16' => '第三学期 / 小学期',
        _ => '学期 $semester',
      };
  final numericYear = int.tryParse(year);
  final yearLabel =
      _first(form, const ['xkxnmc', 'xnmc']) ??
      (numericYear == null ? year : '$year–${numericYear + 1} 学年');
  return AcademicTerm(
    yearCode: year,
    termCode: semester,
    label: '$yearLabel $semesterLabel',
  );
}

Map<String, String> _merge(
  Map<String, String> original,
  Map<String, String> incoming,
) => {
  ...original,
  // Empty Display placeholders must not erase populated Index fields.
  for (final entry in incoming.entries)
    if (entry.value.isNotEmpty || !original.containsKey(entry.key))
      entry.key: entry.value,
};

Object? _decode(String source) {
  final text = source.replaceFirst('\uFEFF', '').trim();
  if (text.startsWith('<')) _document(text);
  try {
    final Object? decoded = jsonDecode(text);
    if (decoded is String) _checkLoginMessage(decoded);
    return decoded;
  } on FormatException {
    _protocol('学校没有返回可识别的选课数据，请在教务页面核对');
  }
}

List<Map<String, Object?>> _rows(
  String source, {
  String? expectedStudentId,
  List<String> keys = const ['tmpList', 'courses', 'items'],
}) {
  final decoded = _decode(source);
  List<Object?>? candidates;
  final containers = <Map<String, Object?>>[];
  if (decoded is List<Object?>) {
    candidates = decoded;
  } else if (decoded is Map<String, Object?>) {
    containers.add(decoded);
    for (final key in const ['data', 'result']) {
      final value = decoded[key];
      if (value is Map<String, Object?>) containers.add(value);
    }
    for (final container in containers) {
      final message = _text(container, const ['message', 'msg', 'msgContent']);
      _checkLoginMessage(message);
      if (container['code']?.toString() == '401') _expired();
      if (_rejected(container)) {
        throw SelectionException(
          message != null && _closedMessage.hasMatch(message)
              ? SelectionFailureCode.roundClosed
              : SelectionFailureCode.schoolRejected,
          message ?? '学校拒绝了此次选课查询，请在教务页面查看原因',
        );
      }
      for (final key in [...keys, 'data', 'aaData', 'rows', 'list']) {
        final value = container[key];
        if (value is List<Object?> &&
            (candidates == null || (candidates.isEmpty && value.isNotEmpty))) {
          candidates = value;
        }
      }
    }
  }
  if (candidates == null) _protocol('学校返回的选课列表格式无法识别，请在教务页面核对');
  final rows = <Map<String, Object?>>[];
  for (final value in candidates) {
    if (value is! Map<String, Object?>) _protocol('学校选课列表包含无法识别的记录');
    rows.add(value);
  }
  _checkIdentity([...containers, ...rows], expectedStudentId);
  return rows;
}

bool _rejected(Map<String, Object?> value) {
  const falseValues = {false, 'false', 0, '0'};
  final code = value['code']?.toString();
  return falseValues.contains(value['success']) ||
      falseValues.contains(value['flag']) ||
      (code != null && !const {'', '0', '200'}.contains(code));
}

void _checkIdentity(
  List<Map<String, Object?>> containers,
  String? expectedStudentId,
) {
  final identities = <String>{};
  for (final container in containers) {
    final student = _text(container, const ['xh', 'studentId']);
    if (student != null) identities.add(student);
    final details = container['xsxx'];
    if (details is Map<String, Object?>) {
      final id = _text(details, const ['xh', 'studentId']);
      if (id != null) identities.add(id);
    }
  }
  final expected = expectedStudentId?.trim();
  if (identities.length > 1 ||
      (expected != null &&
          expected.isNotEmpty &&
          identities.any((id) => id != expected))) {
    throw const SelectionException(
      SelectionFailureCode.identityMismatch,
      '学校返回的数据不属于当前教务账号，此次操作已停止',
    );
  }
}

Map<String, String> _scalarFields(Map<String, Object?> row) => {
  for (final entry in row.entries)
    if (entry.value is String || entry.value is num || entry.value is bool)
      entry.key: entry.value.toString(),
};

String? _text(
  Map<String, Object?> row,
  List<String> keys, {
  bool preserveLines = false,
}) {
  for (final key in keys) {
    final value = row[key];
    if (value == null) continue;
    if (value is! String && value is! num && value is! bool) {
      _protocol('学校选课字段 $key 的格式无法识别');
    }
    final text = _display(value.toString(), preserveLines: preserveLines);
    if (text.trim().isNotEmpty && text.trim().toLowerCase() != 'null') {
      return text;
    }
  }
  return null;
}

String _display(String value, {bool preserveLines = false}) {
  final text = html
      .parseFragment(
        value.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n'),
      )
      .text!;
  return preserveLines
      ? text.split(RegExp(r'\r\n?|\n')).map((line) => line.trim()).join('\n')
      : text.trim();
}

String _required(Map<String, Object?> row, List<String> keys, String label) =>
    _text(row, keys) ??
    (throw SelectionException(
      SelectionFailureCode.protocol,
      '学校返回的一条选课记录缺少$label，请刷新后重试',
    ));

String? _first(Map<String, String> form, List<String> keys) {
  for (final key in keys) {
    final value = form[key]?.trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

String? _teacher(Map<String, Object?> row) {
  final name = _text(row, const ['jsxm', 'jsmc', 'skls', 'xm']);
  if (name != null) return name;
  final info = _text(row, const ['jsxx']);
  if (info == null) return null;
  final parts = info.split('/');
  return parts.length > 1 && parts[1].trim().isNotEmpty
      ? parts[1].trim()
      : info;
}

int? _number(Map<String, Object?> row, List<String> keys) {
  final text = _text(row, keys);
  if (text == null || text == '--' || text == '-') return null;
  final value = num.tryParse(text);
  if (value == null ||
      !value.isFinite ||
      value < 0 ||
      value != value.truncate()) {
    _protocol('学校返回的选课人数格式无法识别');
  }
  return value.toInt();
}

bool? _selected(Map<String, Object?> row) {
  final value = _text(row, const ['sfxkbj', 'sfxz', 'isSelected']);
  return switch (value?.toLowerCase()) {
    '1' || 'true' => true,
    '0' || 'false' => false,
    _ => null,
  };
}

void _checkLoginMessage(String? message) {
  if (message != null && _loginMessage.hasMatch(message)) _expired();
}

Never _expired() =>
    throw const LoginFailure(LoginFailureCode.expired, '教务登录已失效，请重新登录后读取选课数据');

Never _protocol(String message) =>
    throw SelectionException(SelectionFailureCode.protocol, message);
