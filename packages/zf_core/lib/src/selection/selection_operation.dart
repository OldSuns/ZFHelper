import '../auth/account_scope.dart';
import 'selection_models.dart';

enum SelectionMode { immediate, watch }

enum SelectionStatus {
  queued,
  checking,
  submitting,
  verifying,
  waiting,
  paused,
  succeeded,
  rejected,
  uncertain,
  failed,
  cancelled,
  expired,
}

final class SelectionTarget {
  const SelectionTarget({
    required this.scope,
    required this.schoolName,
    required this.accountName,
    required this.round,
    required this.courseId,
    required this.sectionId,
    required this.name,
    this.teacher,
    this.time,
    this.location,
  });

  final AccountScope scope;
  final String schoolName;
  final String accountName;
  final SelectionRound round;
  final String courseId;
  final String sectionId;
  final String name;
  final String? teacher;
  final String? time;
  final String? location;

  bool matches(SelectedCourse course) =>
      courseId == course.courseId &&
      sectionId.isNotEmpty &&
      sectionId == course.sectionId &&
      (round.term == null || course.term == null || round.term == course.term);

  bool sameClass(SelectionTarget other) =>
      scope == other.scope &&
      (round.term != null && other.round.term != null
          ? round.term == other.round.term
          : round.key == other.round.key) &&
      courseId == other.courseId &&
      sectionId == other.sectionId;
}

/// A manually started operation. No future start time or unattended schedule.
final class SelectionOperation {
  const SelectionOperation({
    required this.id,
    required this.target,
    required this.mode,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.expiresAt,
    required this.interval,
    required this.duration,
    this.checks = 0,
    this.submissions = 0,
    this.message = '',
    this.nextCheckAt,
    this.cancelRequested = false,
  });

  final String id;
  final SelectionTarget target;
  final SelectionMode mode;
  final SelectionStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime expiresAt;
  final Duration interval;
  final Duration duration;
  final int checks;
  final int submissions;
  final String message;
  final DateTime? nextCheckAt;
  final bool cancelRequested;

  bool get isActive => const {
    SelectionStatus.queued,
    SelectionStatus.checking,
    SelectionStatus.submitting,
    SelectionStatus.verifying,
    SelectionStatus.waiting,
  }.contains(status);

  bool get mayHaveSubmitted => const {
    SelectionStatus.submitting,
    SelectionStatus.verifying,
    SelectionStatus.uncertain,
  }.contains(status);

  SelectionOperation copyWith({
    SelectionStatus? status,
    DateTime? updatedAt,
    DateTime? expiresAt,
    int? checks,
    int? submissions,
    String? message,
    DateTime? nextCheckAt,
    bool? cancelRequested,
  }) => SelectionOperation(
    id: id,
    target: target,
    mode: mode,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    expiresAt: expiresAt ?? this.expiresAt,
    interval: interval,
    duration: duration,
    checks: checks ?? this.checks,
    submissions: submissions ?? this.submissions,
    message: message ?? this.message,
    nextCheckAt: nextCheckAt,
    cancelRequested: cancelRequested ?? this.cancelRequested,
  );
}

abstract interface class SelectionOperationStore {
  Future<List<SelectionOperation>> readOperations();
  Future<void> writeOperations(List<SelectionOperation> operations);
}

final class SelectionStorageException implements Exception {
  const SelectionStorageException(this.message);
  final String message;
  @override
  String toString() => 'SelectionStorageException: $message';
}
