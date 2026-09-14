import 'package:flutter/material.dart';

import '../../../../data/storage/appearance_store.dart';

final class AppearanceViewModel extends ChangeNotifier {
  AppearanceViewModel({required this._store});

  final AppearanceStore _store;
  AppAppearance _appearance = AppAppearance.system;
  bool _initialized = false;
  bool _saving = false;
  bool _disposed = false;
  Future<void>? _initializing;
  String? _failure;

  AppAppearance get appearance => _appearance;
  bool get initialized => _initialized;
  bool get busy => _initializing != null || _saving;
  String? get failure => _failure;
  String get label => labelFor(_appearance);

  ThemeMode get themeMode => switch (_appearance) {
    AppAppearance.system => ThemeMode.system,
    AppAppearance.light => ThemeMode.light,
    AppAppearance.dark => ThemeMode.dark,
  };

  static String labelFor(AppAppearance value) => switch (value) {
    AppAppearance.system => '跟随系统',
    AppAppearance.light => '浅色',
    AppAppearance.dark => '深色',
  };

  Future<void> initialize() {
    if (_initialized || _disposed) return Future.value();
    return _initializing ??= Future<void>.microtask(_load).whenComplete(() {
      _initializing = null;
      _notify();
    });
  }

  Future<void> _load() async {
    _failure = null;
    _notify();
    try {
      _appearance = await _store.read();
      _initialized = true;
    } on AppearanceStorageException catch (error) {
      _failure = error.message;
    }
  }

  Future<bool> select(AppAppearance value) async {
    if (busy || _disposed) return false;
    if (_initialized && value == _appearance && _failure == null) return true;
    _saving = true;
    _failure = null;
    _notify();
    try {
      await _store.write(value);
      _appearance = value;
      _initialized = true;
      return true;
    } on AppearanceStorageException catch (error) {
      _failure = error.message;
      return false;
    } finally {
      _saving = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
