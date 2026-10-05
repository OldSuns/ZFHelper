import 'package:zf_core/zf_core.dart';

import 'academic_account.dart';

final class CourseRoundCache {
  CourseRoundCache({
    required this.roundKey,
    required List<CourseOffering> courses,
    required List<SelectedCourse> selectedCourses,
    required this.fetchedAt,
    this.selectedFetchedAt,
  }) : courses = List.unmodifiable(courses),
       selectedCourses = List.unmodifiable(selectedCourses);

  final String roundKey;
  final List<CourseOffering> courses;
  final List<SelectedCourse> selectedCourses;
  final DateTime fetchedAt;
  final DateTime? selectedFetchedAt;
}

final class StoredCourseAccount {
  StoredCourseAccount({
    required this.account,
    List<SelectionRound> rounds = const [],
    List<CourseRoundCache> catalogs = const [],
    this.selectedRoundKey,
    this.roundsFetchedAt,
  }) : rounds = List.unmodifiable(rounds),
       catalogs = List.unmodifiable(catalogs);

  final AcademicAccountRecord account;
  final List<SelectionRound> rounds;
  final List<CourseRoundCache> catalogs;
  final String? selectedRoundKey;
  final DateTime? roundsFetchedAt;

  SelectionRound? get selectedRound =>
      rounds.where((round) => round.key == selectedRoundKey).firstOrNull;

  CourseRoundCache? get selectedCatalog =>
      catalogs.where((cache) => cache.roundKey == selectedRoundKey).firstOrNull;
}

final class CourseLibrary {
  CourseLibrary({
    List<StoredCourseAccount> accounts = const [],
    this.selectedAccount,
  }) : accounts = List.unmodifiable(accounts);

  final List<StoredCourseAccount> accounts;
  final AccountScope? selectedAccount;
}

abstract interface class CourseStore {
  Future<CourseLibrary> read();

  /// Atomically replaces the library; failure leaves the previous value intact.
  Future<void> write(CourseLibrary library);

  /// Rejects new work and waits for every already accepted read or write.
  Future<void> close();
}
