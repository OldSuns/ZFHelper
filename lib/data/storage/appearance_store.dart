enum AppAppearance { system, light, dark }

abstract interface class AppearanceStore {
  Future<AppAppearance> read();
  Future<void> write(AppAppearance appearance);
}

final class AppearanceStorageException implements Exception {
  const AppearanceStorageException(this.message);

  final String message;

  @override
  String toString() => message;
}
