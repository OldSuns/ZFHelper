import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../platform/schedule_island_platform.dart';

/// Controls native reminder settings; the widget publisher owns timetable sync.
final class ScheduleIslandViewModel extends ChangeNotifier {
  ScheduleIslandViewModel({required this._platform});

  final ScheduleIslandPlatform _platform;
  ScheduleIslandStatus? _status;
  String? _failure;
  Future<void> _pending = Future.value();
  int _pendingOperations = 0;
  bool _disposed = false;
  Timer? _previewExpiryTimer;

  // NotificationManager removes expired notifications asynchronously.
  static const _expiryRefreshDelay = Duration(seconds: 1);

  ScheduleIslandStatus? get status => _status;
  String? get failure => _failure ?? _status?.failure;
  bool get busy => _pendingOperations > 0;

  Future<void> refreshStatus() => _run(_platform.status);

  Future<void> setEnabled(bool enabled) => _configure(enabled: enabled);

  Future<void> setLeadMinutes(int minutes) => _configure(leadMinutes: minutes);

  Future<void> _configure({bool? enabled, int? leadMinutes}) => _run(() {
    final current = _status;
    if (current == null) {
      throw const ScheduleIslandException('请先读取课程实况设置，再进行修改');
    }
    return _platform.configure(
      enabled: enabled ?? current.enabled,
      leadMinutes: leadMinutes ?? current.leadMinutes,
    );
  });

  Future<void> preview() => _run(_platform.preview);

  Future<void> stopPreview() => _run(_platform.stopPreview);

  Future<void> restore() => _run(_platform.restore);

  Future<void> openSettings(ScheduleIslandSettingsTarget target) =>
      _run(() async {
        await _platform.openSettings(target);
        return null;
      });

  Future<void> _run(Future<ScheduleIslandStatus?> Function() operation) {
    if (_disposed) return Future.value();
    _pendingOperations++;
    _notify();
    // Keep resume/status reads in order with full-setting writes.
    return _pending = _pending.then((_) async {
      try {
        if (_disposed) return;
        _failure = null;
        final next = await operation();
        if (!_disposed && next != null) {
          _status = next;
          _schedulePreviewRefresh(next);
        }
      } on ScheduleIslandException catch (error) {
        if (!_disposed) _failure = error.message;
      } finally {
        _pendingOperations--;
        _notify();
      }
    });
  }

  void _schedulePreviewRefresh(ScheduleIslandStatus status) {
    _previewExpiryTimer?.cancel();
    _previewExpiryTimer = null;
    final expiry = status.previewExpires;
    if (!status.previewVisible || expiry == null) return;
    final remaining = expiry
        .add(_expiryRefreshDelay)
        .difference(DateTime.now());
    if (remaining <= Duration.zero) return;
    _previewExpiryTimer = Timer(remaining, () {
      _previewExpiryTimer = null;
      unawaited(refreshStatus());
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _previewExpiryTimer?.cancel();
    super.dispose();
  }
}
