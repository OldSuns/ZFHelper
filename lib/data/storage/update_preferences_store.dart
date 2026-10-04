import 'dart:convert';
import 'dart:io';

/// Persisted lightweight state for the update checker. Not sensitive data:
/// plain JSON in the application support directory is sufficient.
final class UpdatePreferences {
  const UpdatePreferences({this.lastAutoCheckAt, this.lastNotifiedTag});

  final DateTime? lastAutoCheckAt;
  final String? lastNotifiedTag;

  static const UpdatePreferences empty = UpdatePreferences();
}

abstract interface class UpdatePreferencesStore {
  Future<UpdatePreferences> read();
  Future<void> write(UpdatePreferences preferences);
}

final class UpdatePreferencesStorageException implements Exception {
  const UpdatePreferencesStorageException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef UpdatePreferencesFilePath = Future<String> Function();

/// JSON-file backed store for update-check state. Corrupt or unreadable files
/// reset to [UpdatePreferences.empty]: auto-check runs again and a notice may
/// reappear, which is safer than blocking updates on preferences.
final class JsonFileUpdatePreferencesStore implements UpdatePreferencesStore {
  JsonFileUpdatePreferencesStore({required this.resolvePath});

  final UpdatePreferencesFilePath resolvePath;

  @override
  Future<UpdatePreferences> read() async {
    try {
      final file = File(await resolvePath());
      if (!await file.exists()) return UpdatePreferences.empty;
      final content = await file.readAsString();
      if (content.trim().isEmpty) return UpdatePreferences.empty;
      final Object? json;
      try {
        json = jsonDecode(content);
      } on FormatException {
        return UpdatePreferences.empty;
      }
      if (json is! Map) return UpdatePreferences.empty;
      final lastAutoCheckAt = json['lastAutoCheckAt'];
      final lastNotifiedTag = json['lastNotifiedTag'];
      if ((lastAutoCheckAt != null && lastAutoCheckAt is! int) ||
          (lastNotifiedTag != null && lastNotifiedTag is! String)) {
        return UpdatePreferences.empty;
      }
      return UpdatePreferences(
        lastAutoCheckAt: lastAutoCheckAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(lastAutoCheckAt as int),
        lastNotifiedTag: lastNotifiedTag as String?,
      );
    } on FileSystemException catch (error) {
      throw UpdatePreferencesStorageException(
        '更新检查状态读取失败（${error.osError?.errorCode ?? '未知'}）',
      );
    }
  }

  @override
  Future<void> write(UpdatePreferences preferences) async {
    try {
      final path = await resolvePath();
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode(<String, Object?>{
          if (preferences.lastAutoCheckAt != null)
            'lastAutoCheckAt':
                preferences.lastAutoCheckAt!.millisecondsSinceEpoch,
          if (preferences.lastNotifiedTag != null)
            'lastNotifiedTag': preferences.lastNotifiedTag,
        }),
        flush: true,
      );
    } on FileSystemException catch (error) {
      throw UpdatePreferencesStorageException(
        '更新检查状态保存失败（${error.osError?.errorCode ?? '未知'}）',
      );
    }
  }
}
