import 'dart:async';

import '../auth/account_scope.dart';
import '../auth/login_models.dart';
import 'selection_access.dart';
import 'selection_models.dart';
import 'selection_operation.dart';

final class SelectionExecutionException implements Exception {
  const SelectionExecutionException(this.message);
  final String message;
  @override
  String toString() => 'SelectionExecutionException: $message';
}

/// One executor for manually started operations, independent of page lifetime.
final class SelectionCoordinator {
  SelectionCoordinator({
    required this._access,
    required this._store,
    required this._clock,
    required this._syncRuntime,
  });

  final SelectionAccess _access;
  final SelectionOperationStore _store;
  final DateTime Function() _clock;
  final Future<void> Function(int) _syncRuntime;
  final _changes = StreamController<void>.broadcast(sync: true);
  final _sessions = <String, SelectionAccessSession>{};
  final _ready = <String>{};
  final _hosted = <String>{};
  final _verifications = <String>{};
  final _cancellations = <String>{};
  final _pauses = <String, String>{};
  final _timers = <String, Timer>{};
  final _runners = <AccountScope, Future<void>>{};
  List<SelectionOperation> _operations = const [];
  Future<void> _writes = Future.value();
  Future<void> _hostWrites = Future.value();
  Future<void>? _initializing;
  bool _initialized = false;
  bool _closed = false;
  bool _storageBlocked = false;
  String? _failure;
  int _sequence = 0;

  List<SelectionOperation> get operations => _operations;
  Stream<void> get changes => _changes.stream;
  String? get failure => _failure;
  int get activeCount => _operations.where((item) => item.isActive).length;

  Future<void> initialize() {
    if (_closed) return Future.value();
    if (_initialized && !_storageBlocked) return Future.value();
    return _initializing ??= _initialize().whenComplete(
      () => _initializing = null,
    );
  }

  Future<void> _initialize() async {
    if (_storageBlocked && _runners.isNotEmpty) {
      throw SelectionStorageException(_failure!);
    }
    if (!_initialized) _operations = await _store.readOperations();
    await _commit(
      (items) => items.map((item) {
        if (!item.isActive) return item;
        return item.copyWith(
          status: item.mayHaveSubmitted
              ? SelectionStatus.uncertain
              : SelectionStatus.paused,
          updatedAt: _clock(),
          message: item.mayHaveSubmitted
              ? '上次提交未完成核实，请核对学校已选记录'
              : '运行已中断，点击继续后重新查询学校状态',
        );
      }).toList(),
    );
    _storageBlocked = false;
    _failure = null;
    _initialized = true;
    _emit();
  }

  Future<void> start(
    SelectionTarget target, {
    required SelectionMode mode,
    Duration interval = const Duration(seconds: 5),
    Duration duration = const Duration(minutes: 30),
  }) async {
    await initialize();
    _requireOpen();
    if (target.courseId.isEmpty ||
        target.sectionId.isEmpty ||
        interval <= Duration.zero ||
        duration <= Duration.zero) {
      throw const SelectionExecutionException('请选择具体教学班，并填写有效的查询间隔和持续时间');
    }
    final session = _access.open(target.scope);
    if (!session.isCurrent) {
      throw const SelectionExecutionException('此账号的登录状态已更新，请重新登录后操作');
    }
    final now = _clock();
    String id;
    do {
      id = '${now.microsecondsSinceEpoch}-${++_sequence}';
    } while (_find(id) != null);
    final operation = SelectionOperation(
      id: id,
      target: target,
      mode: mode,
      status: SelectionStatus.queued,
      createdAt: now,
      updatedAt: now,
      expiresAt: _deadline(duration),
      interval: interval,
      duration: duration,
      message: '正在准备选课',
    );
    await _commit((items) {
      if (items.any(
        (item) =>
            item.target.sameClass(target) &&
            (item.isActive ||
                item.mayHaveSubmitted ||
                item.status == SelectionStatus.paused),
      )) {
        throw const SelectionExecutionException('此教学班已有进行中、已暂停或待核实的操作，请先处理原操作');
      }
      return [...items, operation];
    });
    _sessions[id] = session;
    await _activate(id);
  }

  Future<void> resume(String id) async {
    await initialize();
    _require(id);
    SelectionAccessSession? session;
    await _update(id, (current) {
      if (current.isActive ||
          current.mayHaveSubmitted ||
          current.status == SelectionStatus.succeeded) {
        throw const SelectionExecutionException('此操作不能重复启动；未确认的提交请先核实结果');
      }
      session = _access.open(current.target.scope);
      _cancellations.remove(id);
      _pauses.remove(id);
      return current.copyWith(
        status: SelectionStatus.queued,
        cancelRequested: false,
        expiresAt: _deadline(current.duration),
        message: '正在重新查询学校状态',
      );
    });
    if (session == null || _find(id) == null) return;
    _sessions[id] = session!;
    await _activate(id);
  }

  Future<void> verify(String id) async {
    await initialize();
    final item = _require(id);
    SelectionAccessSession? session;
    await _update(id, (current) {
      if (!current.mayHaveSubmitted || current.isActive) {
        throw const SelectionExecutionException('此操作当前无需重新核实');
      }
      session = _access.open(current.target.scope);
      _pauses.remove(id);
      return current.copyWith(
        status: SelectionStatus.verifying,
        message: '正在查询学校已选记录',
      );
    });
    if (session == null || _find(id) == null) return;
    _sessions[id] = session!;
    _verifications.add(id);
    _ready.add(id);
    _kick(item.target.scope);
  }

  Future<void> stop(String id) async {
    final item = _require(id);
    if (!item.isActive && item.status != SelectionStatus.paused) return;
    _cancellations.add(id);
    _timers.remove(id)?.cancel();
    await _update(
      id,
      (current) => current.copyWith(
        status: current.mayHaveSubmitted
            ? current.status
            : SelectionStatus.cancelled,
        cancelRequested: true,
        message: current.mayHaveSubmitted
            ? '已停止后续尝试，正在核实已发出的请求'
            : '已停止，未发出新的选课请求',
      ),
    );
    if (!(_find(id)?.isActive ?? false)) _release(id);
    await _syncHost();
  }

  Future<void> pauseAll(String reason, {bool watchOnly = false}) async {
    bool matches(SelectionOperation item) =>
        item.isActive && (!watchOnly || item.mode == SelectionMode.watch);
    for (final item in operations.where(matches)) {
      _pauses[item.id] = reason;
      _timers.remove(item.id)?.cancel();
    }
    await _commit(
      (items) => items.map((item) {
        if (!matches(item) || item.mayHaveSubmitted) return item;
        _release(item.id);
        return item.copyWith(
          status: SelectionStatus.paused,
          updatedAt: _clock(),
          message: reason,
        );
      }).toList(),
    );
    await _syncHost();
  }

  Future<void> reconcileSessions() async {
    final invalid = _sessions.entries
        .where((entry) => !entry.value.isCurrent)
        .map((entry) => entry.key)
        .toSet();
    if (invalid.isEmpty) return;
    for (final id in invalid) {
      _release(id);
    }
    await _commit(
      (items) => items.map((item) {
        if (!invalid.contains(item.id) || !item.isActive) return item;
        return item.copyWith(
          status: item.mayHaveSubmitted
              ? SelectionStatus.uncertain
              : SelectionStatus.paused,
          updatedAt: _clock(),
          message: item.mayHaveSubmitted
              ? '账号登录状态已更新，之前提交的结果仍待核实'
              : '账号已退出或重新登录，已停止后续尝试',
        );
      }).toList(),
    );
    await _syncHost();
  }

  Future<void> removeAccount(AccountScope scope) async {
    // Invalidate first: a late network response must never recreate this data.
    for (final item in operations.where((item) => item.target.scope == scope)) {
      _release(item.id);
    }
    await _commit(
      (items) => items.where((item) => item.target.scope != scope).toList(),
    );
    await _syncHost();
  }

  Future<void> clearHistory() => _commit(
    (items) => items
        .where(
          (item) =>
              item.isActive ||
              item.mayHaveSubmitted ||
              item.status == SelectionStatus.paused,
        )
        .toList(),
  );

  void dismissFailure() {
    if (_storageBlocked) return;
    _failure = null;
    _emit();
  }

  Future<void> _activate(String id) async {
    try {
      if (_find(id)?.mode == SelectionMode.watch) _hosted.add(id);
      await _syncHost();
      final item = _find(id);
      if (item == null || !item.isActive || !_sessions.containsKey(id)) return;
      _ready.add(id);
      _kick(item.target.scope);
    } on SelectionExecutionException catch (error) {
      await _update(
        id,
        (item) => item.copyWith(
          status: SelectionStatus.paused,
          message: error.message,
        ),
      );
      _release(id);
      rethrow;
    }
  }

  void _kick(AccountScope scope) {
    if (_closed || _storageBlocked || _runners.containsKey(scope)) return;
    final running = _drive(scope);
    _runners[scope] = running;
    unawaited(
      running.whenComplete(() {
        _runners.remove(scope);
        if (_next(scope) != null) _kick(scope);
      }),
    );
  }

  SelectionOperation? _next(AccountScope scope) {
    if (_closed || _storageBlocked) return null;
    return operations
        .where(
          (item) =>
              item.target.scope == scope &&
              _ready.contains(item.id) &&
              (item.status == SelectionStatus.queued ||
                  _verifications.contains(item.id) ||
                  (item.status == SelectionStatus.waiting &&
                      !(item.nextCheckAt?.isAfter(_clock()) ?? false))),
        )
        .firstOrNull;
  }

  Future<void> _drive(AccountScope scope) async {
    try {
      while (true) {
        final item = _next(scope);
        if (item == null) break;
        final session = _sessions[item.id];
        if (session == null) {
          _ready.remove(item.id);
          continue;
        }
        await _attemptAndReport(item.id, session);
        final current = _find(item.id);
        if (current == null || !current.isActive) _release(item.id);
        await _syncHost();
      }
    } on SelectionStorageException {
      await _releaseHostAfterFailure();
    } on SelectionExecutionException catch (error) {
      _failure = error.message;
      try {
        await pauseAll(error.message);
      } on SelectionStorageException {
        await _releaseHostAfterFailure();
      } on SelectionExecutionException catch (stopError) {
        _failure = '${error.message}；${stopError.message}';
      }
      _emit();
    }
  }

  Future<void> _releaseHostAfterFailure() async {
    try {
      await _syncHost();
    } on SelectionExecutionException catch (error) {
      _failure = '${_failure ?? '选课已停止'}；${error.message}';
      _emit();
    }
  }

  Future<void> _attemptAndReport(
    String id,
    SelectionAccessSession session,
  ) async {
    try {
      await _attempt(id, session);
    } on SelectionStorageException {
      rethrow;
    } on Exception catch (error) {
      final message = _knownError(error);
      if (message == null) rethrow;
      if (_find(id) == null || _sessions[id] != session) return;
      await _update(
        id,
        (value) => value.copyWith(
          status: value.mayHaveSubmitted
              ? SelectionStatus.uncertain
              : error is LoginFailure
              ? SelectionStatus.paused
              : SelectionStatus.failed,
          message: message,
        ),
      );
    }
  }

  Future<void> _attempt(String id, SelectionAccessSession session) async {
    var item = _require(id);
    final verification = _verifications.remove(id);
    if (!verification && !await _canContinue(id, session)) return;
    if (!session.isCurrent) {
      throw const LoginFailure(
        LoginFailureCode.expired,
        '账号已退出或重新登录，请处理登录状态后继续',
      );
    }
    if (!verification) {
      await _update(
        id,
        (value) => value.copyWith(
          status: SelectionStatus.checking,
          checks: value.checks + 1,
          message: '正在核对轮次、教学班及已选记录',
        ),
      );
    }
    final context = await session.readContext();
    if (!_live(id, session)) return;
    final round = context.rounds
        .where((round) => round.key == item.target.round.key)
        .firstOrNull;
    if (round == null) {
      throw const SelectionException(
        SelectionFailureCode.roundClosed,
        '原选课轮次已关闭或发生变化，请到教务系统核对结果',
      );
    }
    final selected = await session.readSelected(context, round: round);
    if (!_live(id, session)) return;
    if (selected.any(item.target.matches)) {
      await _success(id, beforeSubmission: !verification);
      return;
    }
    if (verification) {
      await _update(
        id,
        (value) => value.copyWith(
          status: SelectionStatus.uncertain,
          message: '学校已选记录暂未包含此教学班，结果仍待确认；不会自动重新提交',
        ),
      );
      return;
    }
    if (!await _canContinue(id, session)) return;
    final courses = await session.readCourses(context, round);
    if (!await _canContinue(id, session)) return;
    final matching = courses
        .where(
          (course) =>
              course.courseId == item.target.courseId &&
              (course.sectionId == null ||
                  course.sectionId == item.target.sectionId),
        )
        .toList();
    final exact = matching
        .where((course) => course.sectionId == item.target.sectionId)
        .toList();
    final candidates = exact.isEmpty ? matching : exact;
    if (candidates.length != 1) {
      throw const SelectionException(
        SelectionFailureCode.protocol,
        '学校当前课程列表无法唯一定位原课程，请重新查询并选择教学班',
      );
    }
    final course = candidates.single;
    final sections = await session.readSections(context, course);
    if (!await _canContinue(id, session)) return;
    final matches = sections
        .where(
          (section) =>
              section.courseId == item.target.courseId &&
              section.sectionId == item.target.sectionId,
        )
        .toList();
    if (matches.length != 1) {
      throw const SelectionException(
        SelectionFailureCode.protocol,
        '原教学班已不存在或编号无法唯一识别，请重新查询',
      );
    }
    final section = matches.single;
    if (section.available != null && section.available! <= 0) {
      if (item.mode == SelectionMode.watch) {
        await _wait(id, '当前名额已满，等待下次查询');
      } else {
        await _update(
          id,
          (value) => value.copyWith(
            status: SelectionStatus.rejected,
            message: '当前教学班名额已满，可使用手动捡漏继续观察',
          ),
        );
      }
      return;
    }
    await _update(
      id,
      (value) => value.copyWith(
        status: SelectionStatus.submitting,
        submissions: value.submissions + 1,
        message: '正在提交所选教学班',
      ),
    );
    if (!await _canContinue(id, session)) return;

    SelectionSubmission? response;
    String? sendFailure;
    try {
      response = await session.submit(
        context,
        course,
        section,
        shouldSend: () =>
            _live(id, session) &&
            !_storageBlocked &&
            session.isCurrent &&
            !_cancellations.contains(id) &&
            !_pauses.containsKey(id) &&
            _clock().isBefore(_require(id).expiresAt),
      );
    } on SelectionNotSentException {
      if (!_live(id, session)) return;
      await _update(
        id,
        (value) => value.copyWith(
          status: _cancellations.contains(id)
              ? SelectionStatus.cancelled
              : SelectionStatus.paused,
          submissions: value.submissions - 1,
          message: '发送前已停止，未向学校提交选课请求',
        ),
      );
      return;
    } on Exception catch (error) {
      sendFailure = _knownError(error);
      if (sendFailure == null) rethrow;
    }
    if (!_live(id, session)) return;
    await _update(
      id,
      (value) => value.copyWith(
        status: SelectionStatus.verifying,
        message: '提交已结束，正在核实学校已选记录',
      ),
    );
    final after = await session.readSelected(context, round: round);
    if (!_live(id, session)) return;
    if (after.any(item.target.matches)) {
      await _success(id);
      return;
    }
    item = _require(id);
    if (response?.status == SelectionSubmissionStatus.rejected) {
      if (_cancellations.contains(id)) {
        await _update(
          id,
          (value) => value.copyWith(
            status: SelectionStatus.cancelled,
            message: '已停止；学校未接受本次选课：${response!.message}',
          ),
        );
      } else if (item.mode == SelectionMode.watch &&
          RegExp('已满|满额|余量不足|容量不足|无剩余名额').hasMatch(response!.message)) {
        await _wait(id, '学校提示名额不足，等待下次查询');
      } else {
        await _update(
          id,
          (value) => value.copyWith(
            status: SelectionStatus.rejected,
            message: response!.message,
          ),
        );
      }
      return;
    }
    await _update(
      id,
      (value) => value.copyWith(
        status: SelectionStatus.uncertain,
        message: sendFailure == null
            ? '学校尚未确认选中此教学班，请稍后核实；不会自动重新提交'
            : '$sendFailure；已选记录暂未确认结果，请稍后核实',
      ),
    );
  }

  Future<void> _success(String id, {bool beforeSubmission = false}) => _update(
    id,
    (value) => value.copyWith(
      status: SelectionStatus.succeeded,
      message: value.cancelRequested
          ? '停止前的请求已由学校确认选中'
          : beforeSubmission
          ? '学校已选记录包含此教学班，无需重复提交'
          : '学校已选记录已确认选中',
    ),
  );

  Future<bool> _canContinue(String id, SelectionAccessSession session) async {
    if (!_live(id, session) || _storageBlocked) return false;
    if (!session.isCurrent) {
      throw const LoginFailure(LoginFailureCode.expired, '账号已退出或重新登录，已停止后续尝试');
    }
    final item = _require(id);
    SelectionStatus? status;
    String? message;
    if (_cancellations.contains(id)) {
      status = SelectionStatus.cancelled;
      message = '已停止，未继续提交';
    } else if (_pauses[id] case final reason?) {
      status = SelectionStatus.paused;
      message = reason;
    } else if (!_clock().isBefore(item.expiresAt)) {
      status = SelectionStatus.expired;
      message = '已达到本次运行期限';
    }
    if (status == null) return item.isActive;
    await _update(
      id,
      (value) => value.copyWith(status: status, message: message),
    );
    return false;
  }

  Future<void> _wait(String id, String message) async {
    final session = _sessions[id];
    if (session == null || !await _canContinue(id, session)) return;
    final item = _require(id);
    final now = _clock();
    final wake = item.interval < item.expiresAt.difference(now)
        ? now.add(item.interval)
        : item.expiresAt;
    await _update(
      id,
      (value) => value.copyWith(
        status: SelectionStatus.waiting,
        nextCheckAt: wake,
        message: message,
      ),
    );
    if (!_live(id, session) ||
        _cancellations.contains(id) ||
        _pauses.containsKey(id)) {
      return;
    }
    _timers.remove(id)?.cancel();
    final delay = wake.difference(_clock());
    _timers[id] = Timer(delay.isNegative ? Duration.zero : delay, () {
      _timers.remove(id);
      _kick(item.target.scope);
    });
  }

  bool _live(String id, SelectionAccessSession session) =>
      !_closed && _find(id) != null && identical(_sessions[id], session);

  Future<void> _update(
    String id,
    SelectionOperation Function(SelectionOperation) update,
  ) => _commit(
    (items) => items.map((item) {
      if (item.id != id) return item;
      final next = update(item);
      return next.copyWith(updatedAt: _clock(), nextCheckAt: next.nextCheckAt);
    }).toList(),
  );

  Future<void> _commit(
    List<SelectionOperation> Function(List<SelectionOperation>) transform,
  ) {
    final operation = _writes.then((_) async {
      final next = List<SelectionOperation>.unmodifiable(
        transform(_operations),
      );
      try {
        await _store.writeOperations(next);
      } on SelectionStorageException catch (error) {
        _failure = error.message;
        _storageBlocked = true;
        _ready.clear();
        for (final timer in _timers.values) {
          timer.cancel();
        }
        _timers.clear();
        _emit();
        rethrow;
      }
      _operations = next;
      if (!_storageBlocked) _failure = null;
      _emit();
    });
    // Each caller gets its own write failure; a user retry can still persist.
    _writes = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> _syncHost() {
    final operation = _hostWrites.then(
      (_) => _syncRuntime(
        _storageBlocked
            ? 0
            : operations
                  .where(
                    (item) =>
                        item.isActive &&
                        _hosted.contains(item.id) &&
                        _sessions.containsKey(item.id) &&
                        !_pauses.containsKey(item.id),
                  )
                  .length,
      ),
    );
    _hostWrites = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  void _release(String id) {
    _timers.remove(id)?.cancel();
    _ready.remove(id);
    _hosted.remove(id);
    _sessions.remove(id);
    _verifications.remove(id);
  }

  SelectionOperation? _find(String id) =>
      operations.where((item) => item.id == id).firstOrNull;
  DateTime _deadline(Duration duration) {
    try {
      return _clock().add(duration);
    } on ArgumentError {
      throw const SelectionExecutionException('持续时间超出可用日期范围，请缩短后重试');
    }
  }

  SelectionOperation _require(String id) {
    _requireOpen();
    return _find(id) ?? (throw const SelectionExecutionException('此选课记录已移除'));
  }

  void _requireOpen() {
    if (_closed) throw const SelectionExecutionException('选课执行器已关闭');
  }

  void _emit() {
    if (!_closed) _changes.add(null);
  }

  Future<void> dispose() async {
    if (_closed) return;
    try {
      await pauseAll('软件已关闭，点击继续后重新查询');
    } finally {
      _closed = true;
      for (final timer in _timers.values) {
        timer.cancel();
      }
      _timers.clear();
      _ready.clear();
      _sessions.clear();
      await _writes;
      await _hostWrites;
      try {
        await _syncRuntime(0);
      } finally {
        await _changes.close();
      }
    }
  }
}

String? _knownError(Exception error) => switch (error) {
  LoginFailure(:final message) => message,
  SelectionException(:final message) => message,
  SelectionStorageException(:final message) => message,
  SelectionExecutionException(:final message) => message,
  _ => null,
};
