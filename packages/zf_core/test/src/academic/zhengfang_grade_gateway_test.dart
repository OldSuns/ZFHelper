import 'dart:convert';

import 'package:test/test.dart';
import 'package:zf_core/src/academic/zhengfang_grade_gateway.dart';
import 'package:zf_core/src/auth/authenticated_read_client.dart';
import 'package:zf_core/src/auth/login_models.dart';
import 'package:zf_core/src/auth/school_connection.dart';
import 'package:zf_core/src/grades/grade_parse_exception.dart';

// Constructed responses following zhengfang-apk v1.0.76, commit 1ff0815.
// These fixtures contain no real school account or captured response.
void main() {
  final school = SchoolConnection(
    name: '测试学校',
    baseUri: Uri.parse('https://jw.example.test/jwglxt/'),
  );
  final fetchedAt = DateTime.utc(2026, 9, 14);
  ZhengfangGradeGateway gateway(_Client client, {String? studentId}) =>
      ZhengfangGradeGateway(
        profile: school,
        client: client,
        clock: () => fetchedAt,
        studentId: studentId,
      );

  test('accepts empty aliases and legacy page-size defaults', () async {
    final client = _Client(
      (request, index) => _response(request, {
        'items': [
          {'kcmc': '课程'},
        ],
        'rows': null,
        'showCount': 200,
        'pageSize': 15,
      }),
    );
    final snapshot = await gateway(client).readGrades();
    expect(snapshot.records, hasLength(1));
    expect(client.requests, hasLength(1));
  });

  test(
    'uses reference count priority and ignores legacy pagination fields',
    () async {
      final client = _Client(
        (request, index) => _response(request, {
          'count': 3,
          'totalCount': 15,
          'totalResult': 200,
          'records': 0,
          'totalPage': 1,
          'total': 0,
          'currentPage': 0,
          'page': 1,
          'showCount': 200,
          'pageSize': 15,
          'queryModel': {'count': 0, 'currentPage': 1, 'showCount': 15},
          'items': [_row('课程 $index')],
        }),
      );
      final snapshot = await gateway(client).readGrades();
      expect(snapshot.records.map((record) => record.name), [
        '课程 0',
        '课程 1',
        '课程 2',
      ]);
      expect(client.requests, hasLength(3));
    },
  );

  test(
    'queries all terms without an HTML prerequisite and reads every page',
    () async {
      final client = _Client((request, index) {
        expect(request.method, 'POST');
        expect(request.uri, school.gradeQueryUri);
        expect(request.headers['X-Requested-With'], 'XMLHttpRequest');
        expect(Map.fromEntries(request.form), {
          'xnm': '',
          'xqm': '',
          'queryModel.showCount': '200',
          'queryModel.currentPage': '${index + 1}',
          'queryModel.sortName': '',
          'queryModel.sortOrder': 'asc',
          'time': '0',
        });
        return _response(request, {
          'total': 2,
          'records': 3,
          'page': index + 1,
          'items': index == 0
              ? [
                  _row(
                    '微积分',
                    score: '<span>59.5</span>',
                    extra: {
                      'jd': '0',
                      'xh': 'fixture-student',
                      'pscj': 0,
                      'cookie': 'fixture-value-must-not-be-persisted',
                    },
                  ),
                ]
              : [
                  _row('微积分', score: '通过', extra: {'ksxz': '补考', 'bkcj': '通过'}),
                  _row('夏季实践', score: '优秀', extra: {'xqm': '16', 'cxbj': '1'}),
                ],
        });
      });
      final snapshot = await gateway(
        client,
        studentId: 'fixture-student',
      ).readGrades();
      expect(client.requests, hasLength(2));
      expect(snapshot.records, hasLength(3));
      expect(snapshot.records.map((record) => record.id).toSet(), hasLength(3));
      expect(snapshot.records.first.numericScore, 59.5);
      expect(snapshot.records.first.gradePointValue, 0);
      expect(snapshot.records.first.passed, isNull);
      expect(snapshot.records.first.details, {'平时成绩': '0'});
      expect(snapshot.records[1].score, '通过');
      expect(snapshot.records[1].numericScore, isNull);
      expect(snapshot.records[1].examNature, '补考');
      expect(snapshot.records[1].details['补考成绩'], '通过');
      expect(snapshot.records[2].term!.termCode, '16');
      expect(snapshot.records[2].term!.label, contains('小学期'));
      expect(snapshot.records[2].retake, '1');
      expect(snapshot.fetchedAt, fetchedAt);
      expect(snapshot.sourceLabel, '测试学校教务系统');
    },
  );

  test(
    'keeps repeated attempts, absent terms and absent grade points',
    () async {
      final client = _Client(
        (request, index) => _response(request, {
          'items': [
            {'kcmc': '同名课程', 'cj': '优秀', 'xfjd': '12'},
            {'kcmc': '同名课程', 'cj': '优秀', 'xfjd': '12'},
          ],
          'totalResult': 2,
        }),
      );
      final records = (await gateway(client).readGrades()).records;
      expect(records, hasLength(2));
      expect(records.first.id, isNot(records.last.id));
      expect(records.first.term, isNull);
      expect(records.first.gradePoint, isNull);
      expect(records.first.details['学分绩点'], '12');
    },
  );

  test('uses published semester names when codes are absent and keeps custom codes', () async {
    final client = _Client(
      (request, index) => _response(request, [
        {
          'kcmc': '学校只提供学期名称的课程',
          'cj': '合格',
          'xnmc': '2025–2026',
          'xqmc': '第二学期',
        },
        _row('学校自定义学期代码的课程', extra: {'xqm': '7', 'xqmc': '第二学期'}),
      ]),
    );
    final records = (await gateway(client).readGrades()).records;
    expect(records.first.term!.yearCode, '2025');
    expect(records.first.term!.termCode, '第二学期');
    expect(records.first.term!.label, '2025–2026 学年 第二学期');
    expect(records.last.term!.termCode, '7');
    expect(records.last.term!.label, contains('第二学期'));
  });

  test(
    'uses a school pass flag without applying a numeric threshold',
    () async {
      final client = _Client(
        (request, index) => _response(request, [
          _row('课程甲', score: '55', extra: {'sfjg': '1'}),
          _row('课程乙', score: '80', extra: {'sfjg': false}),
          _row('课程丙', score: '及格'),
        ]),
      );
      final records = (await gateway(client).readGrades()).records;
      expect(records.map((record) => record.passed), [true, false, null]);
    },
  );

  test('does not save a query whose total changes between pages', () async {
    final client = _Client(
      (request, index) => _response(request, {
        'items': [_row('课程 $index')],
        'records': index == 0 ? 3 : 4,
      }),
    );
    await expectLater(
      gateway(client).readGrades(),
      throwsA(_parseCode(GradeParseCode.incompleteResponse)),
    );
  });

  test(
    'rejects repeated pages even if the JSON object key order changes',
    () async {
      final client = _Client(
        (request, index) => _response(request, {
          'items': [
            index == 0
                ? {'kcmc': '课程', 'cj': '80'}
                : {'cj': '80', 'kcmc': '课程'},
          ],
          'records': 2,
        }),
      );
      await expectLater(
        gateway(client).readGrades(),
        throwsA(_parseCode(GradeParseCode.incompleteResponse)),
      );
      expect(client.requests, hasLength(2));
    },
  );

  test('rejects an empty page before all reported records arrive', () async {
    final client = _Client(
      (request, index) => _response(request, {
        'items': index == 0 ? [_row('课程')] : <Object?>[],
        'records': 2,
      }),
    );
    await expectLater(
      gateway(client).readGrades(),
      throwsA(_parseCode(GradeParseCode.incompleteResponse)),
    );
  });

  test(
    'ignores response pagination copies when no root count is reported',
    () async {
      final client = _Client((request, index) {
        expect(index, lessThan(2));
        expect(
          Map.fromEntries(request.form)['queryModel.currentPage'],
          '${index + 1}',
        );
        return _response(request, {
          'total': 1,
          'totalPage': 1,
          'showCount': 999,
          'pageSize': 15,
          'queryModel': {'count': 1, 'currentPage': 1, 'showCount': 15},
          'data': {
            'count': 1,
            'items': index == 0
                ? [for (var row = 0; row < 200; row++) _row('课程 $row')]
                : [_row('最后一门课程')],
          },
        });
      });
      final snapshot = await gateway(client).readGrades();
      expect(snapshot.records, hasLength(201));
      expect(snapshot.records.last.name, '最后一门课程');
      expect(client.requests, hasLength(2));
    },
  );

  test(
    'rejects a different account in nested or row identity fields',
    () async {
      for (final body in [
        {
          'DATA': {
            'XSXX': {'XH': 'other-fixture-student'},
            'ITEMS': <Object?>[],
          },
        },
        {
          'items': [
            _row('课程', extra: {'xh': 'other-fixture-student'}),
          ],
        },
      ]) {
        final client = _Client((request, index) => _response(request, body));
        await expectLater(
          gateway(client, studentId: 'fixture-student').readGrades(),
          throwsA(
            _parseCode(GradeParseCode.identityMismatch).having(
              (error) => error.toString(),
              'diagnostic',
              isNot(contains('other-fixture-student')),
            ),
          ),
        );
      }
    },
  );

  test('rejects contradictory term fields in one assessment', () async {
    for (final extra in [
      {'xnmc': '2026-2027'},
      {'xnxqid': '2025-2026-1'},
    ]) {
      final client = _Client(
        (request, index) => _response(request, [_row('课程', extra: extra)]),
      );
      await expectLater(
        gateway(client).readGrades(),
        throwsA(_parseCode(GradeParseCode.invalidValue)),
      );
    }
  });

  test(
    'distinguishes a valid empty list from rejection and malformed rows',
    () async {
      final empty = _Client(
        (request, index) => _response(request, {
          'items': <Object?>[],
          'rows': [_row('备用课程')],
          'records': 0,
        }),
      );
      expect((await gateway(empty).readGrades()).records, isEmpty);
      for (final (body, code) in [
        (
          {'success': false, 'items': <Object?>[]},
          GradeParseCode.schoolRejected,
        ),
        ({'other': <Object?>[]}, GradeParseCode.invalidResponse),
        (
          {
            'items': [
              {'cj': '80'},
            ],
            'rows': [_row('备用课程')],
          },
          GradeParseCode.missingField,
        ),
        (
          {
            'items': [
              _row(
                '课程',
                extra: {
                  'cj': {'value': 80},
                },
              ),
            ],
          },
          GradeParseCode.invalidValue,
        ),
      ]) {
        final client = _Client((request, index) => _response(request, body));
        await expectLater(
          gateway(client).readGrades(),
          throwsA(_parseCode(code)),
        );
      }
    },
  );

  test(
    'surfaces an HTTP 200 login page or explicit login-expiry response',
    () async {
      for (final body in [
        '<html><form><input type="password" name="mm"></form></html>',
        jsonEncode({'success': false, 'msg': 'notLogin'}),
      ]) {
        final client = _Client(
          (request, index) => AuthHttpResponse(
            uri: request.uri,
            statusCode: 200,
            body: utf8.encode(body),
          ),
        );
        await expectLater(
          gateway(client).readGrades(),
          throwsA(
            isA<LoginFailure>().having(
              (error) => error.code,
              'code',
              LoginFailureCode.expired,
            ),
          ),
        );
      }
    },
  );
}

TypeMatcher<GradeParseException> _parseCode(GradeParseCode code) =>
    isA<GradeParseException>().having((error) => error.code, 'code', code);

Map<String, Object?> _row(
  String name, {
  String score = '80',
  Map<String, Object?> extra = const {},
}) => {
  'kcmc': name,
  'cj': score,
  'xf': '2',
  'xnm': '2025',
  'xqm': '12',
  ...extra,
};

final class _Client implements AuthenticatedReadClient {
  _Client(this.respond);
  final AuthHttpResponse Function(AuthHttpRequest, int) respond;
  final requests = <AuthHttpRequest>[];

  @override
  Future<AuthHttpResponse> sendRead(AuthHttpRequest request) async {
    requests.add(request);
    return respond(request, requests.length - 1);
  }
}

AuthHttpResponse _response(AuthHttpRequest request, Object? body) =>
    AuthHttpResponse(
      uri: request.uri,
      statusCode: 200,
      body: utf8.encode(jsonEncode(body)),
    );
