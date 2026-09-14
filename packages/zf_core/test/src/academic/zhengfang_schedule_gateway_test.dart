import 'dart:convert';

import 'package:test/test.dart';
import 'package:zf_core/zf_core.dart';

// Synthetic protocol records following zhengfang-apk v1.0.75. No real account.
const _termPage = '''
<select name="xnm"><option value="2026" selected>2026–2027</option></select>
<select name="xqm"><option value="3" selected>第一学期</option></select>
<script src="/jwglxt/js/comp/jwglxt/pkgl/kbcx/xskbcx.js"></script>
''';

void main() {
  final school = SchoolConnection(
    name: '测试学校',
    baseUri: Uri.parse('https://jw.example.test/jwglxt/'),
  );

  test(
    'an explicit term imports when the school page has no term selectors',
    () async {
      final term = AcademicTerm(
        yearCode: '2025',
        termCode: '12',
        label: '2025–2026 学年 第二学期',
      );
      final client = _Client((request) {
        if (request.method == 'GET') {
          return _response(
            request,
            '<html><main id="app">学教一体化教务页面</main></html>',
          );
        }
        expect(request.uri, school.scheduleQueryUri);
        expect(Map.fromEntries(request.form), {'xnm': '2025', 'xqm': '12'});
        return _response(
          request,
          jsonEncode({
            'xsxx': {'XH': 'student', 'XNM': '2025', 'XQM': '12'},
            'kbList': [
              {'kcmc': '数学', 'xqj': '1', 'jcs': '1-2', 'zcd': '1-16周'},
            ],
          }),
        );
      });
      final result = await ZhengfangScheduleGateway(
        profile: school,
        client: client,
        studentId: 'student',
        clock: DateTime.now,
      ).importSchedule(term: term);
      expect(result.snapshot!.term, term);
      expect(result.snapshot!.entries.single.name, '数学');
      expect(client.requests.first.method, 'POST');
    },
  );

  test('uses the reference query before optional metadata and retains every kind of arrangement', () async {
    final client = _Client((request) {
      if (request.uri.path.endsWith('.js')) {
        throw const LoginFailure(LoginFailureCode.network, '测试网络故障');
      }
      if (request.method == 'GET') return _response(request, _termPage);
      expect(request.uri, school.scheduleQueryUri);
      expect(Map.fromEntries(request.form), {'xnm': '2026', 'xqm': '3'});
      return _response(
        request,
        jsonEncode({
          'xsxx': {'XH': 'student'},
          'kbList': [
            {
              'kcmc': '数学',
              'jxb_id': 'class-a',
              'xqj': '1',
              'jcs': '1-2,5-6',
              'zcd': '1-16周(单)',
            },
          ],
          'sjkList': [
            {'sjkcgs': '认识实习 · 18周', 'qsz': '18', 'zzz': '18'},
          ],
          'jxhjkcList': [
            {'jxhjkcgs': '毕业设计 · 时间另行通知'},
          ],
        }),
      );
    });
    final result = await ZhengfangScheduleGateway(
      profile: school,
      client: client,
      studentId: 'student',
      clock: () => DateTime(2026, 9, 13),
    ).importSchedule();
    expect(client.requests.take(2).map((request) => request.method), [
      'GET',
      'POST',
    ]);
    expect(result.snapshot!.entries, hasLength(4));
    expect(result.snapshot!.entries.first.weeks, {1, 3, 5, 7, 9, 11, 13, 15});
    expect(result.snapshot!.calendar.firstWeekMonday, isNull);
    expect(result.snapshot!.importWarnings.single, contains('作息'));
  });

  test(
    'rejects a different student in normalized nested response fields',
    () async {
      final client = _Client(
        (request) => request.method == 'GET'
            ? _response(request, _termPage)
            : _response(
                request,
                '{"DATA":{"XSXX":{"XH":"someone-else"},"KBLIST":[]}}',
              ),
      );
      final gateway = ZhengfangScheduleGateway(
        profile: school,
        client: client,
        studentId: 'student',
        clock: DateTime.now,
      );
      await expectLater(
        gateway.importSchedule(),
        throwsA(
          isA<ScheduleParseException>().having(
            (error) => error.message,
            'message',
            contains('不属于当前账号'),
          ),
        ),
      );
      expect(client.requests, hasLength(2));
    },
  );
}

final class _Client implements AuthenticatedReadClient {
  _Client(this.respond);
  final AuthHttpResponse Function(AuthHttpRequest) respond;
  final requests = <AuthHttpRequest>[];
  @override
  Future<AuthHttpResponse> sendRead(AuthHttpRequest request) async {
    requests.add(request);
    return respond(request);
  }
}

AuthHttpResponse _response(AuthHttpRequest request, String body) =>
    AuthHttpResponse(
      uri: request.uri,
      statusCode: 200,
      body: utf8.encode(body),
    );
