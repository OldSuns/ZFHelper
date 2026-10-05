import 'dart:convert';

import 'package:test/test.dart';
import 'package:zf_core/src/schedule/academic_term.dart';
import 'package:zf_core/src/schedule/schedule_entry.dart';
import 'package:zf_core/src/schedule/schedule_parse_exception.dart';
import 'package:zf_core/src/schedule/teaching_calendar.dart';
import 'package:zf_core/src/schedule/zhengfang_schedule_parser.dart';

// These fixtures are synthetic. Field names follow the public new Zhengfang
// readers in znjhahaha/zhengfang-apk at 38b4fd3 and zaochih/zf-to-ics at 12a5645.
// They are not captures from an authenticated school account.
void main() {
  const parser = ZhengfangScheduleParser();
  final term = AcademicTerm(
    yearCode: '2026',
    termCode: '3',
    label: '2026–2027 秋季',
  );
  final fetchedAt = DateTime.utc(2026, 9, 13, 5);
  Map<String, Object?> lesson({
    String name = '高等数学',
    String classId = 'class-a',
  }) => {
    'jxb_id': classId,
    'kch_id': 'MATH-101',
    'kcmc': name,
    'xm': '测试教师',
    'xqmc': '测试校区',
    'cdmc': '教学楼 101',
    'xqj': '1',
    'jcs': '1-2',
    'zcd': '1-16周',
    'xf': '4.0',
  };
  final parseError = isA<ScheduleParseException>();

  group('complete timetable imports', () {
    test(
      'keeps separate period blocks and every room in one teaching class',
      () {
        final first = lesson()..['jcs'] = '1-2,5-6';
        final second = lesson()
          ..['xqj'] = '3'
          ..['cdmc'] = '实验楼 202';
        final snapshot = parser.parseSnapshot(
          {
            'kbList': [first, second],
          },
          term: term,
          fetchedAt: fetchedAt,
        );
        expect(snapshot.entries, hasLength(3));
        expect(
          snapshot.entries.map((entry) => (entry.startPeriod, entry.endPeriod)),
          [(1, 2), (5, 6), (1, 2)],
        );
        expect(
          snapshot.entries.map((entry) => entry.groupKey).toSet(),
          hasLength(1),
        );
        expect(snapshot.entries.last.location, '实验楼 202');
        expect(snapshot.entries.first.metadata['xf'], '4.0');
        expect(snapshot.calendar.source, TeachingCalendarSource.unknown);
        expect(snapshot.calendar.totalWeeks, isNull);
        expect(snapshot.observedMaxWeek, 16);
      },
    );

    test(
      'parses V9 uppercase fields and rich text without exposing markup',
      () {
        final row = <String, Object?>{
          'JXB_ID': 'class-v9',
          'KCMC': '<span>化学 &amp; 实验</span>',
          'XM': '测试教师',
          'XQJ': 7,
          'JCOR': '(9-10节)',
          'ZCD': '2-10周(单)',
          'CDLMC': '综合楼',
          'CDMC': '301',
        };
        final snapshot = parser.parseSnapshot(
          jsonEncode({
            'KBList': [row],
          }),
          term: term,
          fetchedAt: fetchedAt,
        );
        final entry = snapshot.entries.single;
        expect(entry.name, '化学 & 实验');
        expect(entry.weekday, 7);
        expect(entry.weeks, {3, 5, 7, 9});
        expect(entry.location, '综合楼 301');
        expect(entry.isPlaced, isTrue);
      },
    );

    test(
      'deduplicates the same arrangement with stable IDs after row reordering',
      () {
        final first = lesson();
        final other = lesson(classId: 'class-b');
        final one = parser.parseSnapshot(
          {
            'kbList': [first, other, first],
          },
          term: term,
          fetchedAt: fetchedAt,
        );
        final two = parser.parseSnapshot(
          {
            'kbList': [other, first],
          },
          term: term,
          fetchedAt: fetchedAt.add(const Duration(days: 1)),
        );
        expect(one.entries, hasLength(2));
        expect(
          one.entries.map((entry) => entry.id).toSet(),
          two.entries.map((entry) => entry.id).toSet(),
        );
        expect(
          one.entries.map((entry) => entry.groupKey).toSet(),
          hasLength(2),
        );
      },
    );

    test(
      'retains practice weeks and a practice course with no arrangement',
      () {
        final snapshot = parser.parseSnapshot(
          {
            'kbList': <Object?>[],
            'sjkList': [
              {
                'kcmc': '校外实践',
                'qsz': '2',
                'zzz': '4',
                'xm': '指导教师',
                'cdmc': '实践基地',
              },
              {'kcmc': '短学期实训', 'qsjsz': '18-19周'},
              {'kcmc': '待安排实践'},
            ],
          },
          term: term,
          fetchedAt: fetchedAt,
        );
        expect(snapshot.entries, hasLength(3));
        expect(snapshot.entries.first.weeks, {2, 3, 4});
        expect(snapshot.entries[1].weeks, {18, 19});
        expect(snapshot.entries.last.weeks, isEmpty);
        expect(
          snapshot.entries.every(
            (entry) =>
                entry.kind == ScheduleEntryKind.practice && !entry.isPlaced,
          ),
          isTrue,
        );
        expect(snapshot.entries.last.occursInWeek(1), isFalse);
      },
    );

    test('retains explicitly unplaced named courses in their weekly list', () {
      final snapshot = parser.parseSnapshot(
        {
          'kbList': [
            {'kcmc': '学术活动', 'zcd': '6周', 'xqj': '待安排', 'jcs': '待安排'},
          ],
        },
        term: term,
        fetchedAt: fetchedAt,
      );
      final entry = snapshot.entries.single;
      expect(entry.kind, ScheduleEntryKind.unscheduled);
      expect(entry.isPlaced, isFalse);
      expect(entry.occursInWeek(6), isTrue);
    });

    test(
      'recognizes an authoritative empty response without inventing limits',
      () {
        final snapshot = parser.parseSnapshot(
          {
            'data': {
              'kbList': <Object?>[],
              'sjkList': <Object?>[],
              'rqazcList': <Object?>[],
            },
          },
          term: term,
          fetchedAt: fetchedAt,
        );
        expect(snapshot.entries, isEmpty);
        expect(snapshot.observedMaxWeek, 0);
        expect(snapshot.maxPeriod, 0);
      },
    );
  });

  group('invalid responses never become an empty or partial success', () {
    test(
      'empty error markers do not turn a successful response into failure',
      () {
        for (final empty in [null, '', false, 0]) {
          expect(
            parser
                .parseSnapshot(
                  {'kbList': <Object?>[], 'success': true, 'error': empty},
                  term: term,
                  fetchedAt: fetchedAt,
                )
                .entries,
            isEmpty,
          );
        }
      },
    );

    test('duplicate case variants agree or fail explicitly', () {
      final matching = lesson()..['KCMC'] = '高等数学';
      expect(
        parser
            .parseSnapshot(
              {
                'kbList': [matching],
              },
              term: term,
              fetchedAt: fetchedAt,
            )
            .entries
            .single
            .name,
        '高等数学',
      );
      final conflicting = lesson()..['KCMC'] = '另一门课程';
      expect(
        () => parser.parseSnapshot(
          {
            'kbList': [conflicting],
          },
          term: term,
          fetchedAt: fetchedAt,
        ),
        throwsA(parseError),
      );
      expect(
        () => parser.parseSnapshot(
          {
            'kbList': [lesson(name: 'null')],
          },
          term: term,
          fetchedAt: fetchedAt,
        ),
        throwsA(parseError),
      );
    });

    for (final response in <Object?>[
      '<html><input type="password"></html>',
      '{not JSON}',
      <Object?>[],
      {},
      {'sjkList': <Object?>[]},
      {'data': <Object?>[]},
      {'kbList': null},
      {'kbList': '[]'},
      {
        'kbList': [null],
      },
      {'kbList': <Object?>[], 'sjkList': 'bad'},
    ]) {
      test('rejects invalid response $response', () {
        expect(
          () =>
              parser.parseSnapshot(response, term: term, fetchedAt: fetchedAt),
          throwsA(parseError),
        );
      });
    }

    test('rejects school failure even when it contains a list', () {
      for (final response in [
        {'success': false, 'kbList': <Object?>[]},
        {'code': '403', 'kbList': <Object?>[]},
        {
          'status': 'error',
          'data': {'kbList': <Object?>[]},
        },
      ]) {
        expect(
          () =>
              parser.parseSnapshot(response, term: term, fetchedAt: fetchedAt),
          throwsA(
            parseError.having(
              (error) => error.code,
              'code',
              ScheduleParseCode.schoolRejected,
            ),
          ),
        );
      }
    });

    test(
      'rejects date-specific arrangements until that protocol is understood',
      () {
        expect(
          () => parser.parseSnapshot(
            {
              'kbList': <Object?>[],
              'rqazcList': [
                {'kcmc': '调课'},
              ],
            },
            term: term,
            fetchedAt: fetchedAt,
          ),
          throwsA(
            parseError.having(
              (error) => error.code,
              'code',
              ScheduleParseCode.unsupported,
            ),
          ),
        );
      },
    );

    test(
      'rejects one broken record alongside valid lessons and reports its index',
      () {
        final broken = lesson(name: 'Do not expose this text')
          ..['zcd'] = '1-8周,错误';
        expect(
          () => parser.parseSnapshot(
            {
              'kbList': [lesson(), broken],
            },
            term: term,
            fetchedAt: fetchedAt,
          ),
          throwsA(
            parseError
                .having((error) => error.recordIndex, 'row', 1)
                .having((error) => error.field, 'field', 'kbList.zcd')
                .having(
                  (error) => error.toString(),
                  'diagnostic',
                  isNot(contains('Do not expose')),
                ),
          ),
        );
      },
    );

    for (final change in <MapEntry<String, Object?>>[
      const MapEntry('kcmc', ''),
      const MapEntry('xqj', '8'),
      const MapEntry('xqj', null),
      const MapEntry('jcs', '1-2,unrecognized'),
      const MapEntry('zcd', null),
      const MapEntry('zcd', '0-16周'),
      const MapEntry('xm', ['teacher']),
    ]) {
      test('rejects invalid course field ${change.key}: ${change.value}', () {
        final row = lesson()..[change.key] = change.value;
        expect(
          () => parser.parseSnapshot(
            {
              'kbList': [row],
            },
            term: term,
            fetchedAt: fetchedAt,
          ),
          throwsA(parseError),
        );
      });
    }

    test('rejects conflicting root and nested term echoes', () {
      for (final response in [
        {'xnm': '2025', 'kbList': <Object?>[]},
        {
          'xsxx': {'XNM': '2026', 'XQM': '12'},
          'kbList': <Object?>[],
        },
        {
          'data': {'xqm': '16', 'kbList': <Object?>[]},
        },
      ]) {
        expect(
          () =>
              parser.parseSnapshot(response, term: term, fetchedAt: fetchedAt),
          throwsA(parseError),
        );
      }
      expect(
        parser
            .parseSnapshot(
              {
                'xsxx': {'XNM': '2026', 'XQM': '3'},
                'kbList': <Object?>[],
              },
              term: term,
              fetchedAt: fetchedAt,
            )
            .term,
        term,
      );
    });

    test('rejects incomplete practice-week ranges', () {
      expect(
        () => parser.parseSnapshot(
          {
            'kbList': <Object?>[],
            'sjkList': [
              {'kcmc': '实践', 'qsz': '2'},
            ],
          },
          term: term,
          fetchedAt: fetchedAt,
        ),
        throwsA(parseError),
      );
    });
  });

  group('daily period times', () {
    test('reversed times are protocol errors with a record location', () {
      expect(
        () => parser.parsePeriodTimes([
          {'jc': '1', 'qssj': '09:00', 'jssj': '08:45'},
        ]),
        throwsA(
          parseError.having((error) => error.recordIndex, 'recordIndex', 0),
        ),
      );
    });

    test('parses and sorts explicit period numbers, preserving campus', () {
      final times = parser.parsePeriodTimes([
        {'jc': '2', 'qssj': '08:55:00', 'jssj': '09:40:00'},
        {'jc': '1', 'qssj': '08:00', 'jssj': '08:45'},
      ], campus: '测试校区');
      expect(times.map((time) => time.number), [1, 2]);
      expect(times.first.startMinutes, 8 * 60);
      expect(times.first.endMinutes, 8 * 60 + 45);
      expect(times.first.campus, '测试校区');
    });

    test('rejects conflicting definitions for one campus and period', () {
      expect(
        () => parser.parsePeriodTimes([
          {'jc': '1', 'qssj': '08:00', 'jssj': '08:45'},
          {'jc': '1', 'qssj': '08:10', 'jssj': '08:55'},
        ]),
        throwsA(parseError),
      );
    });

    test('rejects an unrecognized time instead of using a made-up clock', () {
      expect(
        () => parser.parsePeriodTimes([
          {'jc': '1', 'qssj': '上午第一节', 'jssj': '08:45'},
        ]),
        throwsA(parseError),
      );
      expect(
        () => parser.parsePeriodTimes([
          {'qssj': '08:00', 'jssj': '08:45'},
        ]),
        throwsA(parseError),
      );
    });
  });
}
