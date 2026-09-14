import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum SelectionRuntimeMode { androidForegroundService, process }

enum SelectionRuntimeEventKind {
  stopRequested,
  runtimeStopped,
  capabilitiesChanged,
}

final class SelectionRuntimeCapabilities {
  const SelectionRuntimeCapabilities({
    required this.mode,
    required this.notificationsGranted,
    required this.running,
    required this.canStart,
    this.reason,
  });

  /// Process mode continues while the desktop application remains open.
  final SelectionRuntimeMode mode;
  final bool notificationsGranted;
  final bool running;
  final bool canStart;
  final String? reason;
}

final class SelectionRuntimeEvent {
  const SelectionRuntimeEvent({required this.kind, this.reason});

  final SelectionRuntimeEventKind kind;
  final String? reason;
}

final class SelectionRuntimeException implements Exception {
  const SelectionRuntimeException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'SelectionRuntimeException($code): $message';
}

/// Keeps one existing Dart executor alive; it never creates or resumes work.
abstract interface class SelectionRuntime {
  Stream<SelectionRuntimeEvent> get events;
  Future<SelectionRuntimeCapabilities> capabilities();

  /// Requests notification access only in response to a user's action.
  Future<SelectionRuntimeCapabilities> prepare();

  /// Await a positive count before starting work; zero releases the host.
  ///
  /// A notification stop or system interruption remains pending until the
  /// owner stops its work and acknowledges that state by synchronizing zero.
  Future<void> sync({required int activeWorkCount});
  Future<void> dispose();
}

SelectionRuntime createSelectionRuntime() => switch (defaultTargetPlatform) {
  TargetPlatform.android when !kIsWeb => _AndroidSelectionRuntime(),
  TargetPlatform.windows when !kIsWeb => _ProcessSelectionRuntime(),
  _ => throw const SelectionRuntimeException(
    'unsupported_platform',
    '当前平台不支持运行捡漏',
  ),
};

final class _AndroidSelectionRuntime implements SelectionRuntime {
  _AndroidSelectionRuntime() {
    _subscription = const EventChannel('zfhelper/selection_runtime/events')
        .receiveBroadcastStream()
        .listen((value) {
          try {
            _events.add(_readEvent(value));
          } on SelectionRuntimeException catch (error) {
            _events.addError(error);
          }
        }, onError: (Object error) => _events.addError(_platformError(error)));
  }

  static const _channel = MethodChannel('zfhelper/selection_runtime');
  final _events = StreamController<SelectionRuntimeEvent>.broadcast(sync: true);
  late final StreamSubscription<Object?> _subscription;
  Future<void> _writes = Future<void>.value();
  bool _closing = false;
  Future<void>? _disposing;

  @override
  Stream<SelectionRuntimeEvent> get events => _events.stream;

  @override
  Future<SelectionRuntimeCapabilities> capabilities() async {
    _ensureOpen();
    return _readCapabilities(await _invoke('capabilities'));
  }

  @override
  Future<SelectionRuntimeCapabilities> prepare() async {
    _ensureOpen();
    return _readCapabilities(await _invoke('prepare'));
  }

  @override
  Future<void> sync({required int activeWorkCount}) {
    _ensureOpen();
    if (activeWorkCount < 0) {
      throw ArgumentError.value(activeWorkCount, 'activeWorkCount');
    }
    return _sync(activeWorkCount);
  }

  Future<void> _sync(int count) {
    final operation = _writes.then((_) async {
      await _invoke('sync', {'activeWorkCount': count});
    });
    // Each caller receives its own failure; a later explicit stop can still run.
    _writes = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  @override
  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    _closing = true;
    try {
      await _sync(0);
    } finally {
      await _subscription.cancel();
      await _events.close();
    }
  }

  void _ensureOpen() {
    if (_closing) {
      throw const SelectionRuntimeException('runtime_closed', '捡漏运行宿主已关闭');
    }
  }

  static Future<Object?> _invoke(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      return await _channel.invokeMethod<Object?>(method, arguments);
    } on PlatformException catch (error) {
      throw _platformError(error);
    } on MissingPluginException {
      throw const SelectionRuntimeException(
        'runtime_unavailable',
        '无法连接 Android 后台运行宿主，请重新启动软件',
      );
    }
  }
}

final class _ProcessSelectionRuntime implements SelectionRuntime {
  final _events = StreamController<SelectionRuntimeEvent>.broadcast(sync: true);
  bool _running = false;
  bool _closed = false;

  @override
  Stream<SelectionRuntimeEvent> get events => _events.stream;

  @override
  Future<SelectionRuntimeCapabilities> capabilities() async =>
      SelectionRuntimeCapabilities(
        mode: SelectionRuntimeMode.process,
        notificationsGranted: true,
        running: _running,
        canStart: !_closed,
        reason: _closed ? '捡漏运行宿主已关闭' : null,
      );

  @override
  Future<SelectionRuntimeCapabilities> prepare() => capabilities();

  @override
  Future<void> sync({required int activeWorkCount}) async {
    if (_closed) {
      throw const SelectionRuntimeException('runtime_closed', '捡漏运行宿主已关闭');
    }
    if (activeWorkCount < 0) {
      throw ArgumentError.value(activeWorkCount, 'activeWorkCount');
    }
    _running = activeWorkCount > 0;
    _events.add(
      const SelectionRuntimeEvent(
        kind: SelectionRuntimeEventKind.capabilitiesChanged,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _running = false;
    await _events.close();
  }
}

SelectionRuntimeCapabilities _readCapabilities(Object? value) {
  if (value case {
    'mode': 'androidForegroundService',
    'notificationsGranted': final bool granted,
    'running': final bool running,
    'canStart': final bool canStart,
    'reason': final String? reason,
  }) {
    return SelectionRuntimeCapabilities(
      mode: SelectionRuntimeMode.androidForegroundService,
      notificationsGranted: granted,
      running: running,
      canStart: canStart,
      reason: reason,
    );
  }
  throw const SelectionRuntimeException('invalid_runtime_state', '后台运行状态无法识别');
}

SelectionRuntimeEvent _readEvent(Object? value) {
  if (value case {'kind': final String name, 'reason': final String? reason}) {
    final kind = switch (name) {
      'stopRequested' => SelectionRuntimeEventKind.stopRequested,
      'runtimeStopped' => SelectionRuntimeEventKind.runtimeStopped,
      'capabilitiesChanged' => SelectionRuntimeEventKind.capabilitiesChanged,
      _ => null,
    };
    if (kind != null) return SelectionRuntimeEvent(kind: kind, reason: reason);
  }
  throw const SelectionRuntimeException('invalid_runtime_event', '后台运行事件无法识别');
}

SelectionRuntimeException _platformError(Object error) => switch (error) {
  PlatformException(:final code, :final message) => SelectionRuntimeException(
    code,
    message ?? 'Android 后台运行操作失败',
  ),
  _ => const SelectionRuntimeException('runtime_unavailable', '后台运行连接已中断'),
};
