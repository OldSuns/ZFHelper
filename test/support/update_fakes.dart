import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:zfhelper/data/repositories/release_repository.dart';
import 'package:zfhelper/platform/app_installer_platform.dart';

typedef ReleaseResponder = FutureOr<ResponseBody> Function(
  RequestOptions options,
);

final class RecordingReleaseAdapter implements HttpClientAdapter {
  RecordingReleaseAdapter(this.respond);

  final ReleaseResponder respond;
  final List<Uri> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.uri);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

final class ReleaseRepositoryHarness {
  ReleaseRepositoryHarness._(this.repository, this.adapter);

  final ReleaseRepository repository;
  final RecordingReleaseAdapter adapter;

  factory ReleaseRepositoryHarness({
    required ReleaseResponder respond,
    DownloadProbe? probe,
  }) {
    final adapter = RecordingReleaseAdapter(respond);
    return ReleaseRepositoryHarness._(
      ReleaseRepository(
        client: Dio()..httpClientAdapter = adapter,
        probe: probe,
      ),
      adapter,
    );
  }

  void dispose() => repository.dispose();
}

ResponseBody releaseJsonResponse(Map<String, Object?> json) =>
    ResponseBody.fromString(
      jsonEncode(json),
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );

ResponseBody downloadResponseOf(String text) => ResponseBody.fromBytes(
  utf8.encode(text),
  200,
  headers: {
    'content-type': ['application/octet-stream'],
  },
);

ResponseBody notFoundResponse() => ResponseBody.fromString(
  '{"message":"Not Found"}',
  404,
  headers: {
    'content-type': ['application/json'],
  },
);

Map<String, Object?> releaseJson({
  required String tag,
  String body = '修复课表显示问题',
  List<Map<String, Object?>> assets = const [],
}) => {
  'tag_name': tag,
  'name': '$tag 更新',
  'body': body,
  'published_at': '2026-09-01T12:00:00Z',
  'html_url': 'https://github.com/OldSuns/ZFHelper/releases/tag/$tag',
  'assets': assets,
};

Map<String, Object?> apkAssetJson(String tag) => {
  'name': 'zfhelper-$tag.apk',
  'browser_download_url':
      'https://github.com/OldSuns/ZFHelper/releases/download/$tag/zfhelper-$tag.apk',
};

final class FakeAppInstaller implements AppInstallerPlatform {
  final List<String> installRequests = [];

  /// When set, thrown by the next [installApk] call.
  AppInstallerException? failure;

  @override
  Future<void> installApk(String apkPath) async {
    installRequests.add(apkPath);
    final error = failure;
    if (error != null) throw error;
  }
}
