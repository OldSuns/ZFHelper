import 'package:dio/dio.dart';

const githubRepositoryUrl = 'https://github.com/OldSuns/ZFHelper';
const _releasesApiUrl =
    'https://api.github.com/repos/OldSuns/ZFHelper/releases';

final class ReleaseInfo {
  const ReleaseInfo({
    required this.tagName,
    required this.name,
    required this.body,
    required this.publishedAt,
    required this.htmlUrl,
  });

  factory ReleaseInfo.fromJson(Map<String, Object?> json) {
    final tagName = json['tag_name'];
    final name = json['name'];
    final body = json['body'];
    final publishedAt = json['published_at'];
    final htmlUrl = json['html_url'];
    if (tagName is! String ||
        tagName.isEmpty ||
        (name != null && name is! String) ||
        (body != null && body is! String) ||
        publishedAt is! String ||
        htmlUrl is! String) {
      throw const FormatException('GitHub Release 响应缺少有效字段');
    }
    final published = DateTime.tryParse(publishedAt);
    final url = Uri.tryParse(htmlUrl);
    if (published == null ||
        url == null ||
        url.scheme != 'https' ||
        url.host != 'github.com') {
      throw const FormatException('GitHub Release 响应字段格式无效');
    }
    return ReleaseInfo(
      tagName: tagName,
      name: name as String? ?? tagName,
      body: body as String? ?? '',
      publishedAt: published.toLocal(),
      htmlUrl: url,
    );
  }

  final String tagName;
  final String name;
  final String body;
  final DateTime publishedAt;
  final Uri htmlUrl;
}

/// Returns a negative, zero, or positive value according to semantic version order.
int compareVersions(String left, String right) {
  final a = _versionParts(left);
  final b = _versionParts(right);
  for (var index = 0; index < a.length; index++) {
    final comparison = a[index].compareTo(b[index]);
    if (comparison != 0) return comparison;
  }
  return 0;
}

String releaseTagForVersion(String value) {
  final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:\+\d+)?$')
      .firstMatch(value.trim());
  if (match == null) throw FormatException('版本号格式无效：$value');
  return 'v${match.group(1)}.${match.group(2)}.${match.group(3)}';
}

List<int> _versionParts(String value) {
  final tag = releaseTagForVersion(value);
  final parts = tag.substring(1).split('.');
  return [for (final part in parts) int.parse(part)];
}

final class ReleaseRepository {
  ReleaseRepository({Dio? client}) : _client = client ?? Dio();

  final Dio _client;

  Future<ReleaseInfo> fetchLatest() => _fetch('latest');

  Future<ReleaseInfo> fetchByTag(String tag) =>
      _fetch('tags/${Uri.encodeComponent(tag)}');

  Future<ReleaseInfo> _fetch(String path) async {
    try {
      final response = await _client.get<Object?>(
        '$_releasesApiUrl/$path',
        options: Options(
          headers: const {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
          },
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          validateStatus: (_) => true,
        ),
      );
      if (response.statusCode != 200 || response.data is! Map) {
        throw ReleaseException(
          _statusMessage(response.statusCode),
          statusCode: response.statusCode,
        );
      }
      return ReleaseInfo.fromJson(
        Map<String, Object?>.from(response.data! as Map),
      );
    } on ReleaseException {
      rethrow;
    } on FormatException catch (error) {
      throw ReleaseException(error.message);
    } on DioException catch (error) {
      throw ReleaseException(_networkMessage(error));
    }
  }

  void dispose() => _client.close(force: true);

  static String _statusMessage(int? statusCode) =>
      releaseStatusMessage(statusCode);

  static String _networkMessage(DioException error) => switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.connectionError => '无法连接 GitHub，请检查网络后重试',
    _ => '读取 GitHub Release 失败，请稍后重试',
  };
}

String releaseStatusMessage(int? statusCode) => switch (statusCode) {
  403 => 'GitHub API 请求受限，请稍后重试（HTTP 403）',
  404 => 'GitHub 暂无可用的发布版本（HTTP 404）',
  final code? when code >= 500 => 'GitHub 服务暂时不可用，请稍后重试（HTTP $code）',
  _ => 'GitHub Release 请求失败（HTTP ${statusCode ?? '未知'}）',
};

final class ReleaseException implements Exception {
  const ReleaseException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
