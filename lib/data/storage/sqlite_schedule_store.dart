import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';
import 'package:zf_core/zf_core.dart';

import 'schedule_store.dart';

/// Stores account records in SQLite using short-lived background isolates.
final class SqliteScheduleStore implements ScheduleStore {
  SqliteScheduleStore({required Future<String> Function() databasePath})
    : _resolveDatabasePath = databasePath;

  final Future<String> Function() _resolveDatabasePath;
  Future<void> _pending = Future<void>.value();
  String? _databasePath;
  bool _closed = false;

  @override
  Future<ScheduleLibrary> read() async {
    final library = await _enqueue(const _ReadLibrary());
    return library!;
  }

  @override
  Future<void> saveAccount(
    StoredScheduleAccount account, {
    bool select = false,
  }) async {
    await _enqueue(_SaveAccount(account, select: select));
  }

  @override
  Future<void> selectAccount(AccountScope? scope) async {
    await _enqueue(_SelectAccount(scope));
  }

  @override
  Future<void> removeAccount(AccountScope scope) async {
    await _enqueue(_RemoveAccount(scope));
  }

  @override
  Future<void> close() {
    _closed = true;
    return _pending;
  }

  Future<ScheduleLibrary?> _enqueue(_StoreCommand command) {
    if (_closed) {
      return Future.error(
        ScheduleStorageException(
          operation: command.operation,
          message: '课表存储已关闭。',
        ),
      );
    }
    final result = Completer<ScheduleLibrary?>();
    _pending = _pending.then((_) async {
      try {
        final path = await _path();
        result.complete(await _runInWorker(path, command));
      } catch (error, stackTrace) {
        // Each caller receives its error; one failed operation must not poison
        // the queue and prevent a subsequent explicit retry.
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  Future<String> _path() async {
    final saved = _databasePath;
    if (saved != null) return saved;
    try {
      final resolved = await _resolveDatabasePath();
      _databasePath = resolved;
      return resolved;
    } on ScheduleStorageException {
      rethrow;
    } on FileSystemException catch (error) {
      throw _fileError('resolvePath', error);
    } on Exception catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const ScheduleStorageException(
          operation: 'resolvePath',
          message: '无法取得应用数据目录，课表存储不可用。',
        ),
        stackTrace,
      );
    }
  }
}

const _schemaVersion = 1;
const _busyTimeoutMilliseconds = 5000;

sealed class _StoreCommand {
  const _StoreCommand();

  String get operation;
}

final class _ReadLibrary extends _StoreCommand {
  const _ReadLibrary();

  @override
  String get operation => 'read';
}

final class _SaveAccount extends _StoreCommand {
  const _SaveAccount(this.account, {required this.select});

  final StoredScheduleAccount account;
  final bool select;

  @override
  String get operation => 'saveAccount';
}

final class _SelectAccount extends _StoreCommand {
  const _SelectAccount(this.scope);

  final AccountScope? scope;

  @override
  String get operation => 'selectAccount';
}

final class _RemoveAccount extends _StoreCommand {
  const _RemoveAccount(this.scope);

  final AccountScope scope;

  @override
  String get operation => 'removeAccount';
}

// Keep this closure outside the store instance so the isolate only receives
// its immutable command and path, never the queue or platform path resolver.
Future<ScheduleLibrary?> _runInWorker(String path, _StoreCommand command) =>
    Isolate.run(() => _executeCommand(path, command));

ScheduleLibrary? _executeCommand(String path, _StoreCommand command) {
  try {
    if (path.trim().isEmpty || path == ':memory:') {
      throw ScheduleStorageException(
        operation: command.operation,
        message: '课表数据库需要有效的持久化文件路径。',
      );
    }
    File(path).parent.createSync(recursive: true);
    final database = sqlite3.open(path);
    try {
      database.execute('PRAGMA foreign_keys = ON');
      database.execute('PRAGMA busy_timeout = $_busyTimeoutMilliseconds');
      _initializeSchema(database);
      return _transaction(database, () {
        switch (command) {
          case _ReadLibrary():
            return _readLibrary(database);
          case _SaveAccount(:final account, :final select):
            _saveAccount(database, account, select: select);
          case _SelectAccount(:final scope):
            _selectAccount(database, scope);
          case _RemoveAccount(:final scope):
            _removeAccount(database, scope);
        }
        return null;
      }, write: command is! _ReadLibrary);
    } finally {
      database.close();
    }
  } on SqliteException catch (error) {
    throw ScheduleStorageException(
      operation: command.operation,
      message: '课表本地数据读写失败，请重试。',
      sqliteCode: error.extendedResultCode,
    );
  } on FileSystemException catch (error) {
    throw _fileError(command.operation, error);
  } on FormatException {
    throw ScheduleStorageException(
      operation: command.operation,
      message: '本地课表数据格式无效，原数据已保留。',
    );
  }
}

ScheduleStorageException _fileError(
  String operation,
  FileSystemException error,
) => ScheduleStorageException(
  operation: operation,
  message: '无法访问课表数据库文件，请检查应用数据目录。',
  osErrorCode: error.osError?.errorCode,
);

T _transaction<T>(Database database, T Function() action, {bool write = true}) {
  database.execute(write ? 'BEGIN IMMEDIATE' : 'BEGIN');
  try {
    final result = action();
    database.execute('COMMIT');
    return result;
  } finally {
    if (!database.autocommit) database.execute('ROLLBACK');
  }
}

void _initializeSchema(Database database) {
  final version = database.userVersion;
  if (version == _schemaVersion) return;
  if (version != 0) _unsupportedVersion();

  _transaction(database, () {
    // Another store can create the file between open and BEGIN IMMEDIATE.
    final lockedVersion = database.userVersion;
    if (lockedVersion == _schemaVersion) return;
    if (lockedVersion != 0) _unsupportedVersion();
    final tables = database.select(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%'",
    );
    if (tables.isNotEmpty) {
      throw const ScheduleStorageException(
        operation: 'migrate',
        message: '课表数据库缺少版本信息，原文件已保留。',
      );
    }
    database.execute('''
      CREATE TABLE schedule_accounts (
        school_id TEXT NOT NULL,
        account_id TEXT NOT NULL,
        school_name TEXT NOT NULL,
        account_name TEXT NOT NULL,
        login_name TEXT NOT NULL,
        catalog_payload TEXT,
        schedules_payload TEXT NOT NULL,
        settings_payload TEXT NOT NULL,
        selected_term_key TEXT,
        access_order INTEGER NOT NULL CHECK(access_order > 0),
        PRIMARY KEY (school_id, account_id)
      ) STRICT
    ''');
    database.execute('''
      CREATE TABLE schedule_metadata (
        id INTEGER PRIMARY KEY CHECK(id = 1),
        selected_school_id TEXT,
        selected_account_id TEXT,
        next_access_order INTEGER NOT NULL CHECK(next_access_order > 0),
        CHECK ((selected_school_id IS NULL) = (selected_account_id IS NULL)),
        FOREIGN KEY (selected_school_id, selected_account_id)
          REFERENCES schedule_accounts (school_id, account_id)
          ON DELETE SET NULL
      ) STRICT
    ''');
    database.execute(
      'INSERT INTO schedule_metadata (id, next_access_order) VALUES (1, 1)',
    );
    database.userVersion = _schemaVersion;
  });
}

Never _unsupportedVersion() => throw const ScheduleStorageException(
  operation: 'migrate',
  message: '当前程序不支持此课表数据库版本，原文件已保留。',
);

ScheduleLibrary _readLibrary(Database database) {
  final accounts = database
      .select('SELECT * FROM schedule_accounts ORDER BY access_order DESC')
      .map(_decodeAccount)
      .toList();
  final scope = _selectedScope(database);
  if (scope != null && !accounts.any((item) => item.account.scope == scope)) {
    throw const FormatException('Selected account is missing.');
  }
  return ScheduleLibrary(accounts: accounts, selectedAccount: scope);
}

StoredScheduleAccount _decodeAccount(Row row) {
  final catalog = _optionalString(row['catalog_payload']);
  final account = StoredScheduleAccount(
    account: AcademicAccountRecord(
      scope: AccountScope(
        schoolId: _string(row['school_id']),
        accountId: _string(row['account_id']),
      ),
      schoolName: _string(row['school_name']),
      accountName: _string(row['account_name']),
      loginName: _string(row['login_name']),
    ),
    catalog: catalog == null ? null : TermCatalogCodec.decode(catalog),
    schedules: _decodeItems(
      _string(row['schedules_payload']),
      ScheduleSnapshotCodec.decode,
    ),
    settings: _decodeItems(
      _string(row['settings_payload']),
      ScheduleSettingsCodec.decode,
    ),
    selectedTermKey: _optionalString(row['selected_term_key']),
  );
  _validateAccount(account);
  return account;
}

void _saveAccount(
  Database database,
  StoredScheduleAccount stored, {
  required bool select,
}) {
  _validateAccount(stored);
  final account = stored.account;
  final previous = database.select(
    'SELECT access_order FROM schedule_accounts '
    'WHERE school_id = ? AND account_id = ?',
    [account.scope.schoolId, account.scope.accountId],
  );
  final accessOrder = select || previous.isEmpty
      ? _nextAccessOrder(database)
      : previous.single['access_order'] as int;
  database.execute(
    '''
    INSERT INTO schedule_accounts (
      school_id, account_id, school_name, account_name, login_name,
      catalog_payload, schedules_payload, settings_payload,
      selected_term_key, access_order
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT (school_id, account_id) DO UPDATE SET
      school_name = excluded.school_name,
      account_name = excluded.account_name,
      login_name = excluded.login_name,
      catalog_payload = excluded.catalog_payload,
      schedules_payload = excluded.schedules_payload,
      settings_payload = excluded.settings_payload,
      selected_term_key = excluded.selected_term_key,
      access_order = excluded.access_order
    ''',
    [
      account.scope.schoolId,
      account.scope.accountId,
      account.schoolName,
      account.accountName,
      account.loginName,
      stored.catalog == null ? null : TermCatalogCodec.encode(stored.catalog!),
      _encodeItems(stored.schedules, ScheduleSnapshotCodec.encode),
      _encodeItems(stored.settings, ScheduleSettingsCodec.encode),
      stored.selectedTermKey,
      accessOrder,
    ],
  );
  if (select) _setSelectedScope(database, account.scope);
}

void _selectAccount(Database database, AccountScope? scope) {
  if (scope == null) {
    _setSelectedScope(database, null);
    return;
  }
  _validateScope(scope);
  final existing = database.select(
    'SELECT 1 FROM schedule_accounts WHERE school_id = ? AND account_id = ?',
    [scope.schoolId, scope.accountId],
  );
  if (existing.isEmpty) {
    throw const ScheduleStorageException(
      operation: 'selectAccount',
      message: '该账号没有本地课表记录。',
    );
  }
  database.execute(
    'UPDATE schedule_accounts SET access_order = ? '
    'WHERE school_id = ? AND account_id = ?',
    [_nextAccessOrder(database), scope.schoolId, scope.accountId],
  );
  _setSelectedScope(database, scope);
}

void _removeAccount(Database database, AccountScope scope) {
  _validateScope(scope);
  final wasSelected = _selectedScope(database) == scope;
  database.execute(
    'DELETE FROM schedule_accounts WHERE school_id = ? AND account_id = ?',
    [scope.schoolId, scope.accountId],
  );
  if (!wasSelected) return;
  final remaining = database.select(
    'SELECT school_id, account_id FROM schedule_accounts '
    'ORDER BY access_order DESC LIMIT 1',
  );
  if (remaining.isEmpty) return;
  final row = remaining.single;
  _selectAccount(
    database,
    AccountScope(
      schoolId: _string(row['school_id']),
      accountId: _string(row['account_id']),
    ),
  );
}

AccountScope? _selectedScope(Database database) {
  final rows = database.select(
    'SELECT selected_school_id, selected_account_id '
    'FROM schedule_metadata WHERE id = 1',
  );
  if (rows.length != 1) {
    throw const FormatException('Missing schedule metadata.');
  }
  final schoolId = _optionalString(rows.single['selected_school_id']);
  final accountId = _optionalString(rows.single['selected_account_id']);
  if (schoolId == null && accountId == null) return null;
  if (schoolId == null || accountId == null) {
    throw const FormatException('Invalid selected account.');
  }
  return AccountScope(schoolId: schoolId, accountId: accountId);
}

void _setSelectedScope(Database database, AccountScope? scope) {
  database.execute(
    'UPDATE schedule_metadata SET selected_school_id = ?, '
    'selected_account_id = ? WHERE id = 1',
    [scope?.schoolId, scope?.accountId],
  );
}

int _nextAccessOrder(Database database) {
  final rows = database.select(
    'SELECT next_access_order FROM schedule_metadata WHERE id = 1',
  );
  if (rows.length != 1 || rows.single['next_access_order'] is! int) {
    throw const FormatException('Invalid schedule access order.');
  }
  final order = rows.single['next_access_order'] as int;
  if (order <= 0) {
    throw const FormatException('Invalid schedule access order.');
  }
  database.execute(
    'UPDATE schedule_metadata SET next_access_order = ? WHERE id = 1',
    [order + 1],
  );
  return order;
}

String _encodeItems<T>(Map<String, T> items, String Function(T) encode) =>
    jsonEncode({
      for (final entry in items.entries)
        entry.key: jsonDecode(encode(entry.value)),
    });

Map<String, T> _decodeItems<T>(String payload, T Function(String) decode) {
  final value = jsonDecode(payload);
  if (value is! Map<String, Object?>) {
    throw const FormatException('Invalid schedule map.');
  }
  return {
    for (final entry in value.entries)
      _string(entry.key): decode(jsonEncode(entry.value)),
  };
}

void _validateAccount(StoredScheduleAccount stored) {
  _validateScope(stored.account.scope);
  _string(stored.account.schoolName);
  _string(stored.account.accountName);
  _string(stored.account.loginName);
  for (final entry in stored.schedules.entries) {
    if (_string(entry.key) != entry.value.term.key) {
      throw const FormatException('Schedule key does not match its term.');
    }
  }
  for (final key in stored.settings.keys) {
    _string(key);
  }
  final selected = stored.selectedTermKey;
  if (selected == null) return;
  _string(selected);
  if (!stored.schedules.containsKey(selected) &&
      !stored.settings.containsKey(selected) &&
      !(stored.catalog?.terms.any((term) => term.key == selected) ?? false)) {
    throw const FormatException('Selected term is missing.');
  }
}

void _validateScope(AccountScope scope) {
  _string(scope.schoolId);
  _string(scope.accountId);
}

String _string(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Invalid saved schedule field.');
  }
  return value;
}

String? _optionalString(Object? value) => value == null ? null : _string(value);
