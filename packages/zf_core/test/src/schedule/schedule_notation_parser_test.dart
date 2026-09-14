import 'package:test/test.dart';
import 'package:zf_core/src/schedule/schedule_notation_parser.dart';
import 'package:zf_core/src/schedule/schedule_parse_exception.dart';

void main() {
  group('teaching week notation', () {
    test('bounds expansion work without setting an academic term length', () {
      expect(
        () => parseTeachingWeeks('1-9223372036854775807周'),
        throwsA(
          isA<ScheduleParseException>().having(
            (error) => error.code,
            'code',
            ScheduleParseCode.unsupported,
          ),
        ),
      );
      expect(
        () => parseTeachingWeeks('1-600周,1-600周'),
        throwsA(isA<ScheduleParseException>()),
      );
      expect(parseTeachingWeeks('1001周'), {1001});
      expect(parseTeachingWeeks('9223372036854775807周'), {9223372036854775807});
      expect(
        parseTeachingWeeks('1-1001周', maxExpandedNumbers: null),
        hasLength(1001),
      );
    });

    final cases = <String, Set<int>>{
      '1-4周': {1, 2, 3, 4},
      '1-3周,7周,9-10周': {1, 2, 3, 7, 9, 10},
      '2-10周(单)': {3, 5, 7, 9},
      '1-7周(双)': {2, 4, 6},
      '1-5周(单),8-12周(双),15周': {1, 3, 5, 8, 10, 12, 15},
      ' 第１－５周（单）；第８～１０周（双） ': {1, 3, 5, 8, 10},
      '1-3(单)周、5(单周)、8周(双周)': {1, 3, 5, 8},
      '1,3,5周': {1, 3, 5},
      '1-3周,2-4周': {1, 2, 3, 4},
      '27-30周': {27, 28, 29, 30},
    };
    for (final example in cases.entries) {
      test('preserves the weeks in ${example.key}', () {
        expect(parseTeachingWeeks(example.key), example.value);
      });
    }

    for (final source in [
      '',
      '每周',
      '全部',
      '0-8周',
      '8-2周',
      '1-8周(隔周)',
      '2周(单)',
      '1周(双)',
      '1-8周,',
      '1周 / 3周',
      '1周garbage',
      '1周周',
      '-3周',
    ]) {
      test('rejects unknown or contradictory weeks: $source', () {
        expect(
          () => parseTeachingWeeks(source),
          throwsA(isA<ScheduleParseException>()),
        );
      });
    }

    test('returned weeks cannot be changed by callers', () {
      final weeks = parseTeachingWeeks('3周,1周');
      expect(weeks.toList(), [1, 3]);
      expect(() => weeks.add(2), throwsUnsupportedError);
    });
  });

  group('teaching period notation', () {
    test('rejects huge expansions and can explicitly raise the work limit', () {
      expect(
        () => parsePeriodRanges('1-9223372036854775807'),
        throwsA(isA<ScheduleParseException>()),
      );
      final allowed = parsePeriodRanges('1-1001', maxExpandedNumbers: 1001);
      expect((allowed.single.start, allowed.single.end), (1, 1001));
    });

    test('rejects mismatched period brackets', () {
      for (final source in ['(1-2]', '[1-2)']) {
        expect(
          () => parsePeriodRanges(source),
          throwsA(isA<ScheduleParseException>()),
        );
      }
    });

    test('keeps the gap in separated blocks', () {
      final ranges = parsePeriodRanges('1-2,5-6');
      expect(ranges.map((range) => (range.start, range.end)), [(1, 2), (5, 6)]);
    });

    test('deduplicates overlaps and joins only adjacent periods', () {
      final ranges = parsePeriodRanges('5,1-2,2-3,7-8,6');
      expect(ranges.map((range) => (range.start, range.end)), [(1, 3), (5, 8)]);
    });

    test('understands fullwidth labels and bracketed display values', () {
      final first = parsePeriodRanges('第１－２节、５－６节');
      final second = parsePeriodRanges('（1-2节）');
      expect(first.map((range) => (range.start, range.end)), [(1, 2), (5, 6)]);
      expect(second.map((range) => (range.start, range.end)), [(1, 2)]);
    });

    for (final source in ['', '1-2,invalid', '0-2', '5-2', '1,', '1.5', '待定']) {
      test('rejects a partially unrecognized period expression: $source', () {
        expect(
          () => parsePeriodRanges(source),
          throwsA(isA<ScheduleParseException>()),
        );
      });
    }
  });
}
