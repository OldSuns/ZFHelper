import 'dart:convert';

import '../auth/authenticated_read_client.dart';
import '../auth/login_models.dart';
import '../auth/school_connection.dart';
import 'selection_models.dart';
import 'zhengfang_selection_parser.dart';

/// Shares the authentication owner's transport for new-Zhengfang selection.
final class ZhengfangSelectionGateway {
  ZhengfangSelectionGateway({
    required SchoolConnection profile,
    required this._client,
    required this._clock,
    this._studentId,
    String? functionCode,
  }) : _profile = profile,
       _functionCode =
           functionCode ??
           profile.selectionPageUri.queryParameters['gnmkdm'] ??
           'N253512';

  final SchoolConnection _profile;
  final AuthenticatedReadClient _client;
  final DateTime Function() _clock;
  final String? _studentId;
  final String _functionCode;
  static const _parser = ZhengfangSelectionParser();
  static const _pageSize = 10;

  Future<SelectionContext> readContext() async {
    final response = await _read(AuthHttpRequest.get(_pageUri));
    final index = _parser.parseIndex(
      response.text,
      expectedStudentId: _studentId,
    );
    final rounds = <SelectionRound>[];
    for (final round in index.rounds) {
      final fields = {
        round.controlKey: round.controlId,
        'kklxdm': round.categoryCode,
        'xszxzt': '1',
        'njdm_id': round.gradeId,
        'zyh_id': round.majorId,
        'kspage': '0',
        'jspage': '0',
        ..._pick(index.form, _tokenFields),
      };
      final display = await _read(
        _form('zzxkyzb_cxZzxkYzbDisplay.html', fields),
      );
      rounds.add(
        _parser.parseDisplay(
          display.text,
          round,
          expectedStudentId: _studentId,
        ),
      );
    }
    return SelectionContext(
      rounds: rounds,
      fetchedAt: _clock(),
      pageUri: _pageUri,
      form: index.form,
      studentId: _studentId,
    );
  }

  Future<List<CourseOffering>> readCourses(
    SelectionContext context,
    SelectionRound round, {
    String keyword = '',
  }) async {
    final current = _round(context, round.key);
    final result = <CourseOffering>[];
    final pages = <String>{};
    for (var start = 1; ; start += _pageSize) {
      final fields = {
        ..._queryForm(context, current),
        'kspage': '$start',
        'jspage': '${start + _pageSize - 1}',
        'kch_id': '',
        'jxbzb': '',
        if (keyword.trim().isNotEmpty) 'searchInput': keyword.trim(),
      };
      final response = await _read(
        _form('zzxkyzb_cxZzxkYzbPartDisplay.html', fields),
      );
      final courses = _parser.parseCourses(
        response.text,
        context: context,
        round: current,
        expectedStudentId: _studentId,
      );
      if (courses.isEmpty) break;
      final ids = courses.map((course) => course.key).toList()..sort();
      if (!pages.add(jsonEncode(ids))) {
        throw const SelectionException(
          SelectionFailureCode.incompleteResponse,
          '学校重复返回了同一页课程，本次查询未能完整读取，请重新查询',
        );
      }
      result.addAll(courses);
    }
    return List.unmodifiable(result);
  }

  Future<List<CourseSection>> readSections(
    SelectionContext context,
    CourseOffering course,
  ) async {
    final round = _courseRound(context, course);
    final response = await _read(
      _form('zzxkyzbjk_cxJxbWithKchZzxkYzb.html', {
        ..._queryForm(context, round),
        ..._pick(course.form, _queryFields),
        round.controlKey: round.controlId,
        'kklxdm': round.categoryCode,
        'kch_id': course.courseId,
      }),
    );
    return _parser.parseSections(
      response.text,
      context: context,
      course: course,
      expectedStudentId: _studentId,
    );
  }

  Future<List<SelectedCourse>> readSelected(
    SelectionContext context, {
    SelectionRound? round,
  }) async {
    _checkContext(context);
    final scopes = round == null
        ? context.rounds
        : [_round(context, round.key)];
    final queries = <String, SelectionRound?>{};
    for (final scope in scopes) {
      queries.putIfAbsent(scope.term?.key ?? '', () => scope);
    }
    if (queries.isEmpty) queries[''] = null;
    final records = <String, SelectedCourse>{};
    for (final scope in queries.values) {
      final form = {...context.form, if (scope != null) ...scope.form};
      final response = await _read(
        _form('zzxkyzb_cxZzxkYzbChoosedDisplay.html', {
          ..._pick(form, _selectedFields),
          ..._pick(form, _tokenFields),
        }),
      );
      for (final record in _parser.parseSelected(
        response.text,
        term: scope?.term,
        expectedStudentId: _studentId,
      )) {
        records.putIfAbsent(record.key, () => record);
      }
    }
    return List.unmodifiable(records.values);
  }

  /// Sends exactly once. The caller must provide a non-replaying mutation client
  /// from the account owner and then verify the target with [readSelected].
  Future<SelectionSubmission> submit(
    SelectionContext context,
    CourseOffering course,
    CourseSection section,
  ) async {
    final round = _courseRound(context, course);
    if (!identical(section.contextToken, context.token) ||
        section.courseId != course.courseId ||
        section.roundKey != round.key ||
        section.sectionId.isEmpty ||
        section.submitId == null ||
        section.submitId!.isEmpty) {
      throw const SelectionException(
        SelectionFailureCode.protocol,
        '请重新读取目标教学班后选课，已保存的课程资料不能直接用于提交',
      );
    }
    final source = {
      ..._queryForm(context, round),
      ...course.form,
      ...section.form,
    };
    final year = source['xkxnm'];
    final semester = source['xkxqm'];
    if (year == null || year.isEmpty || semester == null || semester.isEmpty) {
      throw const SelectionException(
        SelectionFailureCode.protocol,
        '学校未提供目标教学班的学年学期，无法准确提交，请刷新选课页面',
      );
    }
    if (round.term case final term?) {
      if (year != term.yearCode || semester != term.termCode) {
        throw const SelectionException(
          SelectionFailureCode.protocol,
          '学校目标教学班的学期已变化，请重新确认课程',
        );
      }
    }
    final fields = {
      ..._pick(source, _submitFields),
      ..._pick(source, _tokenFields),
      'jxb_ids': section.submitId!,
      'kch_id': course.courseId,
      'kcmc': '(${course.courseId})${course.name}',
      round.controlKey: round.controlId,
      'kklxdm': round.categoryCode,
      'qz': '0',
    };
    try {
      final response = await _client.sendRead(
        _form('zzxkyzbjk_xkBcZyZzxkYzb.html', fields),
      );
      if ((response.statusCode >= 300 && response.statusCode < 400) ||
          response.statusCode == 429 ||
          response.statusCode >= 500) {
        return SelectionSubmission(
          SelectionSubmissionStatus.unknown,
          '学校未能明确返回选课结果（HTTP ${response.statusCode}），需要核实已选记录',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return SelectionSubmission(
          SelectionSubmissionStatus.rejected,
          '学校未接受选课请求（HTTP ${response.statusCode}）',
        );
      }
      return _parser.parseSubmission(response.text);
    } on LoginFailure catch (error) {
      if (error.code != LoginFailureCode.network &&
          error.code != LoginFailureCode.cancelled) {
        rethrow;
      }
      return const SelectionSubmission(
        SelectionSubmissionStatus.unknown,
        '选课请求的返回中断，需要核实学校已选记录',
      );
    } on FormatException {
      return const SelectionSubmission(
        SelectionSubmissionStatus.unknown,
        '学校提交响应的文字编码无法识别，需要核实学校已选记录',
      );
    }
  }

  Uri get _pageUri => _profile.selectionPageUri.replace(
    queryParameters: {
      ..._profile.selectionPageUri.queryParameters,
      'gnmkdm': _functionCode,
      'layout':
          _profile.selectionPageUri.queryParameters['layout'] ?? 'default',
    },
  );

  AuthHttpRequest _form(String file, Map<String, String> fields) =>
      AuthHttpRequest.form(
        _pageUri
            .resolve(file)
            .replace(queryParameters: {'gnmkdm': _functionCode}),
        fields: fields.entries.toList(),
        headers: {
          'Accept': 'application/json, text/javascript, */*; q=0.01',
          'X-Requested-With': 'XMLHttpRequest',
          'Origin': _profile.baseUri.origin,
          'Referer': _pageUri.toString(),
        },
      );

  Map<String, String> _queryForm(
    SelectionContext context,
    SelectionRound round,
  ) {
    final source = {...context.form, ...round.form};
    final values = {
      ..._pick(source, _queryFields),
      ..._pick(source, _tokenFields),
      round.controlKey: round.controlId,
      'kklxdm': round.categoryCode,
      'njdm_id': round.gradeId,
      'zyh_id': round.majorId,
    };
    // V9 can require xkkz_xh alongside xkkz_id; retain the Index value when
    // Display contains only an empty placeholder (reference CourseNameKit).
    final sequenceValue = _value(source, 'xkkz_xh');
    final sequence = sequenceValue == null || sequenceValue.isEmpty
        ? source['firstXkkzXh']
        : sequenceValue;
    if (round.controlKey != 'xkkz_xh' && sequence != null) {
      values['xkkz_xh'] = sequence;
    }
    return values;
  }

  SelectionRound _round(SelectionContext context, String key) {
    _checkContext(context);
    return context.rounds.where((round) => round.key == key).firstOrNull ??
        (throw const SelectionException(
          SelectionFailureCode.roundClosed,
          '目标选课轮次已不在学校当前页面中，请重新选择轮次',
        ));
  }

  SelectionRound _courseRound(SelectionContext context, CourseOffering course) {
    final round = _round(context, course.roundKey);
    if (!identical(course.contextToken, context.token)) {
      throw const SelectionException(
        SelectionFailureCode.protocol,
        '请刷新课程后读取教学班详情，当前课程资料属于较早的查询',
      );
    }
    return round;
  }

  void _checkContext(SelectionContext context) {
    if (context.pageUri != _pageUri || context.studentId != _studentId) {
      throw const SelectionException(
        SelectionFailureCode.identityMismatch,
        '选课页面不属于当前学校及账号，请重新查询',
      );
    }
  }

  Future<AuthHttpResponse> _read(AuthHttpRequest request) async {
    final response = await _client.sendRead(request);
    if (response.statusCode == 401) {
      throw const LoginFailure(LoginFailureCode.expired, '教务登录已失效，请重新登录');
    }
    if (response.statusCode == 429 || response.statusCode >= 500) {
      throw LoginFailure(
        LoginFailureCode.network,
        '学校暂时无法提供选课查询（HTTP ${response.statusCode}），请稍后重试',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SelectionException(
        SelectionFailureCode.schoolRejected,
        '学校未允许读取选课数据（HTTP ${response.statusCode}）',
      );
    }
    try {
      response.text;
    } on FormatException {
      throw const SelectionException(
        SelectionFailureCode.protocol,
        '学校选课响应的文字编码无法识别',
      );
    }
    return response;
  }
}

Map<String, String> _pick(Map<String, String> source, List<String> keys) => {
  for (final key in keys) key: ?_value(source, key),
};

String? _value(Map<String, String> source, String key) {
  final direct = source[key];
  if (direct != null && direct.isNotEmpty) return direct;
  for (var suffix = 1; suffix <= 5; suffix++) {
    final value = source['${key}_$suffix'];
    if (value != null && value.isNotEmpty) return value;
  }
  return direct;
}

const _tokenFields = ['csrftoken', 'csrfToken', '_csrf', 'validate'];
const _queryFields = [
  'rwlx',
  'xklc',
  'xkly',
  'bklx_id',
  'sfkkjyxdxnxq',
  'kzkcgs',
  'xqh_id',
  'jg_id',
  'njdm_id_1',
  'zyh_id_1',
  'gnjkxdnj',
  'zyh_id',
  'zyfx_id',
  'njdm_id',
  'bh_id',
  'bjgkczxbbjwcx',
  'xbm',
  'xslbdm',
  'mzm',
  'xz',
  'ccdm',
  'xsbj',
  'sfkknj',
  'sfkkzy',
  'kzybkxy',
  'sfznkx',
  'zdkxms',
  'sfkxq',
  'sfkcfx',
  'kkbk',
  'kkbkdj',
  'bklbkcj',
  'sfkgbcx',
  'sfrxtgkcxd',
  'tykczgxdcs',
  'xkxnm',
  'xkxqm',
  'xkxskcgskg',
  'bbhzxjxb',
  'rlkz',
  'xkzgbj',
  'txbsfrl',
  'cdrlkz',
  'rlzlkz',
  'jxbzcxskg',
  'cxbj',
  'fxbj',
  'xkkz_xh',
];
const _submitFields = [
  'rwlx',
  'rlkz',
  'rlzlkz',
  'sxbj',
  'xxkbj',
  'cxbj',
  'njdm_id',
  'zyh_id',
  'xklc',
  'xkxnm',
  'xkxqm',
  'jcxx_id',
  'xkkz_xh',
];
const _selectedFields = [
  'jg_id',
  'zyh_id',
  'njdm_id',
  'zyfx_id',
  'bh_id',
  'xz',
  'ccdm',
  'xqh_id',
  'xkxnm',
  'xkxqm',
  'xkly',
];
