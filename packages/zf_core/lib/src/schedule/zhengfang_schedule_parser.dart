import 'dart:convert';

import 'package:html/parser.dart' as html;

import 'academic_term.dart';
import 'schedule_entry.dart';
import 'schedule_notation_parser.dart';
import 'schedule_parse_exception.dart';
import 'schedule_snapshot.dart';
import 'teaching_calendar.dart';
import 'zhengfang_term_parser.dart';

/// Reads new Zhengfang's term selectors and complete semester timetable JSON.
///
/// A malformed row rejects the import, allowing the repository to retain the
/// previous complete snapshot. This parser does not handle sessions or infer a
/// term calendar from the current month or the last course's week number.
final class ZhengfangScheduleParser {
  const ZhengfangScheduleParser();

  TermCatalog parseTermCatalog(String source) =>
      parseZhengfangTermCatalog(source);

  ScheduleSnapshot parseSnapshot(
    Object? response, {
    required AcademicTerm term,
    required DateTime fetchedAt,
    String? sourceLabel,
    String? expectedStudentId,
  }) {
    final root = _Record(_decode(response));
    _checkAccepted(root);
    final payload = root.has('kblist')
        ? root
        : root.value('data') is Map
        ? _Record(root.value('data'))
        : root;
    _checkAccepted(payload);
    for (final scope in {root, payload}) {
      _checkTerm(scope, term);
      final student = scope.value('xsxx');
      if (student != null) {
        final record = _Record(student, path: 'xsxx');
        _checkTerm(record, term);
        final returned = record.text(const ['xh']);
        if (expectedStudentId != null &&
            returned != null &&
            returned != expectedStudentId.trim()) {
          record.fail('xh', '学校返回的课表不属于当前账号，未保存这次导入');
        }
      }
      if (scope.list('rqazclist').isNotEmpty) {
        throw const ScheduleParseException(
          ScheduleParseCode.unsupported,
          '学校返回了尚未识别的按日期教学安排，原有课表已保留',
          field: 'rqazcList',
        );
      }
    }
    final entries = <String, ScheduleEntry>{};
    void addRows(
      List<Object?> rows, {
      required bool practice,
      required String path,
    }) {
      for (var index = 0; index < rows.length; index++) {
        final row = _Record(rows[index], path: path, index: index);
        for (final entry in _entries(row, practice: practice)) {
          final previous = entries[entry.id];
          if (previous != null &&
              (!previous.hasSameArrangement(entry) ||
                  previous.metadata.length != entry.metadata.length ||
                  previous.metadata.entries.any(
                    (field) => entry.metadata[field.key] != field.value,
                  ))) {
            row.fail('record', '同一教学安排返回了相互矛盾的内容，请在教务网页核对');
          }
          entries[entry.id] = entry;
        }
      }
    }

    addRows(
      payload.list('kblist', required: true),
      practice: false,
      path: 'kbList',
    );
    for (final scope in {root, payload}) {
      addRows(scope.list('sjklist'), practice: true, path: 'sjkList');
      addRows(scope.list('jxhjkclist'), practice: true, path: 'jxhjkcList');
    }
    return ScheduleSnapshot(
      term: term,
      entries: entries.values.toList(),
      fetchedAt: fetchedAt,
      sourceLabel: sourceLabel,
    );
  }

  /// Parses explicit period numbers and times returned by a daily-period API.
  List<PeriodTime> parsePeriodTimes(Object? response, {String? campus}) {
    final decoded = _decode(response);
    final List<Object?> rows;
    if (decoded is List<Object?>) {
      rows = decoded;
    } else {
      final root = _Record(decoded);
      _checkAccepted(root);
      rows = root.has('rjlist')
          ? root.list('rjlist', required: true)
          : root.list('data', required: true);
    }
    final times = <(String?, int), PeriodTime>{};
    for (var index = 0; index < rows.length; index++) {
      final row = _Record(rows[index], path: 'periodTimes', index: index);
      final numberText = row.text(const ['jc', 'jcs', 'jcmc', 'number']);
      if (numberText == null) row.fail('jc', '学校作息缺少课节序号');
      final ranges = row.notation('jc', () => parsePeriodRanges(numberText));
      if (ranges.length != 1 || ranges.single.start != ranges.single.end) {
        row.fail('jc', '一条作息记录必须对应一个课节');
      }
      final start = _minutes(row, const ['qssj', 'kssj', 'starttime']);
      final end = _minutes(row, const ['jssj', 'endtime']);
      if (start >= end) row.fail('qssj/jssj', '课节结束时间必须晚于开始时间');
      final time = PeriodTime(
        number: ranges.single.start,
        startMinutes: start,
        endMinutes: end,
        campus: row.text(const ['xqmc', 'campus']) ?? campus,
      );
      final key = (time.campus, time.number);
      final previous = times[key];
      if (previous != null &&
          (previous.startMinutes != time.startMinutes ||
              previous.endMinutes != time.endMinutes)) {
        row.fail('jc', '同一校区同一课节返回了不同的作息时间');
      }
      times[key] = time;
    }
    return List.unmodifiable(
      times.values.toList()..sort((left, right) {
        final campusOrder = (left.campus ?? '').compareTo(right.campus ?? '');
        return campusOrder == 0
            ? left.number.compareTo(right.number)
            : campusOrder;
      }),
    );
  }
}

List<ScheduleEntry> _entries(_Record row, {required bool practice}) {
  final name = row.text([
    'kcmc',
    'kc_mc',
    'sjkcmc',
    'coursename',
    if (practice) 'jxhjmc',
    if (practice) 'sjkcgs',
    if (practice) 'qtkcgs',
    if (practice) 'jxhjkcgs',
  ]);
  if (name == null) row.fail('kcmc', '课表中有一条没有课程名称的记录');
  final teacher = row.text(const ['xm', 'jsxm', 'jsmc', 'jsxx', 'teacher']);
  final room = row.text(const ['cdmc', 'jxcdmc', 'jxdd', 'location']);
  final building = row.text(const ['cdlmc', 'jxlmc']);
  final location = building == null || (room?.contains(building) ?? false)
      ? room
      : room == null
      ? building
      : '$building $room';
  final campus = row.text(const ['xqmc', 'cdxqmc', 'campus']);
  final teachingClassId = row.text(const [
    'jxb_id',
    'jx0404id',
    'teachingclassid',
  ]);
  final courseCode = row.text(const ['kch', 'kch_id', 'coursecode']);
  final rawDay = _arrangedText(row.text(const ['xqj', 'weekday']));
  final weekday = rawDay == null ? null : _weekday(row, rawDay);
  final rawPeriods = _arrangedText(row.text(const ['jcs', 'jcor']));
  final periods = rawPeriods == null
      ? <PeriodRange>[]
      : row.notation('jcs', () => parsePeriodRanges(rawPeriods));
  final rawWeeks = _rawWeeks(row, practice: practice);
  final weeks = rawWeeks == null
      ? <int>{}
      : row.notation('zcd', () => parseTeachingWeeks(rawWeeks));
  if (!practice) {
    if ((weekday == null) != periods.isEmpty) {
      row.fail('xqj/jcs', '课程的星期和课节信息不完整');
    }
    if (weekday != null && rawWeeks == null) {
      row.fail('zcd', '有上课时段的课程缺少教学周，无法准确导入');
    }
  }
  final kind = practice
      ? row.text(const ['sfsjk']) == '0'
            ? ScheduleEntryKind.unscheduled
            : ScheduleEntryKind.practice
      : weekday == null
      ? ScheduleEntryKind.unscheduled
      : ScheduleEntryKind.lesson;
  final metadata = <String, String>{};
  for (final key in _metadataFields) {
    final value = row.text([key]);
    if (value != null) metadata[key] = value;
  }
  final sourceId = row.text(const ['schedule_source_id', 'kcb_id', 'kb_id']);
  ScheduleEntry entry(PeriodRange? range) {
    final identity = [
      sourceId,
      teachingClassId,
      courseCode,
      name,
      teacher,
      location,
      campus,
      metadata['xqh_id'],
      weekday,
      range?.start,
      range?.end,
      weeks.toList(),
      kind.name,
    ];
    final id =
        'imported:${base64Url.encode(utf8.encode(jsonEncode(identity)))}';
    return ScheduleEntry(
      id: id,
      name: name,
      teachingClassId: teachingClassId,
      courseCode: courseCode,
      teacher: teacher,
      location: location,
      campus: campus,
      weekday: weekday,
      startPeriod: range?.start,
      endPeriod: range?.end,
      weeks: weeks,
      rawWeeks: rawWeeks,
      metadata: metadata,
      kind: kind,
    );
  }

  return periods.isEmpty ? [entry(null)] : periods.map(entry).toList();
}

String? _rawWeeks(_Record row, {required bool practice}) {
  final text = _arrangedText(row.text(const ['zcd', 'weeks', 'qsjsz']));
  if (text != null || !practice) return text;
  final start = _arrangedText(row.text(const ['qsz']));
  final end = _arrangedText(row.text(const ['zzz']));
  if (start == null && end == null) return null;
  if (start == null || end == null) {
    row.fail('qsz/zzz', '实践课的起止教学周信息不完整');
  }
  return '$start-$end周';
}

String? _arrangedText(String? value) =>
    const {'未安排', '未排课', '待定', '待安排', '待排', '暂无', '--', '无'}.contains(value)
    ? null
    : value;

int _weekday(_Record row, String source) {
  final normalized = normalizeScheduleNotation(source);
  final day = switch (normalized) {
    '周一' || '星期一' => 1,
    '周二' || '星期二' => 2,
    '周三' || '星期三' => 3,
    '周四' || '星期四' => 4,
    '周五' || '星期五' => 5,
    '周六' || '星期六' => 6,
    '周日' || '周天' || '星期日' || '星期天' => 7,
    _ => int.tryParse(normalized),
  };
  if (day == null || day < 1 || day > DateTime.daysPerWeek) {
    row.fail('xqj', '学校返回了无效的上课星期');
  }
  return day;
}

int _minutes(_Record row, List<String> fields) {
  final source = row.text(fields);
  final value = source?.replaceAll('：', ':');
  final match = value == null
      ? null
      : RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(value);
  if (match == null) row.fail(fields.first, '学校返回的作息时间无法识别');
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  final second = match.group(3) == null ? 0 : int.parse(match.group(3)!);
  if (hour > 24 || minute > 59 || second != 0 || (hour == 24 && minute != 0)) {
    row.fail(fields.first, '学校返回的作息时间超出有效范围');
  }
  return hour * 60 + minute;
}

void _checkTerm(_Record row, AcademicTerm term) {
  for (final field in ['xnm', 'xqm']) {
    final value = row.text([field]);
    final expected = field == 'xnm' ? term.yearCode : term.termCode;
    if (value != null && value != expected) {
      row.fail(field, '学校返回的学年或学期与本次请求不一致');
    }
  }
}

void _checkAccepted(_Record row) {
  if (row.value('xnxqsfkz') == true || row.value('xnxqsfkz') == 'true') {
    throw const ScheduleParseException(
      ScheduleParseCode.schoolRejected,
      '学校尚未允许查看这个学期的课表，已保留本机课表',
    );
  }
  for (final field in const ['xkkg', 'jfckbkg']) {
    if (const {false, 0, 'false', '0'}.contains(row.value(field))) {
      throw ScheduleParseException(
        ScheduleParseCode.schoolRejected,
        field == 'xkkg' ? '学校尚未开放这个学期的课表' : '学校要求处理缴费状态后才能查询课表',
      );
    }
  }
  final success = row.value('success');
  final status = row.value('status')?.toString().toLowerCase();
  final code = row.value('code')?.toString();
  final rejected =
      success == false ||
      success == 0 ||
      success == 'false' ||
      success == '0' ||
      const {
        'error',
        'failed',
        'failure',
        'forbidden',
        'false',
      }.contains(status) ||
      (code != null &&
          !const {'', '0', '200'}.contains(code) &&
          success != true);
  final error = row.value('error');
  final hasError =
      error == true ||
      (error is String && error.trim().isNotEmpty) ||
      (error is Map && error.isNotEmpty);
  if (rejected || hasError) {
    throw const ScheduleParseException(
      ScheduleParseCode.schoolRejected,
      '学校未接受本次课表查询，请在学校网页核对查询条件',
    );
  }
}

Object? _decode(Object? response) {
  if (response is! String) return response;
  try {
    return jsonDecode(response.replaceFirst(RegExp(r'^\uFEFF'), ''));
  } on FormatException {
    throw const ScheduleParseException(
      ScheduleParseCode.invalidResponse,
      '学校没有返回有效的课表 JSON 数据',
    );
  }
}

final class _Record {
  _Record(Object? value, {this.path, this.index}) {
    if (value is! Map<String, Object?>) {
      fail('record', '学校返回的课表记录结构无法识别');
    }
    for (final entry in value.entries) {
      final key = entry.key.toLowerCase();
      if (_values.containsKey(key)) {
        if (_values[key] == entry.value) continue;
        fail(entry.key, '学校返回了重复且大小写不一致的字段');
      }
      _values[key] = entry.value;
    }
  }

  final String? path;
  final int? index;
  final _values = <String, Object?>{};

  bool has(String key) => _values.containsKey(key);
  Object? value(String key) => _values[key];

  String? text(List<String> keys) {
    for (final key in keys) {
      final value = _values[key];
      if (value == null) continue;
      if (value is! String && value is! num) {
        fail(key, '学校返回的课表字段类型无法识别');
      }
      final fragment = html.parseFragment(value.toString());
      for (final node in fragment.querySelectorAll('script, style')) {
        node.remove();
      }
      final result = fragment.text?.trim();
      if (result != null && result.isNotEmpty && result != 'null') {
        return result;
      }
    }
    return null;
  }

  List<Object?> list(String key, {bool required = false}) {
    final value = _values[key];
    if (value == null && !required) return const [];
    if (value is! List<Object?>) {
      fail(key, '学校响应缺少有效的课表列表', missing: value == null);
    }
    return value;
  }

  T notation<T>(String field, T Function() parse) {
    try {
      return parse();
    } on ScheduleParseException catch (error) {
      throw ScheduleParseException(
        error.code,
        error.message,
        field: path == null ? field : '$path.$field',
        recordIndex: index,
      );
    }
  }

  Never fail(String field, String message, {bool missing = false}) =>
      throw ScheduleParseException(
        missing
            ? ScheduleParseCode.missingField
            : ScheduleParseCode.invalidValue,
        message,
        field: path == null ? field : '$path.$field',
        recordIndex: index,
      );
}

const _metadataFields = [
  'jxbmc',
  'xf',
  'kcxz',
  'kcxzmc',
  'kclb',
  'kclbmc',
  'khfsmc',
  'ksfsmc',
  'zxs',
  'skfsmc',
  'kkbmmc',
  'qsz',
  'zzz',
  'qsjsz',
  'bz',
  'xqh_id',
  'sksj',
  'sjkcgs',
  'qtkcgs',
  'jxhjkcgs',
  'cxbj',
  'xsskbz',
];
