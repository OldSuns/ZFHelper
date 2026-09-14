import 'schedule_parse_exception.dart';

/// The default resource limit for expanding one untrusted schedule expression.
///
/// This limits parser work, not the length of an academic term. Callers with a
/// separately bounded input may override it or explicitly pass `null`.
const maximumExpandedScheduleNumbers = 1000;

/// One contiguous inclusive range of teaching periods.
final class PeriodRange {
  const PeriodRange({required this.start, required this.end});

  final int start;
  final int end;
}

/// Parses explicit week ranges and per-range odd/even qualifiers.
///
/// Unknown or contradictory notation throws [ScheduleParseException]; an empty
/// expression never means every week. Parity applies to actual week numbers,
/// so `2-10周(单)` includes weeks 3, 5, 7 and 9.
Set<int> parseTeachingWeeks(
  String source, {
  int? maxExpandedNumbers = maximumExpandedScheduleNumbers,
}) {
  _checkLimit(maxExpandedNumbers);
  final normalized = normalizeScheduleNotation(source);
  if (normalized.isEmpty) {
    throw const ScheduleParseException(
      ScheduleParseCode.missingField,
      '课程缺少教学周，无法确定在哪些周上课',
      field: 'zcd',
    );
  }
  final weeks = <int>{};
  var expanded = 0;
  for (final part in normalized.split(',')) {
    final match = RegExp(r'^第?(\d+)(?:-(\d+))?(.*)$').firstMatch(part);
    if (match == null) _invalidWeeks();
    final start = _positiveNumber(match.group(1), 'zcd');
    final end = match.group(2) == null
        ? start
        : _positiveNumber(match.group(2), 'zcd');
    if (end < start) _invalidWeeks();
    expanded = _checkedExpansion(
      start,
      end,
      expanded,
      maxExpandedNumbers,
      'zcd',
    );
    final suffix = match.group(3)!;
    final parity = switch (suffix) {
      '' || '周' => null,
      '(单)' || '(单周)' || '周(单)' || '周(单周)' || '(单)周' => 1,
      '(双)' || '(双周)' || '周(双)' || '周(双周)' || '(双)周' => 0,
      _ => _invalidWeeks(),
    };
    var included = false;
    for (var week = start; ; week++) {
      if (parity == null || week % 2 == parity) {
        weeks.add(week);
        included = true;
      }
      if (week == end) break;
    }
    if (!included) _invalidWeeks();
  }
  return Set.unmodifiable(weeks.toList()..sort());
}

/// Splits noncontiguous periods instead of extending a course through a gap.
List<PeriodRange> parsePeriodRanges(
  String source, {
  int? maxExpandedNumbers = maximumExpandedScheduleNumbers,
}) {
  _checkLimit(maxExpandedNumbers);
  var normalized = normalizeScheduleNotation(source);
  final wrapper = RegExp(r'^(?:\(([^()]+)\)|\[([^\[\]]+)\])节?$')
      .firstMatch(normalized);
  if (wrapper != null) normalized = wrapper.group(1) ?? wrapper.group(2)!;
  if (normalized.isEmpty) {
    throw const ScheduleParseException(
      ScheduleParseCode.missingField,
      '课程缺少课节安排',
      field: 'jcs',
    );
  }
  final numbers = <int>{};
  var expanded = 0;
  for (final part in normalized.split(',')) {
    final match = RegExp(r'^第?(\d+)(?:-(\d+))?节?$').firstMatch(part);
    if (match == null) _invalidPeriods();
    final start = _positiveNumber(match.group(1), 'jcs');
    final end = match.group(2) == null
        ? start
        : _positiveNumber(match.group(2), 'jcs');
    if (end < start) _invalidPeriods();
    expanded = _checkedExpansion(
      start,
      end,
      expanded,
      maxExpandedNumbers,
      'jcs',
    );
    for (var period = start; ; period++) {
      numbers.add(period);
      if (period == end) break;
    }
  }
  final ordered = numbers.toList()..sort();
  final ranges = <PeriodRange>[];
  var start = ordered.first;
  var end = start;
  for (final period in ordered.skip(1)) {
    if (period == end + 1) {
      end = period;
      continue;
    }
    ranges.add(PeriodRange(start: start, end: end));
    start = end = period;
  }
  ranges.add(PeriodRange(start: start, end: end));
  return List.unmodifiable(ranges);
}

void _checkLimit(int? limit) {
  if (limit != null && limit < 1) {
    throw ArgumentError.value(limit, 'maxExpandedNumbers', 'Must be positive.');
  }
}

int _checkedExpansion(
  int start,
  int end,
  int expanded,
  int? limit,
  String field,
) {
  final width = end - start + 1;
  if (limit != null && width > limit - expanded) {
    throw ScheduleParseException(
      ScheduleParseCode.unsupported,
      '学校返回的周次或课节范围异常大，无法安全展开该记录',
      field: field,
    );
  }
  return expanded + width;
}

String normalizeScheduleNotation(String source) {
  final halfWidth = String.fromCharCodes(
    source.runes.map(
      (rune) => rune >= 0xff01 && rune <= 0xff5e ? rune - 0xfee0 : rune,
    ),
  );
  return halfWidth
      .replaceAll(RegExp(r'\s|\u3000'), '')
      .replaceAll(RegExp('[，、；;]'), ',')
      .replaceAll(RegExp('[~～—–−至]'), '-');
}

int _positiveNumber(String? value, String field) {
  final number = int.tryParse(value ?? '');
  if (number == null || number < 1) {
    throw ScheduleParseException(
      ScheduleParseCode.invalidValue,
      '教学周和课节序号必须是正整数',
      field: field,
    );
  }
  return number;
}

Never _invalidWeeks() => throw const ScheduleParseException(
  ScheduleParseCode.invalidValue,
  '学校返回的教学周格式无法识别，请核对周次和单双周标记',
  field: 'zcd',
);

Never _invalidPeriods() => throw const ScheduleParseException(
  ScheduleParseCode.invalidValue,
  '学校返回的课节格式无法识别',
  field: 'jcs',
);
