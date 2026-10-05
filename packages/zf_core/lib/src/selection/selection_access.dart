import '../auth/account_scope.dart';
import 'selection_models.dart';

abstract interface class SelectionAccess {
  SelectionAccessSession open(AccountScope scope);
}

/// One account binding, retained when the user views a different account.
abstract interface class SelectionAccessSession {
  bool get isCurrent;
  Future<SelectionContext> readContext();
  Future<List<CourseOffering>> readCourses(
    SelectionContext context,
    SelectionRound round, {
    String keyword = '',
  });
  Future<List<CourseSection>> readSections(
    SelectionContext context,
    CourseOffering course,
  );
  Future<List<SelectedCourse>> readSelected(
    SelectionContext context, {
    SelectionRound? round,
  });
  Future<SelectionSubmission> submit(
    SelectionContext context,
    CourseOffering course,
    CourseSection section, {
    required bool Function() shouldSend,
  });
}

/// The owner cancelled before the mutation transport sent a request.
final class SelectionNotSentException implements Exception {
  const SelectionNotSentException();
}
