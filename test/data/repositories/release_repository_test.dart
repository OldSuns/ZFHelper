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
    });

    expect(release.tagName, 'v0.2.0');
    expect(release.name, '课程表改进');
    expect(release.body, '修复课表显示问题');
    expect(release.htmlUrl.host, 'github.com');
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
