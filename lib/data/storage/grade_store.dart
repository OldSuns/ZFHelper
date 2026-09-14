import 'package:zf_core/zf_core.dart';

import 'academic_account.dart';

final class StoredGradeAccount {
  StoredGradeAccount({
    required this.account,
    this.snapshot,
    String? selectedTermKey,
  }) : selectedTermKey = _resolveSelection(snapshot, selectedTermKey);

  final AcademicAccountRecord account;
  final GradeSnapshot? snapshot;

  /// Null selects all records; aliases from older caches resolve to one group.
  final String? selectedTermKey;

  static String? _resolveSelection(GradeSnapshot? snapshot, String? key) {
    if (key == null) return null;
    final selected = snapshot?.resolveTermKey(key);
    if (selected == null) {
      throw const FormatException('Selected grade term is missing.');
    }
    return selected;
  }
}

final class GradeLibrary {
  GradeLibrary({
    List<StoredGradeAccount> accounts = const [],
    this.selectedAccount,
  }) : accounts = List.unmodifiable(accounts);

  final List<StoredGradeAccount> accounts;
  final AccountScope? selectedAccount;
}

abstract interface class GradeStore {
  Future<GradeLibrary> read();

  /// Replaces the library atomically; a failed write leaves the old data intact.
  Future<void> write(GradeLibrary library);
  Future<void> close();
}

final class GradeStorageException implements Exception {
  const GradeStorageException(this.message);

  final String message;

  @override
  String toString() => 'GradeStorageException: $message';
}
