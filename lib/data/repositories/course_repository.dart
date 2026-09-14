import 'dart:async';

import 'package:zf_core/zf_core.dart';

import '../../platform/selection_runtime.dart';
import '../storage/academic_account.dart';
import '../storage/course_store.dart';
import 'academic_source.dart';
import 'course_source.dart';

final class CourseDetails {
  CourseDetails({
    required this.account,
    required this.round,
    required this.course,
    required List<CourseSection> sections,
    required this.fetchedAt,
  }) : sections = List.unmodifiable(sections);
  final AcademicAccountRecord account;
  final SelectionRound round;
  final CourseOffering course;
  final List<CourseSection> sections;
  final DateTime fetchedAt;
}

final class CourseRepositoryState {
  const CourseRepositoryState({
    required this.library,
    required this.operations,
    this.initialized = false,
    this.loading = false,
    this.refreshing = false,
    this.failure,
    this.runtime,
  });
  final CourseLibrary library;
  final List<SelectionOperation> operations;
  final bool initialized;
  final bool loading;
  final bool refreshing;
  final String? failure;
  final SelectionRuntimeCapabilities? runtime;
  StoredCourseAccount? get account => library.accounts
      .where((item) => item.account.scope == library.selectedAccount)
      .firstOrNull;
  CourseRoundCache? get catalog => account?.selectedCatalog;
}

/// Owns cached course data and the single executor shared by every page/account.
final class CourseRepository {
  CourseRepository({
    required this._store,
    required CourseSource source,
    required SelectionOperationStore operationStore,
    required SelectionRuntime runtime,
    required DateTime Function() clock,
  }) : _source = source,
       _runtime = runtime,
       _clock = clock {
    _coordinator = SelectionCoordinator(
      access: source,
      store: operationStore,
      clock: clock,
      syncRuntime: (count) async {
        try {
          await _runtime.sync(activeWorkCount: count);
        } on SelectionRuntimeException catch (error) {
          throw SelectionExecutionException(error.message);
        }
      },
    );
    _accountSubscription = source.accountChanges.listen(_onAccountChanged);
    _accessSubscription = source.accessChanges.listen((_) {
      if (_initialized && !_closed) {
        unawaited(_reconcileAccess());
      }
    });
    _operationSubscription = _coordinator.changes.listen((_) => _emit());
    _runtimeSubscription = runtime.events.listen(
      _onRuntimeEvent,
      onError: (Object error) {
        if (error is! SelectionRuntimeException) {
          Error.throwWithStackTrace(error, StackTrace.current);
        }
        unawaited(_interruptRuntime(error.message));
      },
    );
  }

  final CourseStore _store;
  final CourseSource _source;
  final SelectionRuntime _runtime;
  final DateTime Function() _clock;
  late final SelectionCoordinator _coordinator;
  late final StreamSubscription<AcademicAccountChange> _accountSubscription;
  late final StreamSubscription<void> _accessSubscription;
  late final StreamSubscription<void> _operationSubscription;
  late final StreamSubscription<SelectionRuntimeEvent> _runtimeSubscription;
  final _changes = StreamController<CourseRepositoryState>.broadcast(
    sync: true,
  );
  CourseLibrary _library = CourseLibrary();
  SelectionRuntimeCapabilities? _capabilities;
  AcademicAccountChange? _pendingAccountChange;
  Future<void>? _initializing;
  Future<void> _writes = Future.value();
  bool _initialized = false;
  bool _loading = true;
  bool _refreshing = false;
  bool _starting = false;
  bool _closed = false;
  int _readGeneration = 0;
  int _detailsGeneration = 0;
  String? _failure;

  CourseRepositoryState get state => CourseRepositoryState(
    library: _library,
    operations: _coordinator.operations,
    initialized: _initialized,
    loading: _loading,
    refreshing: _refreshing,
    failure: _failure ?? _coordinator.failure,
    runtime: _capabilities,
  );
  Stream<CourseRepositoryState> get changes => _changes.stream;
  bool canQuery(AccountScope scope) => _source.canAccess(scope);
  bool get hasActiveOperations => _coordinator.activeCount > 0;

  Future<void> initialize() {
    if (_closed || _initialized) return Future.value();
    return _initializing ??= _initialize().whenComplete(
      () => _initializing = null,
    );
  }

  Future<void> _initialize() async {
    _loading = true;
    _failure = null;
    _emit();
    try {
      await _writes;
      _library = await _store.read();
      if (_closed) return;
      await _coordinator.initialize();
      await _runtime.sync(activeWorkCount: 0);
      _capabilities = await _runtime.capabilities();
      if (_closed) return;
      final connected = _source.connectedAccount;
      final applied = _pendingAccountChange;
      if (connected != null) {
        await _save(
          _withAccount(connected),
          select:
              _library.selectedAccount == null ||
              (applied?.selectForViewing ?? false),
        );
      }
      if (_closed) return;
      _initialized = true;
      final latest = _pendingAccountChange;
      _pendingAccountChange = null;
      if (latest != null && !identical(applied, latest)) {
        _onAccountChanged(latest);
      }
    } on Exception catch (error) {
      _failure = _errorMessage(error);
      if (_failure == null) rethrow;
    } finally {
      _loading = false;
      _emit();
    }
  }

  Future<bool> refresh() => _refresh();

  Future<bool> _refresh({String? requestedRound}) async {
    await initialize();
    final stored = state.account;
    if (!_initialized || _closed || _refreshing || stored == null) return false;
    final scope = stored.account.scope;
    final generation = ++_readGeneration;
    _refreshing = true;
    _failure = null;
    _emit();
    try {
      await _coordinator.initialize();
      final session = _source.open(scope);
      final context = await session.readContext();
      if (!_validRead(generation, scope, session)) return false;
      final preferred = requestedRound ?? stored.selectedRoundKey;
      var round = context.rounds
          .where((item) => item.key == preferred)
          .firstOrNull;
      if (requestedRound != null && round == null) {
        throw const SelectionException(
          SelectionFailureCode.roundClosed,
          '此选课轮次已关闭或更新，请重新查询轮次',
        );
      }
      round ??= context.rounds.firstOrNull;
      CourseRoundCache? catalog;
      if (round != null) {
        final courses = await session.readCourses(context, round);
        if (!_validRead(generation, scope, session)) return false;
        final selected = await session.readSelected(context, round: round);
        if (!_validRead(generation, scope, session)) return false;
        final now = _clock();
        catalog = CourseRoundCache(
          roundKey: round.key,
          courses: courses,
          selectedCourses: selected,
          fetchedAt: now,
          selectedFetchedAt: now,
        );
      }
      await _write(() async {
        if (!_validRead(generation, scope, session)) return;
        final current = _account(scope)!;
        final roundKeys = context.rounds.map((item) => item.key).toSet();
        await _save(
          StoredCourseAccount(
            account: current.account,
            rounds: context.rounds,
            roundsFetchedAt: context.fetchedAt,
            selectedRoundKey: round?.key,
            catalogs: [
              ?catalog,
              ...current.catalogs.where(
                (item) =>
                    item.roundKey != catalog?.roundKey &&
                    roundKeys.contains(item.roundKey),
              ),
            ],
          ),
        );
      });
      return _validRead(generation, scope, session);
    } on Exception catch (error) {
      final message = _errorMessage(error);
      if (message == null) rethrow;
      if (generation == _readGeneration) _failure = message;
      return false;
    } finally {
      if (generation == _readGeneration) _refreshing = false;
      _emit();
    }
  }

  Future<bool> selectRound(String key) async {
    _cancelRead();
    final scope = state.account?.account.scope;
    if (scope == null) return false;
    final saved = await _action(
      () => _write(() async {
        final item = _account(scope);
        if (item == null || !item.rounds.any((round) => round.key == key)) {
          throw const SelectionExecutionException('轮次列表已更新，请重新选择');
        }
        await _save(
          StoredCourseAccount(
            account: item.account,
            rounds: item.rounds,
            catalogs: item.catalogs,
            selectedRoundKey: key,
            roundsFetchedAt: item.roundsFetchedAt,
          ),
        );
      }),
    );
    if (!saved || _library.selectedAccount != scope) return false;
    // A saved round remains browsable offline; no background refresh on selection.
    return state.catalog != null || !canQuery(scope)
        ? true
        : _refresh(requestedRound: key);
  }

  Future<bool> selectAccount(AccountScope scope) {
    _cancelRead();
    return _action(
      () => _write(() async {
        final item = _account(scope);
        if (item == null) {
          throw const SelectionExecutionException('此账号的课程缓存已移除');
        }
        await _save(item, select: true);
      }),
    );
  }

  Future<CourseDetails?> sections(CourseOffering offering) async {
    await initialize();
    final account = state.account?.account;
    if (!_initialized || _closed || account == null) return null;
    final generation = ++_detailsGeneration;
    final scope = account.scope;
    _failure = null;
    _emit();
    try {
      final session = _source.open(scope);
      bool current() =>
          !_closed &&
          generation == _detailsGeneration &&
          _library.selectedAccount == scope &&
          session.isCurrent;
      final context = await session.readContext();
      if (!current()) return null;
      final round = context.rounds
          .where((item) => item.key == offering.roundKey)
          .firstOrNull;
      if (round == null) {
        throw const SelectionException(
          SelectionFailureCode.roundClosed,
          '此选课轮次已关闭或变化，请更新课程列表',
        );
      }
      final courses = await session.readCourses(context, round);
      if (!current()) return null;
      final candidates = courses
          .where((item) => item.key == offering.key)
          .toList();
      if (candidates.length != 1) {
        throw const SelectionException(
          SelectionFailureCode.protocol,
          '课程已变化或无法唯一定位，请更新列表后重新选择',
        );
      }
      final course = candidates.single;
      final sections = await session.readSections(context, course);
      if (!current()) return null;
      return CourseDetails(
        account: account,
        round: round,
        course: course,
        sections: sections,
        fetchedAt: _clock(),
      );
    } on Exception catch (error) {
      final message = _errorMessage(error);
      if (message == null) rethrow;
      if (generation == _detailsGeneration) _failure = message;
      return null;
    } finally {
      _emit();
    }
  }

  Future<bool> start(
    SelectionTarget target, {
    required SelectionMode mode,
    Duration interval = const Duration(seconds: 5),
    Duration duration = const Duration(minutes: 30),
  }) async {
    if (_starting) return false;
    _starting = true;
    try {
      return await _action(() async {
        if (mode == SelectionMode.watch) await _prepareRuntime();
        await _coordinator.start(
          target,
          mode: mode,
          interval: interval,
          duration: duration,
        );
      });
    } finally {
      _starting = false;
    }
  }

  Future<bool> stop(String id) => _action(() => _coordinator.stop(id));
  Future<bool> resume(String id) => _action(() async {
    final item = _coordinator.operations
        .where((item) => item.id == id)
        .firstOrNull;
    if (item?.mode == SelectionMode.watch) await _prepareRuntime();
    await _coordinator.resume(id);
  });
  Future<bool> verify(String id) => _action(() => _coordinator.verify(id));
  Future<bool> clearHistory() => _action(_coordinator.clearHistory);

  Future<void> _prepareRuntime() async {
    _capabilities = await _runtime.prepare();
    if (!_capabilities!.canStart) {
      throw SelectionRuntimeException(
        'cannot_start',
        _capabilities!.reason ?? '当前无法维持捡漏运行，请检查通知权限与系统状态',
      );
    }
  }

  Future<bool> clearCurrentCache() {
    _cancelRead();
    final scope = state.account?.account.scope;
    if (scope == null) return Future.value(false);
    return _action(
      () => _write(() async {
        final current = _account(scope);
        if (current != null) {
          await _save(StoredCourseAccount(account: current.account));
        }
      }),
    );
  }

  Future<bool> removeAccount(AccountScope scope) {
    _cancelRead();
    return _action(() async {
      await _coordinator.removeAccount(scope);
      await _write(() async {
        final remaining = _library.accounts
            .where((item) => item.account.scope != scope)
            .toList();
        final next = CourseLibrary(
          accounts: remaining,
          selectedAccount: _library.selectedAccount == scope
              ? remaining.firstOrNull?.account.scope
              : _library.selectedAccount,
        );
        await _store.write(next);
        _library = next;
      });
    });
  }

  Future<bool> pauseForExit() =>
      _action(() => _coordinator.pauseAll('软件已关闭；重新打开后请手动继续，未确认的提交先核实结果'));

  void dismissFailure() {
    _failure = null;
    _coordinator.dismissFailure();
    _emit();
  }

  Future<bool> _action(Future<void> Function() action) async {
    await initialize();
    if (!_initialized || _closed) return false;
    _failure = null;
    try {
      await action();
      return true;
    } on Exception catch (error) {
      _failure = _errorMessage(error);
      if (_failure == null) rethrow;
      return false;
    } finally {
      _emit();
    }
  }

  Future<void> _write(Future<void> Function() action) {
    final pending = _writes.then((_) => action());
    _writes = pending.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return pending;
  }

  void _onAccountChanged(AcademicAccountChange change) {
    if (_closed) return;
    if (!_initialized) {
      _pendingAccountChange = change;
      return;
    }
    _cancelRead();
    _emit();
    final account = change.account;
    if (account == null) return;
    unawaited(
      _action(
        () => _write(() async {
          if (_source.connectedAccount?.scope != account.scope) return;
          await _save(
            _withAccount(account),
            select: change.selectForViewing || _library.selectedAccount == null,
          );
        }),
      ),
    );
  }

  void _onRuntimeEvent(SelectionRuntimeEvent event) {
    if (_closed) return;
    if (event.kind == SelectionRuntimeEventKind.capabilitiesChanged) {
      unawaited(_loadCapabilities());
    } else {
      unawaited(_interruptRuntime(event.reason ?? '捡漏运行已被停止，请手动继续'));
    }
  }

  Future<void> _loadCapabilities() async {
    try {
      _capabilities = await _runtime.capabilities();
    } on SelectionRuntimeException catch (error) {
      _failure = error.message;
    }
    _emit();
  }

  Future<void> _reconcileAccess() async {
    try {
      await _coordinator.reconcileSessions();
    } on Exception catch (error) {
      _failure = _errorMessage(error);
      if (_failure == null) rethrow;
    }
    _emit();
  }

  Future<void> _interruptRuntime(String reason) async {
    if (_closed) return;
    try {
      // Native events can arrive before SQLite has restored the operation list.
      await initialize();
      if (_closed) return;
      if (!_initialized) {
        await _runtime.sync(activeWorkCount: 0);
        return;
      }
      await _coordinator.pauseAll(reason, watchOnly: true);
      _capabilities = await _runtime.capabilities();
      _failure = reason;
    } on Exception catch (error) {
      _failure = _errorMessage(error);
      if (_failure == null) rethrow;
    }
    _emit();
  }

  StoredCourseAccount? _account(AccountScope scope) => _library.accounts
      .where((item) => item.account.scope == scope)
      .firstOrNull;

  StoredCourseAccount _withAccount(AcademicAccountRecord account) {
    final previous = _account(account.scope);
    return StoredCourseAccount(
      account: account,
      rounds: previous?.rounds ?? const [],
      catalogs: previous?.catalogs ?? const [],
      selectedRoundKey: previous?.selectedRoundKey,
      roundsFetchedAt: previous?.roundsFetchedAt,
    );
  }

  Future<void> _save(StoredCourseAccount item, {bool select = false}) async {
    final next = CourseLibrary(
      accounts: [
        item,
        ..._library.accounts.where(
          (entry) => entry.account.scope != item.account.scope,
        ),
      ],
      selectedAccount: select ? item.account.scope : _library.selectedAccount,
    );
    await _store.write(next);
    _library = next;
  }

  bool _validRead(
    int generation,
    AccountScope scope,
    SelectionAccessSession session,
  ) =>
      !_closed &&
      generation == _readGeneration &&
      _library.selectedAccount == scope &&
      session.isCurrent;

  void _cancelRead() {
    _readGeneration++;
    _detailsGeneration++;
    _refreshing = false;
  }

  void _emit() {
    if (!_closed) _changes.add(state);
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _cancelRead();
    await _accountSubscription.cancel();
    await _accessSubscription.cancel();
    await _runtimeSubscription.cancel();
    await _initializing;
    try {
      await _coordinator.dispose();
    } finally {
      await _operationSubscription.cancel();
      await _writes;
      try {
        await _runtime.dispose();
      } finally {
        await _store.close();
        await _changes.close();
      }
    }
  }
}

String? _errorMessage(Exception error) => switch (error) {
  LoginFailure(:final message) => message,
  SelectionException(:final message) => message,
  SelectionStorageException(:final message) => message,
  SelectionExecutionException(:final message) => message,
  SelectionRuntimeException(:final message) => message,
  _ => null,
};
