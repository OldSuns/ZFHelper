import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../auth/authenticated_read_client.dart';
import '../auth/login_models.dart';
import '../auth/school_connection.dart';
import '../schedule/academic_term.dart';
import '../schedule/schedule_parse_exception.dart';
import '../schedule/schedule_snapshot.dart';
import '../schedule/teaching_calendar.dart';
import '../schedule/zhengfang_schedule_parser.dart';

final class ScheduleImportResult {
  const ScheduleImportResult({this.catalog, this.snapshot});

  /// Absent when importing an explicitly selected term without reading a catalog.
  final TermCatalog? catalog;
  final ScheduleSnapshot? snapshot;
}

final class ZhengfangScheduleGateway {
  ZhengfangScheduleGateway({
    required this._profile,
    required this._client,
    required this._clock,
    this._studentId,
  });

  final SchoolConnection _profile;
  final AuthenticatedReadClient _client;
  final DateTime Function() _clock;
  final String? _studentId;
  static const _parser = ZhengfangScheduleParser();

  /// Reads the school's year/term selectors without importing a timetable.
  Future<TermCatalog> readTermCatalog() async {
    final termPage = await _readTermPage();
    return termPage.catalog;
  }

  Future<ScheduleImportResult> importSchedule({AcademicTerm? term}) async {
    AuthHttpResponse? page;
    TermCatalog? catalog;
    var selected = term;
    if (selected == null) {
      final termPage = await _readTermPage();
      page = termPage.page;
      catalog = termPage.catalog;
      selected = catalog.selectedTerm;
      if (selected == null) return ScheduleImportResult(catalog: catalog);
    }

    final document = page == null ? null : html.parse(page.text);
    // Follow the current zhengfang-apk reader: the configured timetable URL
    // receives xnm/xqm. School page scripts must not replace that working URL.
    final fields = <MapEntry<String, String>>[
      MapEntry('xnm', selected.yearCode),
      MapEntry('xqm', selected.termCode),
      if (_profile.scheduleQueryUri.path.endsWith('/xskbcx_cxXsgrkb.html')) ...[
        const MapEntry('kzlx', 'ck'),
        const MapEntry('xsdm', ''),
        const MapEntry('kclbdm', ''),
        const MapEntry('kclxdm', ''),
      ],
      ..._pageTokens(document),
    ];
    final response = await _read(
      AuthHttpRequest.form(
        _profile.scheduleQueryUri,
        fields: fields,
        headers: _queryHeaders,
      ),
    );
    var snapshot = _parser.parseSnapshot(
      response.text,
      term: selected,
      fetchedAt: _clock(),
      sourceLabel: '${_profile.name}教务系统',
      expectedStudentId: _studentId,
    );

    try {
      final times = await _periodTimes(
        snapshot,
        document,
        page?.uri ?? _profile.schedulePageUri,
      );
      snapshot = snapshot.copyWith(periodTimes: times);
    } on ScheduleParseException catch (error) {
      if (_profile.schedulePeriodsUri != null) rethrow;
      snapshot = snapshot.copyWith(
        importWarnings: ['课程已完整导入，自动读取学校作息失败：${error.message}。可在校历与作息中填写时间。'],
      );
    } on LoginFailure catch (error) {
      if (_profile.schedulePeriodsUri != null ||
          error.code != LoginFailureCode.network) {
        rethrow;
      }
      snapshot = snapshot.copyWith(
        importWarnings: ['课程已完整导入，读取学校作息时网络连接失败。可在校历与作息中填写时间。'],
      );
    }
    return ScheduleImportResult(catalog: catalog, snapshot: snapshot);
  }

  Future<({AuthHttpResponse page, TermCatalog catalog})> _readTermPage() async {
    final page = await _read(AuthHttpRequest.get(_profile.schedulePageUri));
    return (page: page, catalog: _parser.parseTermCatalog(page.text));
  }

  Future<List<PeriodTime>> _periodTimes(
    ScheduleSnapshot snapshot,
    Document? document,
    Uri pageUri,
  ) async {
    // An explicit term has already been queried. This optional page read is
    // only for clock metadata; missing HTML term controls cannot block it.
    final metadataPage = document == null && _profile.schedulePeriodsUri == null
        ? await _read(AuthHttpRequest.get(pageUri))
        : null;
    final metadataDocument =
        document ??
        (metadataPage == null ? null : html.parse(metadataPage.text));
    final periodsUri = await _periodsEndpoint(
      metadataDocument,
      metadataPage?.uri ?? pageUri,
    );
    final selected = snapshot.term;
    if (periodsUri != null) {
      final campuses = <String?, String?>{};
      for (final entry in snapshot.entries) {
        final id = entry.metadata['xqh_id'];
        if (id != null) campuses[id] = entry.campus ?? campuses[id];
      }
      if (campuses.isEmpty) {
        final field = metadataDocument?.querySelector(
          'input[name="xqh_id"], select[name="xqh_id"] option[selected]',
        );
        final id = field?.attributes['value'];
        campuses[id == null || id.isEmpty ? null : id] = null;
      }
      final times = <PeriodTime>[];
      for (final campus in campuses.entries) {
        final periods = await _read(
          AuthHttpRequest.form(
            periodsUri,
            fields: [
              MapEntry('xnm', selected.yearCode),
              MapEntry('xqm', selected.termCode),
              if (campus.key != null) MapEntry('xqh_id', campus.key!),
              ..._pageTokens(metadataDocument),
            ],
            headers: _queryHeaders,
          ),
        );
        times.addAll(
          _parser.parsePeriodTimes(periods.text, campus: campus.value),
        );
      }
      return times;
    }
    return const [];
  }

  Map<String, String> get _queryHeaders => {
    'Accept': 'application/json, text/javascript, */*; q=0.01',
    'X-Requested-With': 'XMLHttpRequest',
    'Origin': _profile.baseUri.origin,
    'Referer': _profile.schedulePageUri.toString(),
  };

  // Only copy authentication tokens required by the read form. Unrelated
  // controls on the school's page must not change the requested term or query.
  Iterable<MapEntry<String, String>> _pageTokens(Document? document) sync* {
    if (document == null) return;
    for (final name in const ['csrftoken', 'csrfToken', '_csrf', 'validate']) {
      final input = document.querySelector('input[name="$name"]');
      if (input == null || input.attributes.containsKey('disabled')) continue;
      final value = input.attributes['value'];
      if (value != null && value.isNotEmpty) yield MapEntry(name, value);
    }
  }

  Future<Uri?> _periodsEndpoint(Document? page, Uri pageUri) async {
    final configured = _profile.schedulePeriodsUri;
    if (configured != null) return configured;
    if (page == null) return null;
    final scripts = page
        .querySelectorAll('script[src]')
        .map((element) => pageUri.resolve(element.attributes['src']!))
        .where(
          (uri) =>
              uri.origin == _profile.baseUri.origin &&
              RegExp(r'/xskbcx(?:_v\d+)?\.js$').hasMatch(uri.path),
        );
    // Optional clock metadata is separate from the reference's course query.
    // Read only a declared same-school script and a documented read endpoint.
    for (final uri in scripts.toSet()) {
      final script = await _read(AuthHttpRequest.get(uri));
      if (RegExp(
        r'''\burl\s*:\s*_path\s*\+\s*['"]/kbcx/xskbcx_cxRjc\.html['"]''',
      ).hasMatch(script.text)) {
        return _endpoint('/kbcx/xskbcx_cxRjc.html');
      }
    }
    return null;
  }

  Uri _endpoint(String relativeToApplication) => _profile.baseUri
      .resolve(relativeToApplication.substring(1))
      .replace(
        queryParameters: _profile.schedulePageUri.queryParameters.isEmpty
            ? null
            : _profile.schedulePageUri.queryParameters,
      );

  Future<AuthHttpResponse> _read(AuthHttpRequest request) async {
    final response = await _client.sendRead(request);
    if (response.statusCode == 401) {
      throw const LoginFailure(LoginFailureCode.expired, '教务登录已过期，请重新连接');
    }
    if (response.statusCode != 200) {
      throw ScheduleParseException(
        ScheduleParseCode.schoolRejected,
        '学校未允许读取教务数据（HTTP ${response.statusCode}）',
      );
    }
    final text = response.text.trimLeft();
    if (text.startsWith('<')) {
      final document = html.parse(text);
      final loginForm = document.querySelector(
        'form[action*="login_slogin"], form[action*="cas/login"]',
      );
      final standardLogin =
          document.querySelector('input[name="yhm"]') != null &&
          document.querySelector('input[name="mm"]') != null;
      if (loginForm != null || standardLogin) {
        throw const LoginFailure(
          LoginFailureCode.expired,
          '学校返回了登录页面，请重新连接后更新课表',
        );
      }
    }
    return response;
  }
}
