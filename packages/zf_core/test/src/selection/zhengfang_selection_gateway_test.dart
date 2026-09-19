import 'dart:convert';

import 'package:test/test.dart';
import 'package:zf_core/src/auth/authenticated_read_client.dart';
import 'package:zf_core/src/auth/login_models.dart';
import 'package:zf_core/src/auth/school_connection.dart';
import 'package:zf_core/src/selection/selection_models.dart';
import 'package:zf_core/src/selection/zhengfang_selection_gateway.dart';
import 'package:zf_core/src/selection/zhengfang_selection_parser.dart';

// Constructed from zhengfang-apk 1ff0815; no real account or school response.
void main() {
  test(
    'reads V9 context, submits fresh class once and verifies stable IDs',
    () async {
      final client = _Client([
        '''<input type="hidden" name="firstXkkzXh" value="round-v9">
      <input type="hidden" name="xkxnm" value="2027">
      <input type="hidden" name="xkxqm" value="3">
      <input type="hidden" name="xh" value="student-fixture">
      <a onclick="queryCourse(this,'05','round-v9','2024','major')">专业选修</a>''',
        '''<input type="hidden" name="xkkz_xh" value="">
      <input type="hidden" name="rwlx" value="1">
      <input type="hidden" name="xklc" value="2">
      <input type="hidden" name="jg_id_1" value="school-department">''',
        {
          'tmpList': <Object?>[],
          'data': [
            {'kch_id': 'course', 'kcmc': '算法', 'jxb_id': 'class', 'xf': '2.5'},
          ],
          'rows': null,
        },
        <Object?>[],
        [
          {
            'kch_id': 'course',
            'jxb_id': 'class',
            'do_jxb_id': 'a+b/c==',
            'jxbrl': 20,
            'yxzrs': 19,
            'jcxx_id': 'detail',
            'sxbj': '1',
          },
        ],
        {'flag': '1'},
        [
          {'kch_id': 'course', 'kcmc': '算法', 'jxb_id': 'another-class'},
          {'kch_id': 'course', 'kcmc': '算法', 'jxb_id': 'class'},
        ],
      ]);
      final gateway = ZhengfangSelectionGateway(
        profile: SchoolConnection(
          name: '测试学校',
          baseUri: Uri.parse('https://jw.example.test/jwglxt/'),
          selectionPagePath: 'xsxk/zzxkyzb_cxZzxkYzbIndex.html?gnmkdm=N-test',
        ),
        client: client,
        clock: () => DateTime.utc(2026, 9, 14),
        studentId: 'student-fixture',
      );
      final context = await gateway.readContext();
      final round = context.rounds.single;
      expect(round.controlKey, 'xkkz_xh');
      expect(round.term!.yearCode, '2027');
      final course = (await gateway.readCourses(
        context,
        round,
        keyword: '算法',
      )).single;
      final section = (await gateway.readSections(context, course)).single;
      expect(section.sectionId, 'class');
      expect(section.submitId, 'a+b/c==');
      expect(section.available, 1);
      expect(course.isSelected, isNull);
      expect(
        (await gateway.submit(context, course, section)).status,
        SelectionSubmissionStatus.accepted,
      );
      final selected = await gateway.readSelected(context, round: round);
      expect(selected.map((entry) => entry.matches(section)), [false, true]);
      final listForm = Map.fromEntries(client.requests[2].form);
      expect(listForm['xkkz_xh'], 'round-v9');
      expect(listForm['jg_id'], 'school-department');
      expect(listForm.containsKey('xbm'), isFalse);
      expect(Map.fromEntries(client.requests[3].form)['kspage'], '11');
      final submitted = Map.fromEntries(client.requests[5].form);
      expect(submitted['jxb_ids'], 'a+b/c==');
      expect(submitted['jcxx_id'], 'detail');
      expect(submitted['xkxqm'], '3');
      expect(submitted['kcmc'], '(course)算法');
      expect(
        client.requests.every(
          (request) => request.uri.queryParameters['gnmkdm'] == 'N-test',
        ),
        isTrue,
      );
      expect(
        client.requests
            .where((request) => request.uri.path.contains('_xkBcZy'))
            .length,
        1,
      );
      await expectLater(
        gateway.submit(
          context,
          course,
          CourseSection(
            roundKey: round.key,
            courseId: 'course',
            sectionId: 'class',
            name: '班次',
          ),
        ),
        throwsA(isA<SelectionException>()),
      );
      const parser = ZhengfangSelectionParser();
      expect(
        parser.parseSubmission('{"flag":"0","msg":"容量不足"}').status,
        SelectionSubmissionStatus.rejected,
      );
      expect(
        parser.parseSubmission('unrecognized').status,
        SelectionSubmissionStatus.unknown,
      );
      expect(client.replies, isEmpty);
      client.statusCode = 307;
      client.replies.add({'flag': '1'});
      expect(
        (await gateway.submit(context, course, section)).status,
        SelectionSubmissionStatus.unknown,
      );
    },
  );

  test('reports when the school is outside the selection period', () async {
    final client = _Client([
      '''<input type="hidden" id="sessionUserKey" value="student-fixture">
      <input type="hidden" id="iskxk" value="0">
      <p>对不起，当前不属于选课阶段，如有需要，请与管理员联系！</p>''',
    ]);
    final gateway = ZhengfangSelectionGateway(
      profile: SchoolConnection(
        name: '测试学校',
        baseUri: Uri.parse('https://jw.example.test/jwglxt/'),
      ),
      client: client,
      clock: () => DateTime.utc(2026, 9, 14),
      studentId: 'student-fixture',
    );

    await expectLater(
      gateway.readContext(),
      throwsA(
        isA<SelectionException>().having(
          (error) => error.code,
          'code',
          SelectionFailureCode.roundClosed,
        ),
      ),
    );
    expect(client.requests.single.uri.queryParameters['gnmkdm'], 'N253512');
  });
}

final class _Client implements AuthenticatedReadClient {
  _Client(this.replies);

  final List<Object?> replies;
  final List<AuthHttpRequest> requests = [];
  int statusCode = 200;

  @override
  Future<AuthHttpResponse> sendRead(AuthHttpRequest request) async {
    requests.add(request);
    final value = replies.removeAt(0);
    return AuthHttpResponse(
      uri: request.uri,
      statusCode: statusCode,
      body: utf8.encode(value is String ? value : jsonEncode(value)),
    );
  }
}
