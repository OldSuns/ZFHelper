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
}
