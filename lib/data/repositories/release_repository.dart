import 'dart:io';

import 'package:dio/dio.dart';

typedef DownloadProbe = Future<bool> Function(Uri url);
typedef DownloadProgressListener = void Function(int received, int total);

const githubRepositoryUrl = 'https://github.com/OldSuns/ZFHelper';
const _downloadMirrorPrefix = 'https://ghfast.top/';
const _releasesApiUrl =
    'https://api.github.com/repos/OldSuns/ZFHelper/releases';

final class ReleaseInfo {
  const ReleaseInfo({
    required this.tagName,
    required this.name,
    required this.body,
    required this.publishedAt,
    required this.htmlUrl,
    this.assets = const [],
  });

  factory ReleaseInfo.fromJson(Map<String, Object?> json) {
    final tagName = json['tag_name'];
    final name = json['name'];
    final body = json['body'];
    final publishedAt = json['published_at'];
    final htmlUrl = json['html_url'];
    final assets = json['assets'];
    if (tagName is! String ||
        tagName.isEmpty ||
        (name != null && name is! String) ||
        (body != null && body is! String) ||
        publishedAt is! String ||
        htmlUrl is! String ||
        (assets != null && assets is! List)) {
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
    final releaseAssets = assets is List ? assets : const <Object?>[];
    return ReleaseInfo(
      tagName: tagName,
      name: name as String? ?? tagName,
      body: body as String? ?? '',
      publishedAt: published.toLocal(),
      htmlUrl: url,
      assets: [for (final item in releaseAssets) ?ReleaseAsset.tryParse(item)],
    );
  }

  final String tagName;
  final String name;
  final String body;
  final DateTime publishedAt;
  final Uri htmlUrl;
  final List<ReleaseAsset> assets;

  ReleaseAsset? assetWithExtension(String extension) {
    final normalized = extension.toLowerCase();
    for (final asset in assets) {
      if (asset.name.toLowerCase().endsWith(normalized)) return asset;
    }
    return null;
  }
}

final class ReleaseAsset {
  const ReleaseAsset({required this.name, required this.url});

  static ReleaseAsset? tryParse(Object? value) {
    if (value is! Map) return null;
    final name = value['name'];
    final browserUrl = value['browser_download_url'];
    if (name is! String || name.isEmpty || browserUrl is! String) return null;
    // Asset names become download file names; reject anything that could
    // escape the download directory or trick path handling.
    if (name.contains('/') ||
        name.contains('\\') ||
        name == '.' ||
        name == '..' ||
        name.contains(RegExp(r'[\x00-\x1f]'))) {
      return null;
    }
    final url = Uri.tryParse(browserUrl);
    if (url == null ||
        url.scheme != 'https' ||
        url.host != 'github.com' ||
        !url.path.startsWith('/OldSuns/ZFHelper/releases/download/')) {
      return null;
    }
    return ReleaseAsset(name: name, url: url);
  }

  final String name;
  final Uri url;

  Uri get mirrorUrl => Uri.parse('$_downloadMirrorPrefix$url');
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
  ReleaseRepository({Dio? client, this._probe}) : _client = client ?? Dio();

  final Dio _client;
  final DownloadProbe? _probe;

  Future<ReleaseInfo> fetchLatest() => _fetch('latest');

  Future<ReleaseInfo> fetchByTag(String tag) =>
      _fetch('tags/${Uri.encodeComponent(tag)}');

  Future<Uri> resolveDownloadUrl(ReleaseAsset asset) async {
    if (await (_probe ?? _probeDownload)(asset.mirrorUrl)) {
      return asset.mirrorUrl;
    }
    return asset.url;
  }

  /// Downloads [asset] into [targetDirectory] under its asset name, using a
  /// `.part` temporary file and renaming only after a complete response.
  /// Falls back to the official GitHub URL when the mirror download fails.
  /// Returns the resulting file path.
  Future<String> downloadAsset(
    ReleaseAsset asset,
    String targetDirectory, {
    DownloadProgressListener? onProgress,
  }) async {
    final directory = Directory(targetDirectory);
    try {
      await directory.create(recursive: true);
    } on DioException {
      throw const ReleaseException('无法创建下载目录，请稍后重试');
    } on FileSystemException {
      throw const ReleaseException('无法创建下载目录，请稍后重试');
    }
    final target = File(
      '${directory.path}${Platform.pathSeparator}${asset.name}',
    );
    final temporary = File('${target.path}.part');
    final url = await resolveDownloadUrl(asset);
    final fallbackUrls = url == asset.mirrorUrl ? [asset.url] : <Uri>[];
    var downloaded = false;
    var lastError = const ReleaseException('下载失败，请稍后重试');
    for (final candidate in [url, ...fallbackUrls]) {
      try {
        // A mirror can answer a failed download with an HTML error page and
        // HTTP 200; reject that so the official URL gets a chance instead.
        final response = await _client.download(
          candidate.toString(),
          temporary.path,
          onReceiveProgress: onProgress,
          options: Options(
            // The mirror can fail mid-download with a truncated body too;
            // dio's download validation rejects non-2xx responses.
            validateStatus: (status) =>
                status != null && status >= 200 && status < 400,
            receiveTimeout: const Duration(minutes: 10),
          ),
        );
        final contentType =
            (response.headers.value(Headers.contentTypeHeader) ?? '')
                .toLowerCase();
        if (contentType.startsWith('text/html')) {
          throw const ReleaseException('下载返回了无效内容，请稍后重试');
        }
        downloaded = true;
        break;
      } on DioException catch (error) {
        lastError = ReleaseException(switch (error.type) {
          DioExceptionType.connectionTimeout ||
          DioExceptionType.sendTimeout ||
          DioExceptionType.receiveTimeout ||
          DioExceptionType.connectionError => '无法连接下载服务器，请检查网络后重试',
          DioExceptionType.badResponse =>
            '下载服务器返回错误（HTTP ${error.response?.statusCode ?? '未知'}），请稍后重试',
          _ => '下载失败，请稍后重试',
        });
      } on ReleaseException catch (error) {
        lastError = error;
      }
    }
    if (!downloaded) {
      await _deleteQuietly(temporary);
      throw lastError;
    }
    if (!await temporary.exists() || await temporary.length() == 0) {
      await _deleteQuietly(temporary);
      throw const ReleaseException('下载未能完成，请稍后重试');
    }
    try {
      if (await target.exists()) {
        await target.delete();
      }
      await temporary.rename(target.path);
    } on FileSystemException {
      await _deleteQuietly(temporary);
      throw const ReleaseException('下载文件保存失败，请稍后重试');
    }
    return target.path;
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // Best effort cleanup; the next download overwrites the .part file.
    }
  }

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

  Future<bool> _probeDownload(Uri url) async {
    try {
      final response = await _client.headUri<Object?>(
        url,
        options: Options(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
          followRedirects: true,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 400,
        ),
      );
      return response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 400 &&
          !(response.headers
                  .value(Headers.contentTypeHeader)
                  ?.toLowerCase()
                  .startsWith('text/html') ??
              false);
    } on DioException {
      return false;
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
