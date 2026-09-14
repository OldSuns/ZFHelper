import 'dart:async';

import 'package:zf_core/zf_core.dart';

import '../storage/schedule_store.dart';
import 'schedule_source.dart';

enum ScheduleFailureKind {
  authentication,
  network,
  protocol,
  storage,
  termSelection,
}

typedef ScheduleTarget = ({AccountScope scope, AcademicTerm term, int epoch});

final class ScheduleFailure {
  const ScheduleFailure(this.kind, this.message);
  final ScheduleFailureKind kind;
  final String message;
}

final class ScheduleRepositoryState {
  ScheduleRepositoryState({
    required this.library,
    this.loading = false,
    this.refreshing = false,
    this.failure,
    this.accountEpoch = 0,
  });

  final ScheduleLibrary library;
  final bool loading;
  final bool refreshing;
  final ScheduleFailure? failure;
  final int accountEpoch;

  StoredScheduleAccount? get account => library.accounts
      .where((item) => item.account.scope == library.selectedAccount)
      .firstOrNull;

  AcademicTerm? get selectedTerm {
    final saved = account;
    if (saved == null) return null;
    final key = saved.selectedTermKey;
    return saved.schedules[key]?.term ??
        saved.catalog?.terms.where((term) => term.key == key).firstOrNull;
  }

  ScheduleSnapshot? get imported => account?.schedules[selectedTerm?.key];
  ScheduleTarget? get target {
    final scope = account?.account.scope;
    final term = selectedTerm;
    return scope == null || term == null
        ? null
        : (scope: scope, term: term, epoch: accountEpoch);
  }

  ScheduleSettings get settings =>
      account?.settings[selectedTerm?.key] ?? ScheduleSettings();
  ScheduleSnapshot? get effective =>
      imported == null ? null : settings.applyTo(imported!);
}

final class ScheduleRepository {
  ScheduleRepository({required this._store, required ScheduleSource source})
    : _source = source {
    _subscription = source.accountChanges.listen(_onAccountChanged);
  }

  final ScheduleStore _store;
  final ScheduleSource _source;
  final _changes = StreamController<ScheduleRepositoryState>.broadcast(
    sync: true,
  );
  late final StreamSubscription<ScheduleAccountChange> _subscription;
  ScheduleLibrary _library = ScheduleLibrary();
  bool _loading = true;
  bool _refreshing = false;
  bool _initialized = false;
  bool _closed = false;
  int _readGeneration = 0;
  final _accountEpochs = <AccountScope, int>{};
  ScheduleAccountChange? _initialAccountChange;
  ScheduleFailure? _failure;
  Future<void>? _initializing;
  Future<void> _writes = Future.value();

  ScheduleRepositoryState get state => ScheduleRepositoryState(
    library: _library,
    loading: _loading,
    refreshing: _refreshing,
    failure: _failure,
    accountEpoch: _accountEpochs[_library.selectedAccount] ?? 0,
  );
  Stream<ScheduleRepositoryState> get changes => _changes.stream;

  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    _loading = true;
    _failure = null;
    _emit();
    try {
      final saved = await _store.read();
      if (_closed) return;
      _library = saved;
      final connected = _source.connectedAccount;
      final appliedChange = _initialAccountChange;
      if (connected != null) {
        final account = _withAccount(connected);
        final select =
            saved.selectedAccount == null ||
            (_initialAccountChange?.selectForViewing ?? false);
        await _store.saveAccount(account, select: select);
        if (_closed) return;
        _replace(account, select: select);
      }
      _initialized = true;
      final latest = _initialAccountChange;
      _initialAccountChange = null;
      if (latest != null && !identical(latest, appliedChange)) {
        _onAccountChanged(latest);
      }
    } on ScheduleStorageException catch (error) {
      _failure = ScheduleFailure(ScheduleFailureKind.storage, error.message);
    } finally {
      _loading = false;
      _emit();
    }
  }

  Future<void> retryLocalLoad() async {
    if (_loading) return;
    _initializing = null;
    await initialize();
  }

  Future<bool> refresh({
    AcademicTerm? term,
    bool useSchoolDefault = false,
  }) async {
    await initialize();
    if (!_initialized || _closed || _refreshing) return false;
    final record = state.account;
    if (record == null) return false;
    final scope = record.account.scope;
    final generation = ++_readGeneration;
    _refreshing = true;
    _failure = null;
    _emit();
    try {
      final session = _source.open(scope);
      final result = await session.read(
        term: useSchoolDefault ? null : term ?? state.selectedTerm,
      );
      if (!_validRead(generation, scope, session)) return false;
      await _write(() async {
        if (!_validRead(generation, scope, session)) return;
        final previous = _account(scope)!;
        final snapshot = result.snapshot;
        final catalog = _mergeCatalog(
          result.catalog ?? previous.catalog ?? TermCatalog(),
          previous,
          snapshot?.term,
        );
        final settings = {...previous.settings};
        final oldSnapshot = snapshot == null
            ? null
            : previous.schedules[snapshot.term.key];
        if (snapshot != null &&
            oldSnapshot != null &&
            settings[snapshot.term.key] != null) {
          settings[snapshot.term.key] = settings[snapshot.term.key]!
              .reconcileImport(oldSnapshot, snapshot);
        }
        final schedules = {...previous.schedules};
        if (snapshot != null) schedules[snapshot.term.key] = snapshot;
        final next = StoredScheduleAccount(
          account: previous.account,
          catalog: catalog,
          schedules: schedules,
          settings: settings,
          selectedTermKey: snapshot?.term.key ?? previous.selectedTermKey,
        );
        await _store.saveAccount(next);
        if (_closed) return;
        _replace(next, select: _library.selectedAccount == scope);
      });
      return _validRead(generation, scope, session);
    } on LoginFailure catch (error) {
      if (error.code != LoginFailureCode.cancelled &&
          generation == _readGeneration) {
        _failure = ScheduleFailure(
          error.code == LoginFailureCode.network
              ? ScheduleFailureKind.network
              : ScheduleFailureKind.authentication,
          error.message,
        );
      }
      return false;
    } on ScheduleStorageException catch (error) {
      if (generation == _readGeneration) {
        _failure = ScheduleFailure(ScheduleFailureKind.storage, error.message);
      }
      return false;
    } on FormatException catch (error) {
      if (generation == _readGeneration) {
        _failure = ScheduleFailure(
          error is ScheduleParseException && error.field == 'xnm/xqm'
              ? ScheduleFailureKind.termSelection
              : ScheduleFailureKind.protocol,
          error is ScheduleParseException
              ? error.message
              : '学校返回的课表格式无法识别，请核对课表接口或稍后重试',
        );
      }
      return false;
    } finally {
      if (generation == _readGeneration) _refreshing = false;
      _emit();
    }
  }

  Future<bool> selectTerm(AcademicTerm term) {
    _cancelRead();
    final scope = state.account?.account.scope;
    if (scope == null) return Future.value(false);
    return _localChange(() async {
      final previous = _account(scope);
      if (previous == null) return;
      final next = StoredScheduleAccount(
        account: previous.account,
        catalog: _mergeCatalog(
          previous.catalog ?? TermCatalog(),
          previous,
          term,
        ),
        schedules: previous.schedules,
        settings: previous.settings,
        selectedTermKey: term.key,
      );
      await _store.saveAccount(next);
      _replace(next);
    });
  }

  Future<bool> selectAccount(AccountScope scope) {
    _cancelRead();
    return _localChange(() async {
      final previous = _account(scope);
      if (previous == null) throw StateError('Unknown schedule account.');
      await _store.saveAccount(previous, select: true);
      _replace(previous, select: true);
    });
  }

  Future<bool> updateSettings({
    required ScheduleTarget target,
    required ScheduleSettings Function(ScheduleSettings, ScheduleSnapshot)
    update,
  }) {
    return _localChange(() async {
      final previous = _account(target.scope);
      final termKey = target.term.key;
      if (previous == null || !previous.schedules.containsKey(termKey)) {
        throw const ScheduleStorageException(
          operation: '保存课表设置',
          message: '该账号或学期的本地课表已移除，未保存修改',
        );
      }
      if (target.epoch != (_accountEpochs[target.scope] ?? 0)) {
        throw const ScheduleStorageException(
          operation: '保存课表设置',
          message: '课表已被清理，请重新打开当前课表后修改',
        );
      }
      final settings = update(
        previous.settings[termKey] ?? ScheduleSettings(),
        previous.schedules[termKey]!,
      );
      final next = StoredScheduleAccount(
        account: previous.account,
        catalog: previous.catalog,
        schedules: previous.schedules,
        settings: {...previous.settings, termKey: settings},
        selectedTermKey: previous.selectedTermKey,
      );
      await _store.saveAccount(next);
      _replace(next);
    });
  }

  Future<bool> removeAccount(AccountScope scope) {
    _cancelRead();
    _accountEpochs.update(scope, (epoch) => epoch + 1, ifAbsent: () => 1);
    return _localChange(() async {
      final wasSelected = _library.selectedAccount == scope;
      await _store.removeAccount(scope);
      _library = await _store.read();
      final connected = _source.connectedAccount;
      if (connected != null && _account(connected.scope) == null) {
        final account = _withAccount(connected);
        final select = wasSelected || _library.selectedAccount == null;
        await _store.saveAccount(account, select: select);
        _replace(account, select: select);
      }
    });
  }

  void dismissFailure() {
    _failure = null;
    _emit();
  }

  bool canRefresh(AccountScope scope) =>
      _source.connectedAccount?.scope == scope;

  Future<bool> _localChange(Future<void> Function() action) async {
    await initialize();
    if (!_initialized || _closed) return false;
    _failure = null;
    try {
      await _write(action);
      _emit();
      return true;
    } on ScheduleStorageException catch (error) {
      _failure = ScheduleFailure(ScheduleFailureKind.storage, error.message);
      _emit();
      return false;
    }
  }

  Future<void> _write(Future<void> Function() action) {
    final operation = _writes.then((_) => action());
    // Each caller receives its own error. A failed write must not poison the
    // serialization queue and prevent the user's next explicit retry.
    _writes = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  void _onAccountChanged(ScheduleAccountChange change) {
    if (_closed) return;
    if (!_initialized) {
      _initialAccountChange = change;
      return;
    }
    _cancelRead();
    _emit();
    final account = change.account;
    if (account == null) return;
    // Identity selections share the write queue with imports and removals, so
    // an older transaction cannot leave a different account selected on disk.
    unawaited(
      _localChange(() async {
        if (_source.connectedAccount?.scope != account.scope) return;
        final next = _withAccount(account);
        final select =
            change.selectForViewing || _library.selectedAccount == null;
        await _store.saveAccount(next, select: select);
        _replace(next, select: select);
      }),
    );
  }

  StoredScheduleAccount _withAccount(ScheduleAccountRecord account) {
    final previous = _account(account.scope);
    return StoredScheduleAccount(
      account: account,
      catalog: previous?.catalog,
      schedules: previous?.schedules ?? const {},
      settings: previous?.settings ?? const {},
      selectedTermKey: previous?.selectedTermKey,
    );
  }

  StoredScheduleAccount? _account(AccountScope scope) => _library.accounts
      .where((account) => account.account.scope == scope)
      .firstOrNull;

  void _replace(StoredScheduleAccount account, {bool select = false}) {
    _library = ScheduleLibrary(
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
  }

  static TermCatalog _mergeCatalog(
    TermCatalog catalog,
    StoredScheduleAccount previous,
    AcademicTerm? selected,
  ) {
    final terms = <String, AcademicTerm>{
      for (final term in previous.catalog?.terms ?? <AcademicTerm>[])
        term.key: term,
      for (final snapshot in previous.schedules.values)
        snapshot.term.key: snapshot.term,
      for (final term in catalog.terms) term.key: term,
      if (catalog.selectedTerm != null)
        catalog.selectedTerm!.key: catalog.selectedTerm!,
    };
    if (selected != null) terms[selected.key] = selected;
    return TermCatalog(
      terms: terms.values.toList(),
      selectedTerm: catalog.selectedTerm,
      yearOptions: catalog.yearOptions,
      termOptions: catalog.termOptions,
    );
  }

  bool _validRead(
    int generation,
    AccountScope scope,
    ScheduleReadSession session,
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
    await _writes;
    await _store.close();
    await _changes.close();
  }
}
