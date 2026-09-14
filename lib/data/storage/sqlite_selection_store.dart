import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';
import 'package:zf_core/zf_core.dart';

import 'course_library_codec.dart';
import 'course_store.dart';

/// Course snapshots and operation history share one serial SQLite owner.
final class SqliteSelectionStore
    implements CourseStore, SelectionOperationStore {
  SqliteSelectionStore({required this._databasePath});

  final Future<String> Function() _databasePath;
  Future<void> _pending = Future<void>.value();
  String? _path;
  bool _closed = false;

  @override
  Future<CourseLibrary> read() => _enqueue(
    (path) async =>
        (await _runInWorker(path, _SelectionTable.courses, null))!
            as CourseLibrary,
  );

  @override
  Future<void> write(CourseLibrary library) => _enqueue((path) async {
    await _runInWorker(path, _SelectionTable.courses, library);
  });

  @override
  Future<List<SelectionOperation>> readOperations() => _enqueue(
    (path) async =>
        (await _runInWorker(path, _SelectionTable.operations, null))!
            as List<SelectionOperation>,
  );

  @override
  Future<void> writeOperations(List<SelectionOperation> operations) {
    final snapshot = List<SelectionOperation>.unmodifiable(operations);
    return _enqueue((path) async {
      await _runInWorker(path, _SelectionTable.operations, snapshot);
    });
  }

  Future<T> _enqueue<T>(Future<T> Function(String path) action) {
    if (_closed) {
      return Future.error(const SelectionStorageException('选课存储已关闭。'));
    }
    final result = Completer<T>();
    _pending = _pending.then((_) async {
      try {
        _path ??= await _resolvePath();
        result.complete(await action(_path!));
      } catch (error, stack) {
        // Report this failure without blocking the next explicitly requested IO.
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
        const SelectionStorageException('无法访问应用数据目录，选课数据未保存。'),
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

// SQL identifiers come only from these constants; payloads are bound parameters.
enum _SelectionTable {
  courses('course_library'),
  operations('selection_operations');

  const _SelectionTable(this.sqlName);
  final String sqlName;
}

const _schemaVersion = 1;
const _busyTimeoutMilliseconds = 5000;

Future<Object?> _runInWorker(
  String path,
  _SelectionTable table,
  Object? value,
) => Isolate.run(() => _execute(path, table, value));

Object? _execute(String path, _SelectionTable table, Object? value) {
  try {
    if (path.trim().isEmpty || path == ':memory:') {
      throw const SelectionStorageException('选课数据库需要有效的持久化文件路径。');
    }
    final payload = value == null ? null : _encode(table, value);
    File(path).parent.createSync(recursive: true);
    final database = sqlite3.open(path);
    try {
      database.execute('PRAGMA busy_timeout = $_busyTimeoutMilliseconds');
      _initialize(database);
      if (payload == null) return _read(database, table);
      database.execute('BEGIN IMMEDIATE');
      try {
        database.execute(
          'INSERT INTO ${table.sqlName} (id, payload) VALUES (1, ?) '
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
    throw const SelectionStorageException('选课本地数据读写失败，原数据已保留。');
  } on FileSystemException {
    throw const SelectionStorageException('无法访问选课数据库，请检查应用数据目录。');
  } on FormatException {
    throw const SelectionStorageException('选课缓存或操作记录格式无效，原数据已保留。');
  }
}

String _encode(_SelectionTable table, Object value) => switch ((table, value)) {
  (_SelectionTable.courses, final CourseLibrary library) =>
    CourseLibraryCodec.encode(library),
  (_SelectionTable.operations, final List<SelectionOperation> operations) =>
    SelectionOperationsCodec.encode(operations),
  _ => throw const FormatException('Invalid selection storage value.'),
};

Object _read(Database database, _SelectionTable table) {
  final rows = database.select(
    'SELECT payload FROM ${table.sqlName} WHERE id = 1',
  );
  if (rows.isEmpty) {
    return switch (table) {
      _SelectionTable.courses => CourseLibrary(),
      _SelectionTable.operations => const <SelectionOperation>[],
    };
  }
  if (rows.length != 1 || rows.single['payload'] is! String) {
    throw const FormatException('Invalid selection storage row.');
  }
  final payload = rows.single['payload'] as String;
  return switch (table) {
    _SelectionTable.courses => CourseLibraryCodec.decode(payload),
    _SelectionTable.operations => SelectionOperationsCodec.decode(payload),
  };
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
        throw const SelectionStorageException('选课数据库版本无法识别，原文件已保留。');
      }
      for (final table in _SelectionTable.values) {
        database.execute(
          'CREATE TABLE ${table.sqlName} ('
          'id INTEGER PRIMARY KEY CHECK(id = 1), payload TEXT NOT NULL) STRICT',
        );
      }
      database.userVersion = _schemaVersion;
    }
    database.execute('COMMIT');
  } finally {
    if (!database.autocommit) database.execute('ROLLBACK');
  }
}
