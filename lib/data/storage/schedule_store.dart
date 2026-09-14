import 'package:zf_core/zf_core.dart';

import 'academic_account.dart';

export 'academic_account.dart';

/// An account's imports and independently saved user changes.
final class StoredScheduleAccount {
  StoredScheduleAccount({
    required this.account,
    this.catalog,
    Map<String, ScheduleSnapshot> schedules = const {},
    Map<String, ScheduleSettings> settings = const {},
    this.selectedTermKey,
  }) : schedules = Map.unmodifiable(schedules),
       settings = Map.unmodifiable(settings);

  final AcademicAccountRecord account;
  final TermCatalog? catalog;
  final Map<String, ScheduleSnapshot> schedules;
  final Map<String, ScheduleSettings> settings;
  final String? selectedTermKey;
}

/// Persisted accounts in most recently selected or added order.
final class ScheduleLibrary {
  ScheduleLibrary({
    List<StoredScheduleAccount> accounts = const [],
    this.selectedAccount,
  }) : accounts = List.unmodifiable(accounts);

  final List<StoredScheduleAccount> accounts;
  final AccountScope? selectedAccount;
}

/// Durable schedule data without expiry or network side effects.
abstract interface class ScheduleStore {
  /// Reads saved data without changing its successful import timestamps.
  Future<ScheduleLibrary> read();

  /// Atomically replaces one account's complete record.
  ///
  /// Callers include the other terms and user settings they want to retain.
  /// With [select], this also selects the account in the same transaction.
  Future<void> saveAccount(
    StoredScheduleAccount account, {
    bool select = false,
  });

  /// Selects an existing account, failing when its record is missing.
  Future<void> selectAccount(AccountScope scope);

  /// Removes an account and all its imported and local schedule data.
  ///
  /// Removing the current account selects the most recently selected or added
  /// remaining account, or `null` if none remains. A missing account is a no-op.
  Future<void> removeAccount(AccountScope scope);

  /// Rejects new work and waits for already accepted operations to finish.
  ///
  /// Calling this again is safe. Errors from an earlier operation remain on
  /// that operation's future and are not reported as successful writes.
  Future<void> close();
}

/// A storage failure whose message never contains SQL parameters or payloads.
final class ScheduleStorageException implements Exception {
  const ScheduleStorageException({
    required this.operation,
    required this.message,
    this.sqliteCode,
    this.osErrorCode,
  });

  final String operation;
  final String message;
  final int? sqliteCode;
  final int? osErrorCode;

  @override
  String toString() => 'ScheduleStorageException($operation): $message';
}
