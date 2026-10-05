import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zfhelper/data/repositories/release_repository.dart';

void main() {
  test('normalizes application versions to release tags', () {
    expect(releaseTagForVersion('0.1.1+1'), 'v0.1.1');
    expect(releaseTagForVersion('v2.0.0'), 'v2.0.0');
  });

  test('compares release versions without build metadata', () {
    expect(compareVersions('v0.1.1', '0.1.1+1'), 0);
    expect(compareVersions('v0.2.0', '0.1.1'), greaterThan(0));
    expect(compareVersions('0.1.0', 'v0.1.1'), lessThan(0));
  });

  test('parses a GitHub release response', () {
    final release = ReleaseInfo.fromJson({
      'tag_name': 'v0.2.0',
      'name': '课程表改进',
      'body': '修复课表显示问题',
      'published_at': '2026-09-01T12:00:00Z',
      'html_url': 'https://github.com/OldSuns/ZFHelper/releases/tag/v0.2.0',
      'assets': [
        {
          'name': 'zfhelper-0.2.0.apk',
          'browser_download_url': 'https://github.com/OldSuns/ZFHelper/releases/download/v0.2.0/zfhelper-0.2.0.apk',
        },
        {
          'name': 'untrusted.apk',
          'browser_download_url':
              'https://downloads.example.test/untrusted.apk',
        },
        {
          'name': '../escape.apk',
          'browser_download_url': 'https://github.com/OldSuns/ZFHelper/releases/download/v0.2.0/escape.apk',
        },
        {
          'name': 'nested/path.apk',
          'browser_download_url': 'https://github.com/OldSuns/ZFHelper/releases/download/v0.2.0/path.apk',
        },
      ],
    });

    expect(release.tagName, 'v0.2.0');
    expect(release.name, '课程表改进');
    expect(release.body, '修复课表显示问题');
    expect(release.htmlUrl.host, 'github.com');
    final asset = release.assetWithExtension('.apk');
    expect(asset, isNotNull);
    expect(
      asset!.mirrorUrl.toString(),
      'https://ghfast.top/https://github.com/OldSuns/ZFHelper/releases/download/v0.2.0/zfhelper-0.2.0.apk',
    );
    expect(release.assets, hasLength(1));
  });

  test(
    'falls back to the official asset when the mirror probe fails',
    () async {
      final asset = ReleaseAsset(
        name: 'zfhelper-test.apk',
        url: Uri.parse(
          'https://github.com/OldSuns/ZFHelper/releases/download/v0.0.0/zfhelper-test.apk',
        ),
      );
      final repository = ReleaseRepository(probe: (_) async => false);
      addTearDown(repository.dispose);

      expect(await repository.resolveDownloadUrl(asset), asset.url);
    },
  );

  test('uses the mirror when the mirror probe succeeds', () async {
    final asset = ReleaseAsset(
      name: 'zfhelper-test.apk',
      url: Uri.parse(
        'https://github.com/OldSuns/ZFHelper/releases/download/v0.0.0/zfhelper-test.apk',
      ),
    );
    final repository = ReleaseRepository(probe: (_) async => true);
    addTearDown(repository.dispose);

    expect(await repository.resolveDownloadUrl(asset), asset.mirrorUrl);
  });

  test('maps GitHub status codes to distinct messages', () {
    expect(releaseStatusMessage(403), contains('请求受限'));
    expect(releaseStatusMessage(404), contains('暂无可用的发布版本'));
    expect(releaseStatusMessage(503), contains('服务暂时不可用'));
    expect(releaseStatusMessage(null), contains('请求失败'));
  });

  test('rejects malformed version and release data', () {
    expect(() => compareVersions('latest', '0.1.0'), throwsFormatException);
    expect(
      () => ReleaseInfo.fromJson({'tag_name': 'v0.2.0'}),
      throwsFormatException,
    );
  });

  test('downloads through the mirror and reports progress', () async {
    final temporary = Directory.systemTemp.createTempSync('zfhelper-dl-');
    addTearDown(() => temporary.deleteSync(recursive: true));
    final asset = ReleaseAsset(
      name: 'zfhelper-test.apk',
      url: Uri.parse(
        'https://github.com/OldSuns/ZFHelper/releases/download/v0.0.0/zfhelper-test.apk',
      ),
    );
    final requests = <Uri>[];
    final adapter = _RecordingAdapter((options) {
      requests.add(options.uri);
      return _responseOf('mirror-bytes');
    });
    final repository = ReleaseRepository(
      client: Dio()..httpClientAdapter = adapter,
      probe: (_) async => true,
    );
    addTearDown(repository.dispose);
    final progress = <(int, int)>[];

    final path = await repository.downloadAsset(
      asset,
      temporary.path,
      onProgress: (received, total) => progress.add((received, total)),
    );

    expect(requests, [asset.mirrorUrl]);
    expect(File(path).readAsStringSync(), 'mirror-bytes');
    expect(File(path).uri.pathSegments.last, 'zfhelper-test.apk');
    expect(
      temporary.listSync().map((entry) => entry.uri.pathSegments.last).single,
      'zfhelper-test.apk',
    );
    expect(progress, isNotEmpty);
    expect(progress.last.$1, 'mirror-bytes'.length);
  });

  test(
    'falls back to the official url when the mirror download fails',
    () async {
      final temporary = Directory.systemTemp.createTempSync('zfhelper-dl-');
      addTearDown(() => temporary.deleteSync(recursive: true));
      final asset = ReleaseAsset(
        name: 'zfhelper-test.apk',
        url: Uri.parse(
          'https://github.com/OldSuns/ZFHelper/releases/download/v0.0.0/zfhelper-test.apk',
        ),
      );
      final requests = <Uri>[];
      final adapter = _RecordingAdapter((options) {
        requests.add(options.uri);
        if (options.uri == asset.mirrorUrl) {
          throw DioException.connectionError(
            requestOptions: options,
            reason: 'mirror unavailable',
          );
        }
        return _responseOf('github-bytes');
      });
      final repository = ReleaseRepository(
        client: Dio()..httpClientAdapter = adapter,
        probe: (_) async => true,
      );
      addTearDown(repository.dispose);

      final path = await repository.downloadAsset(asset, temporary.path);

      expect(requests, [asset.mirrorUrl, asset.url]);
      expect(File(path).readAsStringSync(), 'github-bytes');
    },
  );

  test(
    'cleans up partial files and reports failure when all urls fail',
    () async {
      final temporary = Directory.systemTemp.createTempSync('zfhelper-dl-');
      addTearDown(() => temporary.deleteSync(recursive: true));
      final asset = ReleaseAsset(
        name: 'zfhelper-test.apk',
        url: Uri.parse(
          'https://github.com/OldSuns/ZFHelper/releases/download/v0.0.0/zfhelper-test.apk',
        ),
      );
      final adapter = _RecordingAdapter((options) {
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'network down',
        );
      });
      final repository = ReleaseRepository(
        client: Dio()..httpClientAdapter = adapter,
        probe: (_) async => false,
      );
      addTearDown(repository.dispose);

      await expectLater(
        repository.downloadAsset(asset, temporary.path),
        throwsA(
          isA<ReleaseException>().having(
            (error) => error.message,
            'message',
            contains('无法连接下载服务器'),
          ),
        ),
      );
      expect(temporary.listSync(), isEmpty);
    },
  );

  test(
    'rejects mirror HTML error pages and falls back to the official url',
    () async {
      final temporary = Directory.systemTemp.createTempSync('zfhelper-dl-');
      addTearDown(() => temporary.deleteSync(recursive: true));
      final asset = ReleaseAsset(
        name: 'zfhelper-test.apk',
        url: Uri.parse(
          'https://github.com/OldSuns/ZFHelper/releases/download/v0.0.0/zfhelper-test.apk',
        ),
      );
      final requests = <Uri>[];
      final adapter = _RecordingAdapter((options) {
        requests.add(options.uri);
        if (options.uri == asset.mirrorUrl) {
          return ResponseBody.fromString(
            '<html>rate limited</html>',
            200,
            headers: {
              'content-type': ['text/html'],
            },
          );
        }
        return _responseOf('github-bytes');
      });
      final repository = ReleaseRepository(
        client: Dio()..httpClientAdapter = adapter,
        probe: (_) async => true,
      );
      addTearDown(repository.dispose);

      final path = await repository.downloadAsset(asset, temporary.path);

      expect(requests, [asset.mirrorUrl, asset.url]);
      expect(File(path).readAsStringSync(), 'github-bytes');
    },
  );
}

typedef _Responder = FutureOr<ResponseBody> Function(RequestOptions options);

final class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.respond);

  final _Responder respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => respond(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _responseOf(String text) => ResponseBody.fromBytes(
  utf8.encode(text),
  200,
  headers: {
    'content-type': ['application/octet-stream'],
  },
);
