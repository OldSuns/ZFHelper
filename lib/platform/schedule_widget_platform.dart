import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

final class ScheduleWidgetLaunchSource {
  const ScheduleWidgetLaunchSource({
    required this.schoolId,
    required this.accountId,
    required this.termKey,
  });

  final String schoolId;
  final String accountId;
  final String termKey;
}

final class ScheduleWidgetLaunch {
  const ScheduleWidgetLaunch({required this.date, this.source});

  final DateTime date;
  final ScheduleWidgetLaunchSource? source;
}

final class ScheduleWidgetCapabilities {
  const ScheduleWidgetCapabilities({
    required this.canPin,
    required this.count,
    this.lastSync,
    this.failure,
  });

  final bool canPin;
  final int count;
  final DateTime? lastSync;
  final String? failure;
}

final class ScheduleWidgetException implements Exception {
  const ScheduleWidgetException(this.message);
  final String message;
}

abstract interface class ScheduleWidgetPlatform {
  Stream<ScheduleWidgetLaunch> get launches;
  Future<ScheduleWidgetCapabilities> capabilities();
  Future<void> publish(String payload);
  Future<bool> requestPin();
  Future<ScheduleWidgetLaunch?> consumeLaunch();
  Future<void> dispose();
}

ScheduleWidgetPlatform? createScheduleWidgetPlatform() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android
    ? AndroidScheduleWidgetPlatform()
    : null;

final class AndroidScheduleWidgetPlatform implements ScheduleWidgetPlatform {
  AndroidScheduleWidgetPlatform({
    this._channel = const MethodChannel('zfhelper/schedule_widget'),
  }) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'openSchedule') throw MissingPluginException();
      _launches.add(_readLaunch(call.arguments));
    });
  }

  final MethodChannel _channel;
  final _launches = StreamController<ScheduleWidgetLaunch>.broadcast(
    sync: true,
  );

  @override
  Stream<ScheduleWidgetLaunch> get launches => _launches.stream;

  Future<Object?> _invoke(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<Object?>(method, arguments);
    } on PlatformException catch (error) {
      throw ScheduleWidgetException(
        error.message ?? '桌面小组件操作失败（${error.code}）',
      );
    } on MissingPluginException {
      throw const ScheduleWidgetException('桌面小组件服务不可用，请完整重启新版应用');
    }
  }

  @override
  Future<ScheduleWidgetCapabilities> capabilities() async {
    final value = await _invoke('capabilities');
    if (value
        case {
          'supported': true,
          'canPin': final bool canPin,
          'count': final int count,
        }
        when count >= 0) {
      final lastSync = value['lastSync'];
      final failure = value['failure'];
      if ((lastSync != null && lastSync is! int) ||
          (failure != null && failure is! String)) {
        throw const ScheduleWidgetException('桌面小组件返回了无效状态');
      }
      return ScheduleWidgetCapabilities(
        canPin: canPin,
        count: count,
        lastSync: lastSync == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(lastSync as int),
        failure: failure as String?,
      );
    }
    throw const ScheduleWidgetException('桌面小组件返回了无效状态');
  }

  @override
  Future<void> publish(String payload) async =>
      _invoke('publish', {'payload': payload});

  @override
  Future<bool> requestPin() async {
    final value = await _invoke('requestPin');
    if (value is bool) return value;
    throw const ScheduleWidgetException('桌面未返回添加小组件的请求结果');
  }

  @override
  Future<ScheduleWidgetLaunch?> consumeLaunch() async {
    final value = await _invoke('consumeLaunch');
    return value == null ? null : _readLaunch(value);
  }

  static ScheduleWidgetLaunch _readLaunch(Object? value) {
    if (value is String) {
      return ScheduleWidgetLaunch(date: _readDate(value));
    }
    if (value is! Map<Object?, Object?> || value.length != 2) {
      throw const ScheduleWidgetException('系统传来的课表入口无效');
    }
    final source = value['source'];
    if (source
        case {
          'schoolId': final String schoolId,
          'accountId': final String accountId,
          'termKey': final String termKey,
        }
        when source.length == 3 &&
            schoolId.trim().isNotEmpty &&
            accountId.trim().isNotEmpty &&
            termKey.trim().isNotEmpty) {
      return ScheduleWidgetLaunch(
        date: _readDate(value['date']),
        source: ScheduleWidgetLaunchSource(
          schoolId: schoolId,
          accountId: accountId,
          termKey: termKey,
        ),
      );
    }
    throw const ScheduleWidgetException('课程提醒来源信息无效');
  }

  static DateTime _readDate(Object? value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw const ScheduleWidgetException('系统传来的课表日期无效');
    }
    final date = DateTime.tryParse(value);
    if (date == null || date.toIso8601String().split('T').first != value) {
      throw const ScheduleWidgetException('系统传来的课表日期无效');
    }
    return date;
  }

  @override
  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _launches.close();
  }
}
