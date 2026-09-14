import '../auth/authenticated_read_client.dart';
import '../auth/login_models.dart';
import '../auth/school_connection.dart';
import '../grades/grade_parse_exception.dart';
import '../grades/grade_snapshot.dart';
import '../grades/zhengfang_grade_parser.dart';

/// Reads every reported grade page through the existing account session.
final class ZhengfangGradeGateway {
  ZhengfangGradeGateway({
    required this._profile,
    required this._client,
    required this._clock,
    this._studentId,
  });

  final SchoolConnection _profile;
  final AuthenticatedReadClient _client;
  final DateTime Function() _clock;
  final String? _studentId;
  static const _parser = ZhengfangGradeParser();
  static const _pageSize = 200;

  Future<GradeSnapshot> readGrades() async {
    final rows = <Map<String, Object?>>[];
    final pages = <String>{};
    int? totalRecords;
    String? observedStudentId;
    for (var number = 1; ; number++) {
      final page = await _readPage(number);
      if (totalRecords != null &&
          page.totalRecords != null &&
          totalRecords != page.totalRecords) {
        _incomplete('查询过程中学校的成绩总数发生变化，请重新查询');
      }
      if (observedStudentId != null &&
          page.studentId != null &&
          observedStudentId != page.studentId) {
        throw const GradeParseException(
          GradeParseCode.identityMismatch,
          '查询过程中学校返回的账号发生变化，未保存这次查询',
          field: 'xh',
        );
      }
      totalRecords ??= page.totalRecords;
      observedStudentId ??= page.studentId;
      if (page.rows.isNotEmpty && !pages.add(page.fingerprint)) {
        _incomplete('学校重复返回同一页成绩，未保存不完整的查询结果');
      }
      rows.addAll(page.rows);
      if (totalRecords != null && rows.length > totalRecords) {
        _incomplete('学校返回的成绩条数与分页信息不一致，请重新查询');
      }
      if (page.rows.isEmpty) {
        if (totalRecords != null && rows.length < totalRecords) {
          _incomplete('学校在成绩尚未取齐时返回了空页，请重新查询');
        }
        break;
      }
      if (totalRecords != null && rows.length == totalRecords) {
        break;
      }
      if (totalRecords == null && page.rows.length < _pageSize) {
        break;
      }
    }
    return GradeSnapshot(
      records: _parser.parseRecords(rows),
      fetchedAt: _clock(),
      sourceLabel: '${_profile.name}教务系统',
    );
  }

  Future<GradeQueryPage> _readPage(int number) async {
    final response = await _client.sendRead(
      AuthHttpRequest.form(
        _profile.gradeQueryUri,
        fields: [
          const MapEntry('xnm', ''),
          const MapEntry('xqm', ''),
          const MapEntry('queryModel.showCount', '$_pageSize'),
          MapEntry('queryModel.currentPage', '$number'),
          const MapEntry('queryModel.sortName', ''),
          const MapEntry('queryModel.sortOrder', 'asc'),
          const MapEntry('time', '0'),
        ],
        headers: {
          'Accept': 'application/json, text/javascript, */*; q=0.01',
          'X-Requested-With': 'XMLHttpRequest',
          'Origin': _profile.baseUri.origin,
          'Referer': _profile.gradePageUri.toString(),
        },
      ),
    );
    if (response.statusCode == 401) {
      throw const LoginFailure(LoginFailureCode.expired, '教务登录已失效，请重新登录后更新成绩');
    }
    if (response.statusCode == 429 || response.statusCode >= 500) {
      throw LoginFailure(
        LoginFailureCode.network,
        '学校暂时无法提供成绩查询（HTTP ${response.statusCode}），请稍后重试',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GradeParseException(
        GradeParseCode.schoolRejected,
        '学校未允许读取成绩（HTTP ${response.statusCode}）',
      );
    }
    final String text;
    try {
      text = response.text;
    } on FormatException {
      throw const GradeParseException(
        GradeParseCode.invalidResponse,
        '学校成绩响应的文字编码无法识别',
      );
    }
    return _parser.parsePage(text, expectedStudentId: _studentId);
  }
}

Never _incomplete(String message) =>
    throw GradeParseException(GradeParseCode.incompleteResponse, message);
