import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:zf_core/zf_core.dart';

import '../../../../data/repositories/grade_repository.dart';
import '../../../../data/storage/grade_store.dart';

enum GradeSort {
  schoolOrder,
  scoreDescending,
  creditDescending,
  gradePointDescending,
  name,
}

enum GradeFilter { all, nonNumeric, retakes, failed }

final class GradesViewModel extends ChangeNotifier {
  GradesViewModel({required GradeRepository repository})
    : _repository = repository,
      _data = repository.state {
    _subscription = repository.changes.listen(_onData);
  }

  final GradeRepository _repository;
  late final StreamSubscription<GradeRepositoryState> _subscription;
  GradeRepositoryState _data;
  String _query = '';
  GradeSort _sort = GradeSort.schoolOrder;
  GradeFilter _filter = GradeFilter.all;

  GradeRepositoryState get data => _data;
  StoredGradeAccount? get account => data.account;
  GradeSnapshot? get snapshot => data.snapshot;
  String get query => _query;
  GradeSort get sort => _sort;
  GradeFilter get filter => _filter;
  String? get selectedTermKey => account?.selectedTermKey;
  bool get canRefresh =>
      account != null && _repository.canRefresh(account!.account.scope);
  bool get hasUnassignedTerms =>
      snapshot?.records.any((record) => record.term == null) ?? false;

  List<GradeTermGroup> get terms => snapshot?.terms ?? const [];

  String get termLabel {
    if (selectedTermKey == null) return '全部学期';
    if (selectedTermKey == unassignedGradeTermKey) return '未标注学期';
    return terms.firstWhere((term) => term.key == selectedTermKey).label;
  }

  List<GradeRecord> get visibleRecords {
    final records = snapshot?.records ?? const <GradeRecord>[];
    final needle = _query.trim().toLowerCase();
    final result = records.where((record) {
      if (selectedTermKey != null && record.termKey != selectedTermKey) {
        return false;
      }
      if (!_matchesFilter(record)) return false;
      return needle.isEmpty ||
          [
            record.name,
            record.courseCode,
            record.teacher,
            record.courseNature,
            record.courseCategory,
            record.college,
          ].whereType<String>().join(' ').toLowerCase().contains(needle);
    }).toList();
    if (_sort == GradeSort.schoolOrder) return List.unmodifiable(result);
    final order = {
      for (var index = 0; index < records.length; index++)
        records[index].id: index,
    };
    result.sort((a, b) {
      final comparison = switch (_sort) {
        GradeSort.schoolOrder => 0,
        GradeSort.name => a.name.compareTo(b.name),
        GradeSort.scoreDescending => _compareNumber(
          a.numericScore,
          b.numericScore,
        ),
        GradeSort.creditDescending => _compareNumber(
          a.creditValue,
          b.creditValue,
        ),
        GradeSort.gradePointDescending => _compareNumber(
          a.gradePointValue,
          b.gradePointValue,
        ),
      };
      return comparison == 0
          ? order[a.id]!.compareTo(order[b.id]!)
          : comparison;
    });
    return List.unmodifiable(result);
  }

  GradeSummary get summary => GradeSummary(visibleRecords);

  bool _matchesFilter(GradeRecord record) => switch (_filter) {
    GradeFilter.all => true,
    GradeFilter.nonNumeric => record.numericScore == null,
    GradeFilter.failed => record.passed == false,
    GradeFilter.retakes =>
      const {
            '1',
            '是',
            'true',
            'yes',
          }.contains(record.retake?.trim().toLowerCase()) ||
          RegExp('补考|重修|重考')
              .hasMatch('${record.retake ?? ''} ${record.examNature ?? ''}'),
  };

  static int _compareNumber(double? a, double? b) {
    if (a == null) return b == null ? 0 : 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }

  void setQuery(String value) {
    if (_query == value) return;
    _query = value;
    notifyListeners();
  }

  void setSort(GradeSort value) {
    if (_sort == value) return;
    _sort = value;
    notifyListeners();
  }

  void setFilter(GradeFilter value) {
    if (_filter == value) return;
    _filter = value;
    notifyListeners();
  }

  Future<void> initialize() => _repository.initialize();
  Future<bool> refresh() => _repository.refresh();
  Future<bool> selectTerm(String? key) => _repository.selectTerm(key);
  Future<bool> selectAccount(AccountScope scope) =>
      _repository.selectAccount(scope);
  Future<bool> clearCurrentCache() => _repository.clearCurrentCache();
  Future<void> retryLocalLoad() => _repository.retryLocalLoad();
  void dismissFailure() => _repository.dismissFailure();

  void _onData(GradeRepositoryState next) {
    if (_data.library.selectedAccount != next.library.selectedAccount) {
      _query = '';
      _filter = GradeFilter.all;
      _sort = GradeSort.schoolOrder;
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
