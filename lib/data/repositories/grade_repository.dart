import 'dart:async';

import 'package:zf_core/zf_core.dart';

import '../storage/academic_account.dart';
import '../storage/grade_store.dart';
import 'academic_source.dart';
import 'grade_source.dart';

enum GradeFailureKind { authentication, network, protocol, storage }

final class GradeFailure {
  const GradeFailure(this.kind, this.message);
  final GradeFailureKind kind;
  final String message;
}

final class GradeRepositoryState {
  const GradeRepositoryState({
    required this.library,
    this.initialized = false,
    this.loading = false,
    this.refreshing = false,
    this.failure,
  });

  final GradeLibrary library;
  final bool initialized;
  final bool loading;
  final bool refreshing;
  final GradeFailure? failure;

  StoredGradeAccount? get account => library.accounts
      .where((item) => item.account.scope == library.selectedAccount)
      .firstOrNull;
  GradeSnapshot? get snapshot => account?.snapshot;
}

/// Owns complete grade snapshots; filtering never creates another cache copy.
final class GradeRepository {
  GradeRepository({required this._store, required this._source}) {
    _subscription = _source.accountChanges.listen(_onAccountChanged);
  }

  final GradeStore _store;
  final GradeSource _source;
  final _changes = StreamController<GradeRepositoryState>.broadcast(sync: true);
  late final StreamSubscription<AcademicAccountChange> _subscription;
  GradeLibrary _library = GradeLibrary();
  bool _loading = true;
  bool _refreshing = false;
  bool _initialized = false;
  bool _closed = false;
  int _readGeneration = 0;
  GradeFailure? _failure;
  final _accountChanges = PendingAcademicAccountChanges();
  Future<void>? _initializing;
  Future<void> _writes = Future.value();

  GradeRepositoryState get state => GradeRepositoryState(
    library: _library,
    initialized: _initialized,
    loading: _loading,
    refreshing: _refreshing,
    failure: _failure,
  );
  Stream<GradeRepositoryState> get changes => _changes.stream;

  bool canRefresh(AccountScope scope) =>
      _source.connectedAccount?.scope == scope;

  Future<void> initialize() {
    if (_closed || _initialized) return Future.value();
    // Share only the in-flight attempt; a failed attempt must remain retryable.
    return _initializing ??= Future<void>.microtask(_initialize)
        .whenComplete(() => _initializing = null);
  }

  Future<void> _initialize() async {
    _loading = true;
    _failure = null;
    _emit();
    try {
      await _writes;
      if (_closed) return;
      _library = await _store.read();
      if (_closed) return;
      final connected = _source.connectedAccount;
      if (_accountChanges.isEmpty && connected != null) {
        await _applyAccountChange(
          AcademicAccountChange(
            connected,
            selectForViewing: _library.selectedAccount == null,
          ),
        );
      }
      await _accountChanges.drain(_applyAccountChange);
      if (!_closed) _initialized = true;
    } on GradeStorageException catch (error) {
      _failure = GradeFailure(GradeFailureKind.storage, error.message);
    } finally {
      _loading = false;
      _emit();
    }
  }

  Future<void> retryLocalLoad() async {
    if (_loading || _closed) return;
    _cancelRead();
    _initialized = false;
    _loading = true;
    _emit();
    await initialize();
  }

  Future<bool> refresh() async {
    await initialize();
    if (!_initialized || _closed || _refreshing) return false;
    final stored = state.account;
    if (stored == null) return false;
    final scope = stored.account.scope;
    final generation = ++_readGeneration;
    _refreshing = true;
    _failure = null;
    _emit();
    try {
      final session = _source.open(scope);
      final snapshot = await session.read();
      if (!_validRead(generation, scope, session)) return false;
      await _write(() async {
        if (!_validRead(generation, scope, session)) return;
        final previous = _account(scope)!;
        final selected = previous.selectedTermKey;
        await _save(
          StoredGradeAccount(
            account: previous.account,
            snapshot: snapshot,
            selectedTermKey: selected == null
                ? null
                : snapshot.resolveTermKey(selected),
          ),
        );
      });
      return _validRead(generation, scope, session);
    } on LoginFailure catch (error) {
      if (generation == _readGeneration &&
          error.code != LoginFailureCode.cancelled) {
        _failure = GradeFailure(switch (error.code) {
          LoginFailureCode.network => GradeFailureKind.network,
          LoginFailureCode.protocol => GradeFailureKind.protocol,
          _ => GradeFailureKind.authentication,
        }, error.message);
      }
      return false;
    } on GradeStorageException catch (error) {
      if (generation == _readGeneration) {
        _failure = GradeFailure(GradeFailureKind.storage, error.message);
      }
      return false;
    } on FormatException catch (error) {
      if (generation == _readGeneration) {
        _failure = GradeFailure(
          GradeFailureKind.protocol,
          error is GradeParseException
              ? error.message
              : '学校返回的成绩格式无法识别，请核对成绩接口后重试',
        );
      }
      return false;
    } finally {
      if (generation == _readGeneration) _refreshing = false;
      _emit();
    }
  }

  Future<bool> selectTerm(String? key) {
    final scope = state.account?.account.scope;
    if (scope == null) return Future.value(false);
    return _localChange(() async {
      final previous = _account(scope);
      if (previous == null) return;
      final selected = key == null
          ? null
          : previous.snapshot?.resolveTermKey(key);
      if (key != null && selected == null) {
        throw const GradeStorageException('成绩学期列表已更新，请重新选择。');
      }
      await _save(
        StoredGradeAccount(
          account: previous.account,
          snapshot: previous.snapshot,
          selectedTermKey: selected,
        ),
      );
    });
  }

  Future<bool> selectAccount(AccountScope scope) {
    _cancelRead();
    return _localChange(() async {
      final previous = _account(scope);
      if (previous == null) {
        throw const GradeStorageException('此账号的本地成绩已移除，请重新选择。');
      }
      await _save(previous, select: true);
    });
  }

  Future<bool> clearCurrentCache() {
    _cancelRead();
    final scope = state.account?.account.scope;
    if (scope == null) return Future.value(false);
    return _localChange(() async {
      final previous = _account(scope);
      if (previous != null) {
        await _save(StoredGradeAccount(account: previous.account));
      }
    });
  }

  void dismissFailure() {
    _failure = null;
    _emit();
  }

  Future<bool> removeAccount(AccountScope scope) {
    _cancelRead();
    _accountChanges.remove(scope);
    return _localChange(() async {
      final remaining = _library.accounts
          .where((item) => item.account.scope != scope)
          .toList();
      final next = GradeLibrary(
        accounts: remaining,
        selectedAccount: _library.selectedAccount == scope
            ? remaining.firstOrNull?.account.scope
            : _library.selectedAccount,
      );
      await _store.write(next);
      _library = next;
    });
  }

  Future<bool> _localChange(Future<void> Function() action) async {
    await initialize();
    if (!_initialized || _closed) return false;
    _failure = null;
    try {
      await _write(action);
      _emit();
      return true;
    } on GradeStorageException catch (error) {
      _failure = GradeFailure(GradeFailureKind.storage, error.message);
      _emit();
      return false;
    }
  }

  Future<void> _write(Future<void> Function() action) {
    final operation = _writes.then((_) => action());
    // Propagate each write's failure without preventing the next explicit retry.
    _writes = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  void _onAccountChanged(AcademicAccountChange change) {
    if (_closed) return;
    _accountChanges.add(change);
    if (!_initialized) {
      if (!_loading) unawaited(initialize());
      return;
    }
    if (change.selectForViewing ||
        change.account?.scope == _library.selectedAccount) {
      _cancelRead();
    }
    _emit();
    unawaited(_localChange(() => _accountChanges.drain(_applyAccountChange)));
  }

  Future<void> _applyAccountChange(AcademicAccountChange change) async {
    if (_closed) return;
    final account = change.account;
    if (account == null) {
      if (change.selectForViewing) {
        final next = GradeLibrary(accounts: _library.accounts);
        await _store.write(next);
        _library = next;
      }
      return;
    }
    final connected = _source.connectedAccount?.scope == account.scope;
    if (!change.selectForViewing &&
        !connected &&
        _account(account.scope) == null) {
      return;
    }
    await _save(
      _withAccount(account),
      select:
          change.selectForViewing ||
          (connected && _library.selectedAccount == null),
    );
  }

  StoredGradeAccount _withAccount(AcademicAccountRecord account) {
    final previous = _account(account.scope);
    return StoredGradeAccount(
      account: account,
      snapshot: previous?.snapshot,
      selectedTermKey: previous?.selectedTermKey,
    );
  }

  StoredGradeAccount? _account(AccountScope scope) => _library.accounts
      .where((item) => item.account.scope == scope)
      .firstOrNull;

  Future<void> _save(StoredGradeAccount account, {bool select = false}) async {
    final next = GradeLibrary(
      accounts: [
        account,
        ..._library.accounts.where(
          (item) => item.account.scope != account.account.scope,
        ),
      ],
      selectedAccount: select
          ? account.account.scope
          : _library.selectedAccount,
    );
    await _store.write(next);
    _library = next;
  }

  bool _validRead(
    int generation,
    AccountScope scope,
    GradeReadSession session,
  ) =>
      !_closed &&
      generation == _readGeneration &&
      _library.selectedAccount == scope &&
      session.isCurrent;

  void _cancelRead() {
    _readGeneration++;
    _refreshing = false;
  }

  void _emit() {
    if (!_closed) _changes.add(state);
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _cancelRead();
    await _subscription.cancel();
    await _initializing;
    await _writes;
    await _store.close();
    await _changes.close();
  }
}
