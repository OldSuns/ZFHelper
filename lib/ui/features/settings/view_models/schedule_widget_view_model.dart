import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../data/repositories/schedule_repository.dart';
import '../../../../platform/schedule_widget_platform.dart';
import '../../../core/app_theme.dart';
import '../../schedule/view_models/schedule_widget_projection.dart';
import 'appearance_view_model.dart';

/// Publishes a derived, read-only timetable whenever its saved source changes.
final class ScheduleWidgetViewModel extends ChangeNotifier {
  ScheduleWidgetViewModel({
    required this._repository,
    required this._appearance,
    required this._platform,
    required this._clock,
  }) {
    _subscription = _repository.changes.listen((_) => _sourceChanged());
    _appearance.addListener(_sourceChanged);
  }

  final ScheduleRepository _repository;
  final AppearanceViewModel _appearance;
  final ScheduleWidgetPlatform _platform;
  final DateTime Function() _clock;
  late final StreamSubscription<ScheduleRepositoryState> _subscription;
  ScheduleWidgetCapabilities? _capabilities;
  ScheduleWidgetSettings _settings = const ScheduleWidgetSettings();
  bool _settingsInitialized = false;
  bool _settingsSaving = false;
  String? _failure;
  String? _publicationFailure;
  String? _statusFailure;
  String? _settingsReadFailure;
  String? _settingsSaveFailure;
  Object? _requestedSource;
  Future<bool>? _sync;
  bool _pending = false;
  bool _pinning = false;
  bool _disposed = false;

  ScheduleWidgetCapabilities? get capabilities => _capabilities;
  ScheduleWidgetSettings get settings => _settings;
  bool get settingsInitialized => _settingsInitialized;
  bool get settingsBusy => _settingsSaving;
  bool get busy => _sync != null || _pinning || _settingsSaving;
  bool get canSync => _repository.state.initialized && _appearance.initialized;
  String? get settingsReadFailure => _settingsReadFailure;
  String? get failure {
    final messages = [
      _failure,
      _publicationFailure,
      _statusFailure,
      _capabilities?.failure,
      _settingsSaveFailure,
      _settingsReadFailure,
    ].whereType<String>().toSet();
    return messages.isEmpty ? null : messages.join('；');
  }

  Stream<ScheduleWidgetLaunch> get launches => _platform.launches;

  String get sourceLabel {
    final state = _repository.state;
    final account = state.account?.account;
    if (account == null) return '还没有选择课表账号';
    return [
      account.schoolName,
      account.accountName,
      state.selectedTerm?.label,
    ].whereType<String>().join(' · ');
  }

  String? get sourceNotice {
    final state = _repository.state;
    if (!state.initialized) {
      return state.failure?.message ?? '正在读取本机课表';
    }
    if (!_appearance.initialized) {
      return _appearance.failure ?? '正在读取外观设置';
    }
    if (state.account == null) return '先添加账号并导入课表，小组件才会显示课程。';
    if (state.imported == null) return '所选学期尚未导入课表。';
    if (state.effective!.calendar.firstWeekMonday == null) {
      return '请先填写本学期第一周周一，小组件才能把课程对应到日期。';
    }
    return null;
  }

  Object _source() {
    final state = _repository.state;
    return (
      state.account?.account,
      state.selectedTerm?.key,
      state.imported,
      state.account?.settings[state.selectedTerm?.key],
      _appearance.appearance,
    );
  }

  void _sourceChanged() {
    if (_disposed) return;
    if (canSync && _source() != _requestedSource) {
      unawaited(synchronize());
    }
    notifyListeners();
  }

  Future<ScheduleWidgetLaunch?> consumeLaunch() async {
    try {
      return await _platform.consumeLaunch();
    } on ScheduleWidgetException catch (error) {
      _failure = error.message;
      _notify();
      return null;
    }
  }

  Future<void> refreshStatus() async {
    try {
      _capabilities = await _platform.capabilities();
      _statusFailure = null;
    } on ScheduleWidgetException catch (error) {
      _statusFailure = error.message;
    }
    await _refreshSettings();
    _notify();
  }

  Future<void> _refreshSettings() async {
    _settingsInitialized = false;
    try {
      _settings = await _platform.settings();
      _settingsInitialized = true;
      _settingsReadFailure = null;
    } on ScheduleWidgetException catch (error) {
      _settingsReadFailure = error.message;
    }
  }

  Future<bool> updateSettings({
    bool? showCountdown,
    bool? showLocation,
    bool? showTeacher,
  }) async {
    if (_disposed || busy || !_settingsInitialized) return false;
    final next = ScheduleWidgetSettings(
      showCountdown: showCountdown ?? _settings.showCountdown,
      showLocation: showLocation ?? _settings.showLocation,
      showTeacher: showTeacher ?? _settings.showTeacher,
    );
    if (next.showCountdown == _settings.showCountdown &&
        next.showLocation == _settings.showLocation &&
        next.showTeacher == _settings.showTeacher) {
      return true;
    }
    return _saveSettings(next);
  }

  Future<bool> resetSettings() async {
    if (_disposed || busy) return false;
    return _saveSettings(const ScheduleWidgetSettings());
  }

  Future<bool> _saveSettings(ScheduleWidgetSettings next) async {
    _settingsSaving = true;
    _settingsSaveFailure = null;
    _notify();
    try {
      await _platform.setSettings(next);
      _settings = next;
      _settingsInitialized = true;
      _settingsReadFailure = null;
      return true;
    } on ScheduleWidgetException catch (error) {
      _settingsSaveFailure = error.message;
      await _refreshSettings();
      return false;
    } finally {
      _settingsSaving = false;
      _notify();
    }
  }

  Future<bool> synchronize() {
    if (_disposed || !canSync) return Future.value(false);
    _requestedSource = _source();
    _pending = true;
    return _sync ??= Future<bool>.microtask(_publishPending);
  }

  Future<bool> _publishPending() async {
    _failure = null;
    _publicationFailure = null;
    _notify();
    try {
      do {
        while (_pending && !_disposed) {
          _pending = false;
          if (!canSync) return false;
          final payload = {
            ...projectScheduleWidget(_repository.state),
            'generatedAt': _clock().millisecondsSinceEpoch,
            'appearance': _appearance.appearance.name,
            'palette': _palette,
          };
          try {
            await _platform.publish(jsonEncode(payload));
            _publicationFailure = null;
          } on ScheduleWidgetException catch (error) {
            _publicationFailure = error.message;
          }
        }
        if (_disposed) return false;
        await refreshStatus();
        // Account or timetable changes can arrive while the host reads status.
      } while (_pending && !_disposed);
      return !_disposed &&
          _publicationFailure == null &&
          _statusFailure == null &&
          _capabilities?.failure == null;
    } finally {
      _sync = null;
      _notify();
    }
  }

  Future<String> requestPin() async {
    if (busy) return '正在同步小组件，请稍后重试。';
    _pinning = true;
    _notify();
    try {
      if (!await synchronize()) return failure ?? sourceNotice ?? '课表尚未同步到小组件';
      final accepted = await _platform.requestPin();
      return accepted
          ? '请在系统弹窗中确认添加；也可在桌面的小组件列表中找到 ZFHelper。'
          : '当前桌面不支持快捷添加，请长按桌面，从小组件列表添加 ZFHelper 课表。';
    } on ScheduleWidgetException catch (error) {
      _failure = error.message;
      return error.message;
    } finally {
      _pinning = false;
      _notify();
    }
  }

  static final _palette = {
    for (final brightness in Brightness.values)
      brightness.name: _colors(AppTheme.build(brightness).colorScheme),
  };

  static Map<String, int> _colors(ColorScheme colors) => {
    'surface': colors.surface.toARGB32(),
    'card': colors.primaryContainer.toARGB32(),
    'primary': colors.primary.toARGB32(),
    'text': colors.onSurface.toARGB32(),
    'secondary': colors.onSurfaceVariant.toARGB32(),
    'outline': colors.outlineVariant.toARGB32(),
  };

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _appearance.removeListener(_sourceChanged);
    unawaited(_subscription.cancel());
    unawaited(_platform.dispose());
    super.dispose();
  }
}
