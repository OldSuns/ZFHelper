import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:zf_core/zf_core.dart';

import '../../../../data/repositories/course_repository.dart';
import '../../../../data/storage/course_store.dart';

enum CoursePageTab { available, selected, operations }

enum CourseFilter { all, available, unknownCapacity }

enum CourseSort { schoolOrder, name, available }

final class CoursesViewModel extends ChangeNotifier {
  CoursesViewModel({required CourseRepository repository})
    : _repository = repository,
      _data = repository.state {
    _subscription = repository.changes.listen(_onData);
  }

  final CourseRepository _repository;
  late final StreamSubscription<CourseRepositoryState> _subscription;
  CourseRepositoryState _data;
  CoursePageTab _tab = CoursePageTab.available;
  CourseFilter _filter = CourseFilter.all;
  CourseSort _sort = CourseSort.schoolOrder;
  String _query = '';

  CourseRepositoryState get data => _data;
  StoredCourseAccount? get account => data.account;
  CourseRoundCache? get catalog => data.catalog;
  SelectionRound? get round => account?.selectedRound;
  List<SelectionRound> get rounds => account?.rounds ?? const [];
  CoursePageTab get tab => _tab;
  CourseFilter get filter => _filter;
  CourseSort get sort => _sort;
  String get query => _query;
  bool get busy => data.loading || data.refreshing;
  bool get canRefresh => account != null && canQuery(account!.account.scope);
  int get activeCount =>
      data.operations.where((operation) => operation.isActive).length;
  int get uncertainCount => data.operations
      .where((operation) => operation.status == SelectionStatus.uncertain)
      .length;

  bool canQuery(AccountScope scope) => _repository.canQuery(scope);

  List<CourseOffering> get visibleCourses {
    final courses = catalog?.courses ?? const <CourseOffering>[];
    final result = courses.where((course) {
      final matches = switch (_filter) {
        CourseFilter.all => true,
        CourseFilter.available =>
          course.available != null && course.available! > 0,
        CourseFilter.unknownCapacity => course.available == null,
      };
      return matches &&
          _matches([
            course.name,
            course.courseId,
            course.teacher,
            course.time,
            course.location,
          ]);
    }).toList();
    if (_sort == CourseSort.name) {
      result.sort((a, b) => a.name.compareTo(b.name));
    } else if (_sort == CourseSort.available) {
      result.sort((a, b) {
        final first = a.available;
        final second = b.available;
        if (first == null) return second == null ? 0 : 1;
        if (second == null) return -1;
        return second.compareTo(first);
      });
    }
    return List.unmodifiable(result);
  }

  List<SelectedCourse> get selectedCourses => List.unmodifiable(
    (catalog?.selectedCourses ?? const <SelectedCourse>[]).where(
      (course) => _matches([
        course.name,
        course.courseId,
        course.teacher,
        course.time,
        course.location,
      ]),
    ),
  );

  List<SelectionOperation> get operations {
    final result = [...data.operations];
    int priority(SelectionOperation value) => value.isActive
        ? 0
        : value.status == SelectionStatus.uncertain
        ? 1
        : value.status == SelectionStatus.paused
        ? 2
        : 3;
    result.sort((a, b) {
      final rank = priority(a).compareTo(priority(b));
      return rank == 0 ? b.updatedAt.compareTo(a.updatedAt) : rank;
    });
    return List.unmodifiable(result);
  }

  bool? isSelected(CourseOffering course) {
    if (course.sectionId != null &&
        catalog?.selectedCourses.any(
              (selected) =>
                  selected.courseId == course.courseId &&
                  selected.sectionId == course.sectionId,
            ) ==
            true) {
      return true;
    }
    return course.isSelected;
  }

  bool _matches(List<String?> parts) {
    final needle = _query.trim().toLowerCase();
    return needle.isEmpty ||
        parts.whereType<String>().join(' ').toLowerCase().contains(needle);
  }

  void setTab(CoursePageTab value) {
    if (_tab == value) return;
    _tab = value;
    notifyListeners();
  }

  void setQuery(String value) {
    if (_query == value) return;
    _query = value;
    notifyListeners();
  }

  void setFilter(CourseFilter value) {
    if (_filter == value) return;
    _filter = value;
    notifyListeners();
  }

  void setSort(CourseSort value) {
    if (_sort == value) return;
    _sort = value;
    notifyListeners();
  }

  void clearFilters() {
    _query = '';
    _filter = CourseFilter.all;
    notifyListeners();
  }

  Future<void> initialize() => _repository.initialize();
  Future<bool> refresh() => _repository.refresh();
  Future<bool> selectAccount(AccountScope scope) =>
      _repository.selectAccount(scope);
  Future<bool> selectRound(String key) => _repository.selectRound(key);
  Future<CourseDetails?> sections(CourseOffering course) =>
      _repository.sections(course);

  Future<bool> start(
    CourseDetails details,
    CourseSection section, {
    required SelectionMode mode,
    Duration interval = const Duration(seconds: 5),
    Duration duration = const Duration(minutes: 30),
  }) => _repository.start(
    SelectionTarget(
      scope: details.account.scope,
      schoolName: details.account.schoolName,
      accountName: details.account.accountName,
      round: details.round,
      courseId: details.course.courseId,
      sectionId: section.sectionId,
      name: details.course.name,
      teacher: section.teacher,
      time: section.time,
      location: section.location,
    ),
    mode: mode,
    interval: interval,
    duration: duration,
  );

  Future<bool> stop(String id) => _repository.stop(id);
  Future<bool> resume(String id) => _repository.resume(id);
  Future<bool> verify(String id) => _repository.verify(id);
  Future<bool> clearHistory() => _repository.clearHistory();
  Future<bool> clearCurrentCache() => _repository.clearCurrentCache();
  void dismissFailure() => _repository.dismissFailure();

  void _onData(CourseRepositoryState next) {
    if (_data.library.selectedAccount != next.library.selectedAccount ||
        _data.account?.selectedRoundKey != next.account?.selectedRoundKey) {
      _query = '';
      _filter = CourseFilter.all;
    }
    _data = next;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
