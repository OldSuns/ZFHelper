import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum ScheduleIslandSettingsTarget {
  notifications,
  channel,
  promotion,
  alarms,
  app,
}

const scheduleIslandLeadMinutes = [0, 5, 10, 15, 30];

/// Capsule content layout, mirrored by the native `capsuleStyle` preference.
enum ScheduleIslandCapsuleStyle {
  courseNameLocation,
  courseNameOnly;

  static ScheduleIslandCapsuleStyle parse(Object? value) =>
      ScheduleIslandCapsuleStyle.values.asNameMap()[value] ??
      (throw ScheduleIslandException('课程实况返回了无效状态（capsuleStyle）'));
}

final class ScheduleIslandStatus {
  const ScheduleIslandStatus({
    required this.enabled,
    required this.leadMinutes,
    required this.capsuleStyle,
    required this.androidVersion,
    required this.notificationsAllowed,
    required this.channelSupportsLiveUpdates,
    required this.exactAlarmsAllowed,
    required this.liveUpdatesSupported,
    required this.promotionAllowed,
    required this.notificationVisible,
    required this.previewVisible,
    required this.promoted,
    required this.hidden,
    this.sourceLabel,
    this.sourceNotice,
    this.activeLabel,
    this.nextUpdate,
    this.previewExpires,
    this.failure,
  });

  final bool enabled;
  final int leadMinutes;
  final ScheduleIslandCapsuleStyle capsuleStyle;
  final int androidVersion;
  final bool notificationsAllowed;
  final bool channelSupportsLiveUpdates;
  final bool exactAlarmsAllowed;
  final bool liveUpdatesSupported;
  final bool promotionAllowed;
  final bool notificationVisible;
  final bool previewVisible;
  final bool promoted;
  final bool hidden;
  final String? sourceLabel;
  final String? sourceNotice;
  final String? activeLabel;
  final DateTime? nextUpdate;
  final DateTime? previewExpires;
  final String? failure;

  factory ScheduleIslandStatus._fromPlatform(Object? value) {
    if (value is! Map<Object?, Object?>) _invalidStatus('status');
    final leadMinutes = _required<int>(value, 'leadMinutes');
    if (!scheduleIslandLeadMinutes.contains(leadMinutes)) {
      _invalidStatus('leadMinutes');
    }
    final androidVersion = _required<int>(value, 'androidVersion');
    if (androidVersion < 1) _invalidStatus('androidVersion');
    return ScheduleIslandStatus(
      enabled: _required<bool>(value, 'enabled'),
      leadMinutes: leadMinutes,
      capsuleStyle: ScheduleIslandCapsuleStyle.parse(
        _required<String>(value, 'capsuleStyle'),
      ),
      androidVersion: androidVersion,
      notificationsAllowed: _required<bool>(value, 'notificationsAllowed'),
      channelSupportsLiveUpdates: _required<bool>(
        value,
        'channelSupportsLiveUpdates',
      ),
      exactAlarmsAllowed: _required<bool>(value, 'exactAlarmsAllowed'),
      liveUpdatesSupported: _required<bool>(value, 'liveUpdatesSupported'),
      promotionAllowed: _required<bool>(value, 'promotionAllowed'),
      notificationVisible: _required<bool>(value, 'notificationVisible'),
      previewVisible: _required<bool>(value, 'previewVisible'),
      promoted: _required<bool>(value, 'promoted'),
      hidden: _required<bool>(value, 'hidden'),
      sourceLabel: _optional<String>(value, 'sourceLabel'),
      sourceNotice: _optional<String>(value, 'sourceNotice'),
      activeLabel: _optional<String>(value, 'activeLabel'),
      nextUpdate: _date(value, 'nextUpdate'),
      previewExpires: _date(value, 'previewExpires'),
      failure: _optional<String>(value, 'failure'),
    );
  }

  static DateTime? _date(Map<Object?, Object?> value, String key) {
    final milliseconds = _optional<int>(value, key);
    if (milliseconds == null) return null;
    try {
      return DateTime.fromMillisecondsSinceEpoch(milliseconds);
    } on ArgumentError {
      _invalidStatus(key);
    }
  }

  static T _required<T>(Map<Object?, Object?> value, String key) =>
      value[key] is T ? value[key] as T : _invalidStatus(key);

  static T? _optional<T>(Map<Object?, Object?> value, String key) =>
      value[key] == null ? null : _required<T>(value, key);

  static Never _invalidStatus(String key) =>
      throw ScheduleIslandException('课程实况返回了无效状态（$key）');
}

final class ScheduleIslandException implements Exception {
  const ScheduleIslandException(this.message);
  final String message;
}

abstract interface class ScheduleIslandPlatform {
  Future<ScheduleIslandStatus> status();
  Future<ScheduleIslandStatus> configure({
    required bool enabled,
    required int leadMinutes,
    required ScheduleIslandCapsuleStyle capsuleStyle,
  });
  Future<ScheduleIslandStatus> preview();
  Future<ScheduleIslandStatus> stopPreview();
  Future<ScheduleIslandStatus> restore();
  Future<void> openSettings(ScheduleIslandSettingsTarget target);
}

ScheduleIslandPlatform? createScheduleIslandPlatform() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android
    ? AndroidScheduleIslandPlatform()
    : null;

final class AndroidScheduleIslandPlatform implements ScheduleIslandPlatform {
  AndroidScheduleIslandPlatform({
    this._channel = const MethodChannel('zfhelper/schedule_widget'),
  });

  // The existing widget adapter owns this channel's incoming launch handler.
  final MethodChannel _channel;

  Future<Object?> _invoke(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<Object?>('island.$method', arguments);
    } on PlatformException catch (error) {
      throw ScheduleIslandException(error.message ?? '课程实况操作失败（${error.code}）');
    } on MissingPluginException {
      throw const ScheduleIslandException('课程实况服务不可用，请完整重启新版应用');
    }
  }

  Future<ScheduleIslandStatus> _status(
    String method, [
    Object? arguments,
  ]) async =>
      ScheduleIslandStatus._fromPlatform(await _invoke(method, arguments));

  @override
  Future<ScheduleIslandStatus> status() => _status('status');

  @override
  Future<ScheduleIslandStatus> configure({
    required bool enabled,
    required int leadMinutes,
    required ScheduleIslandCapsuleStyle capsuleStyle,
  }) => _status('configure', {
    'enabled': enabled,
    'leadMinutes': leadMinutes,
    'capsuleStyle': capsuleStyle.name,
  });

  @override
  Future<ScheduleIslandStatus> preview() => _status('preview');

  @override
  Future<ScheduleIslandStatus> stopPreview() => _status('stopPreview');

  @override
  Future<ScheduleIslandStatus> restore() => _status('restore');

  @override
  Future<void> openSettings(ScheduleIslandSettingsTarget target) async =>
      _invoke('openSettings', {'page': target.name});
}
