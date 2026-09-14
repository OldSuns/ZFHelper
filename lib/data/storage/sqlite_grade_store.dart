import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';

import 'grade_library_codec.dart';
import 'grade_store.dart';

/// One atomic grade library in an application-private SQLite file.
final class SqliteGradeStore implements GradeStore {
  SqliteGradeStore({required this._databasePath});

  final Future<String> Function() _databasePath;
  String? _path;
  Future<void> _pending = Future.value();
  bool _closed = false;

  @override
  Future<GradeLibrary> read() async => (await _enqueue(null))!;

  @override
  Future<void> write(GradeLibrary library) async {
    await _enqueue(library);
  }

  Future<GradeLibrary?> _enqueue(GradeLibrary? library) {
    if (_closed) return Future.error(const GradeStorageException('成绩存储已关闭。'));
    final result = Completer<GradeLibrary?>();
    _pending = _pending.then((_) async {
      try {
        _path ??= await _resolvePath();
        result.complete(await _runInWorker(_path!, library));
      } catch (error, stack) {
        // Deliver failure to its caller while keeping explicit retries possible.
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Future<String> _resolvePath() async {
    try {
      return await _databasePath();
    } on Exception catch (_, stack) {
      Error.throwWithStackTrace(
        const GradeStorageException('无法访问应用数据目录，成绩未保存。'),
        stack,
      );
    }
  }

  @override
  Future<void> close() {
    _closed = true;
    return _pending;
  }
}

const _schemaVersion = 1;
const _busyTimeoutMilliseconds = 5000;

Future<GradeLibrary?> _runInWorker(String path, GradeLibrary? library) =>
    Isolate.run(() => _execute(path, library));

GradeLibrary? _execute(String path, GradeLibrary? library) {
  try {
    if (path.trim().isEmpty || path == ':memory:') {
      throw const GradeStorageException('成绩数据库需要有效的持久化文件路径。');
    }
    File(path).parent.createSync(recursive: true);
    final database = sqlite3.open(path);
    try {
      database.execute('PRAGMA busy_timeout = $_busyTimeoutMilliseconds');
      _initialize(database);
      if (library == null) {
        final rows = database.select(
          'SELECT payload FROM grade_library WHERE id = 1',
        );
        return rows.isEmpty
            ? GradeLibrary()
            : GradeLibraryCodec.decode(rows.single['payload'] as String);
      }
      final payload = GradeLibraryCodec.encode(library);
      database.execute('BEGIN IMMEDIATE');
      try {
        database.execute(
          'INSERT INTO grade_library (id, payload) VALUES (1, ?) '
          'ON CONFLICT (id) DO UPDATE SET payload = excluded.payload',
          [payload],
        );
        database.execute('COMMIT');
      } finally {
        if (!database.autocommit) database.execute('ROLLBACK');
      }
      return null;
    } finally {
      database.close();
    }
  } on SqliteException {
    throw const GradeStorageException('成绩本地数据读写失败，原数据已保留。');
  } on FileSystemException {
    throw const GradeStorageException('无法访问成绩数据库，请检查应用数据目录。');
  } on FormatException {
    throw const GradeStorageException('本地成绩数据格式无效，原数据已保留。');
  }
}

void _initialize(Database database) {
  if (database.userVersion == _schemaVersion) return;
  database.execute('BEGIN IMMEDIATE');
  try {
    final version = database.userVersion;
    if (version != _schemaVersion) {
      if (version != 0 ||
          database
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' "
                "AND name NOT LIKE 'sqlite_%'",
              )
              .isNotEmpty) {
        throw const GradeStorageException('成绩数据库版本无法识别，原文件已保留。');
      }
      database.execute(
        'CREATE TABLE grade_library ('
        'id INTEGER PRIMARY KEY CHECK(id = 1), payload TEXT NOT NULL) STRICT',
      );
      database.userVersion = _schemaVersion;
    }
    database.execute('COMMIT');
  } finally {
    if (!database.autocommit) database.execute('ROLLBACK');
  }
}
