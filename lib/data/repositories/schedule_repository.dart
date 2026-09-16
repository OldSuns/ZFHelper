import 'dart:async';

import 'package:zf_core/zf_core.dart';

import '../storage/schedule_store.dart';
import 'academic_source.dart';
import 'schedule_source.dart';

enum ScheduleFailureKind {
  authentication,
  network,
  protocol,
  storage,
  termSelection,
}

typedef ScheduleTarget = ({AccountScope scope, AcademicTerm term, int epoch});
typedef ScheduleEventTarget = ({AccountScope scope, int epoch});

final class ScheduleFailure {
  const ScheduleFailure(this.kind, this.message);
  final ScheduleFailureKind kind;
  final String message;
}

final class ScheduleRepositoryState {
  ScheduleRepositoryState({
    required this.library,
    this.initialized = false,
    this.loading = false,
    this.refreshing = false,
    this.failure,
    this.accountEpoch = 0,
    this.scheduleEpoch = 0,
  });

  final ScheduleLibrary library;
  final bool initialized;
  final bool loading;
  final bool refreshing;
  final ScheduleFailure? failure;
  final int accountEpoch;
  final int scheduleEpoch;

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
        : (scope: scope, term: term, epoch: scheduleEpoch);
  }

  ScheduleEventTarget? get eventTarget {
    final scope = account?.account.scope;
    return scope == null ? null : (scope: scope, epoch: accountEpoch);
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
  late final StreamSubscription<AcademicAccountChange> _subscription;
  ScheduleLibrary _library = ScheduleLibrary();
  bool _loading = true;
  bool _refreshing = false;
  bool _initialized = false;
  bool _closed = false;
  int _readGeneration = 0;
  final _accountEpochs = <AccountScope, int>{};
  final _scheduleEpochs = <AccountScope, int>{};
  final _accountChanges = PendingAcademicAccountChanges();
  ScheduleFailure? _failure;
  Future<void>? _initializing;
  Future<void> _writes = Future.value();

  ScheduleRepositoryState get state => ScheduleRepositoryState(
    library: _library,
    initialized: _initialized,
    loading: _loading,
    refreshing: _refreshing,
    failure: _failure,
    accountEpoch: _accountEpochs[_library.selectedAccount] ?? 0,
    scheduleEpoch: _scheduleEpochs[_library.selectedAccount] ?? 0,
  );
  Stream<ScheduleRepositoryState> get changes => _changes.stream;

  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    _loading = true;
    _failure = null;
    _emit();
    try {
      await _writes;
      final saved = await _store.read();
      if (_closed) return;
      _library = saved;
      final connected = _source.connectedAccount;
      if (_accountChanges.isEmpty && connected != null) {
        await _applyAccountChange(
          AcademicAccountChange(
            connected,
            selectForViewing: saved.selectedAccount == null,
          ),
        );
      }
      await _accountChanges.drain(_applyAccountChange);
      if (!_closed) _initialized = true;
    } on ScheduleStorageException catch (error) {
      _failure = ScheduleFailure(ScheduleFailureKind.storage, error.message);
    } finally {
      _loading = false;
      _emit();
    }
  }

  Future<void> retryLocalLoad() async {
    if (_loading || _closed) return;
    _cancelRead();
    _initialized = false;
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
        final next = previous.copyWith(
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
      final next = previous.copyWith(
        catalog: _mergeCatalog(
          previous.catalog ?? TermCatalog(),
          previous,
          term,
        ),
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
      if (target.epoch != (_scheduleEpochs[target.scope] ?? 0)) {
        throw const ScheduleStorageException(
          operation: '保存课表设置',
          message: '课表已被清理，请重新打开当前课表后修改',
        );
      }
      final settings = update(
        previous.settings[termKey] ?? ScheduleSettings(),
        previous.schedules[termKey]!,
      );
      final next = previous.copyWith(
        settings: {...previous.settings, termKey: settings},
      );
      await _store.saveAccount(next);
      _replace(next);
    });
  }

  Future<bool> saveEvent(
    ScheduleEvent event, {
    required ScheduleEventTarget target,
    ScheduleEvent? replacing,
  }) => _editEvents(
    target: target,
    operation: '保存日程',
    update: (events) {
      if (replacing == null) {
        if (events.any((item) => item.id == event.id)) {
          throw const ScheduleStorageException(
            operation: '保存日程',
            message: '该日程已保存，请重新打开后编辑',
          );
        }
        return [...events, event];
      }
      if (event.id != replacing.id) {
        throw const ScheduleStorageException(
          operation: '保存日程',
          message: '日程标识已改变，请重新打开后编辑',
        );
      }
      final index = _eventIndex(events, replacing, '保存日程');
      return [
        for (var i = 0; i < events.length; i++)
          if (i == index) event else events[i],
      ];
    },
  );

  Future<bool> removeEvent(
    ScheduleEvent event, {
    required ScheduleEventTarget target,
  }) => _editEvents(
    target: target,
    operation: '删除日程',
    update: (events) {
      final index = _eventIndex(events, event, '删除日程');
      return [
        for (var i = 0; i < events.length; i++)
          if (i != index) events[i],
      ];
    },
  );

  Future<bool> setEventCompleted(
    ScheduleEvent event,
    bool completed, {
    required ScheduleEventTarget target,
  }) => _editEvents(
    target: target,
    operation: '更新日程状态',
    update: (events) {
      final index = _eventIndex(events, event, '更新日程状态');
      if (!event.canComplete) {
        throw const ScheduleStorageException(
          operation: '更新日程状态',
          message: '只有待办和作业可以标记完成',
        );
      }
      return [
        for (var i = 0; i < events.length; i++)
          if (i == index) event.copyWith(completed: completed) else events[i],
      ];
    },
  );

  Future<bool> _editEvents({
    required ScheduleEventTarget target,
    required String operation,
    required List<ScheduleEvent> Function(List<ScheduleEvent>) update,
  }) => _localChange(() async {
    final previous = _account(target.scope);
    if (previous == null ||
        target.epoch != (_accountEpochs[target.scope] ?? 0)) {
      throw ScheduleStorageException(
        operation: operation,
        message: '该账号的本机数据已移除，请重新打开日程后操作',
      );
    }
    final next = previous.copyWith(events: update(previous.events));
    await _store.saveAccount(next);
    _replace(next);
  });

  static int _eventIndex(
    List<ScheduleEvent> events,
    ScheduleEvent expected,
    String operation,
  ) {
    final index = events.indexWhere((event) => event.id == expected.id);
    if (index < 0 || events[index] != expected) {
      throw ScheduleStorageException(
        operation: operation,
        message: '该日程已被修改或删除，请重新打开后操作',
      );
    }
    return index;
  }

  Future<bool> clearSchedules(AccountScope scope) {
    _cancelRead();
    _scheduleEpochs.update(scope, (epoch) => epoch + 1, ifAbsent: () => 1);
    return _localChange(() async {
      final previous = _account(scope);
      if (previous == null) return;
      final next = previous.copyWith(
        clearCatalog: true,
        schedules: const {},
        settings: const {},
        clearSelectedTerm: true,
      );
      await _store.saveAccount(next);
      _replace(next);
    });
  }

  Future<bool> removeAccount(AccountScope scope) {
    _cancelRead();
    _accountChanges.remove(scope);
    _accountEpochs.update(scope, (epoch) => epoch + 1, ifAbsent: () => 1);
    _scheduleEpochs.update(scope, (epoch) => epoch + 1, ifAbsent: () => 1);
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

  void _onAccountChanged(AcademicAccountChange change) {
    if (_closed) return;
    _accountChanges.add(change);
    if (!_initialized) {
      return;
    }
    if (change.selectForViewing ||
        change.account?.scope == _library.selectedAccount) {
      _cancelRead();
    }
    _emit();
    // Identity selections share the write queue with imports and removals, so
    // an older transaction cannot leave a different account selected on disk.
    unawaited(_localChange(() => _accountChanges.drain(_applyAccountChange)));
  }

  Future<void> _applyAccountChange(AcademicAccountChange change) async {
    if (_closed) return;
    final account = change.account;
    if (account == null) {
      if (change.selectForViewing) {
        await _store.selectAccount(null);
        _library = ScheduleLibrary(accounts: _library.accounts);
      }
      return;
    }
    final connected = _source.connectedAccount?.scope == account.scope;
    if (!change.selectForViewing &&
        !connected &&
        _account(account.scope) == null) {
      return;
    }
    final next = _withAccount(account);
    final select =
        change.selectForViewing ||
        (connected && _library.selectedAccount == null);
    await _store.saveAccount(next, select: select);
    _replace(next, select: select);
  }

  StoredScheduleAccount _withAccount(AcademicAccountRecord account) {
    final previous = _account(account.scope);
    return previous?.copyWith(account: account) ??
        StoredScheduleAccount(account: account);
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
