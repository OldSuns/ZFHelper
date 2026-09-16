import 'package:flutter/foundation.dart';
import 'package:zf_core/zf_core.dart';

/// An undoable local draft. Only the calendar page's save writes to storage.
class PeriodTimesViewModel extends ChangeNotifier {
  PeriodTimesViewModel({
    required List<PeriodTime> schoolTimes,
    required ScheduleSettings settings,
  }) : _school = PeriodTimePlan(periods: schoolTimes),
       _plan = PeriodTimePlan(
         periods: settings.useCustomPeriodTimes
             ? settings.periodTimes
             : schoolTimes,
         sections: settings.useCustomPeriodTimes
             ? settings.periodSections
             : const [],
       ),
       _custom = settings.useCustomPeriodTimes {
    _campus = normalizePeriodCampus(_plan.periods.firstOrNull?.campus);
  }

  final PeriodTimePlan _school;
  final _history = <({PeriodTimePlan plan, bool custom})>[];
  PeriodTimePlan _plan;
  bool _custom;
  String? _campus;
  String? _actionError;

  PeriodTimePlan get plan => _plan;
  bool get useCustomTimes => _custom;
  bool get canUndo => _history.isNotEmpty;
  bool get hasChanges => canUndo;
  String? get campus => _campus;
  List<PeriodTime> get periods => _plan.periodsForCampus(_campus);
  List<PeriodTimeSection> get sections =>
      _plan.sections.where((section) => section.campus == _campus).toList();

  List<String?> get campuses {
    final names = {
      for (final period in [..._school.periods, ..._plan.periods])
        normalizePeriodCampus(period.campus),
      _campus,
    }..remove(null);
    return [null, ...(names.cast<String>().toList()..sort())];
  }

  String? get validationError {
    try {
      _plan.validate();
      return null;
    } on PeriodTimeException catch (error) {
      return error.message;
    }
  }

  String? get error => _actionError ?? validationError;

  void selectCampus(String? value) {
    _campus = normalizePeriodCampus(value);
    _actionError = null;
    notifyListeners();
  }

  /// Conflicting clock ranges remain visible in the draft for correction.
  /// Invalid individual times or section definitions never replace the draft.
  bool change(PeriodTimePlan Function(PeriodTimePlan) update) {
    try {
      final next = update(_plan);
      _remember();
      _plan = next;
      _custom = true;
      _actionError = null;
      notifyListeners();
      return true;
    } on PeriodTimeException catch (error) {
      _actionError = error.message;
      notifyListeners();
      return false;
    }
  }

  void undo() {
    if (!canUndo) return;
    final previous = _history.removeLast();
    _plan = previous.plan;
    _custom = previous.custom;
    _actionError = null;
    notifyListeners();
  }

  void restoreSchool() {
    if (!_custom) return;
    _remember();
    _plan = _school;
    _custom = false;
    _actionError = null;
    notifyListeners();
  }

  void _remember() => _history.add((plan: _plan, custom: _custom));
}
