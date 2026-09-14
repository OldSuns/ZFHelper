import 'package:flutter_test/flutter_test.dart';
import 'package:zfhelper/ui/features/schedule/view_models/timetable_view_model.dart';
import '../../../support/schedule_fakes.dart';

void main() {
  group('TimetableViewModel', () {
    late DateTime now;
    late TimetableViewModel viewModel;

    setUp(() {
      now = DateTime(2026, 9, 12, 13);
      final repository = testScheduleRepository();
      addTearDown(repository.dispose);
      viewModel = TimetableViewModel(repository: repository, clock: () => now);
    });

    tearDown(() => viewModel.dispose());

    test(
      'opens the current calendar week without assuming a teaching week',
      () {
        expect(viewModel.week.start, DateTime(2026, 9, 7));
        expect(viewModel.week.end, DateTime(2026, 9, 13));
        expect(viewModel.rangeLabel, '9月7日 — 9月13日');
        expect(viewModel.isCurrentWeek, isTrue);
      },
    );

    test('previous and next week notify observers with the new dates', () {
      final observedStarts = <DateTime>[];
      viewModel.addListener(() => observedStarts.add(viewModel.week.start));

      viewModel.previousWeek();
      viewModel.nextWeek();
      viewModel.nextWeek();

      expect(observedStarts, [
        DateTime(2026, 8, 31),
        DateTime(2026, 9, 7),
        DateTime(2026, 9, 14),
      ]);
      expect(viewModel.isCurrentWeek, isFalse);
    });

    test('return to current week reads the current clock', () {
      viewModel.previousWeek();
      now = DateTime(2026, 9, 21);

      viewModel.returnToCurrentWeek();

      expect(viewModel.week.start, DateTime(2026, 9, 21));
      expect(viewModel.today, now);
      expect(viewModel.isCurrentWeek, isTrue);
    });

    test('resuming on Monday follows a previously current week', () {
      now = DateTime(2026, 9, 14, 8);

      viewModel.refreshToday();

      expect(viewModel.week.start, DateTime(2026, 9, 14));
      expect(viewModel.isToday(DateTime(2026, 9, 14, 23)), isTrue);
      expect(viewModel.isToday(DateTime(2026, 9, 12)), isFalse);
    });

    test('resuming preserves a week the user was browsing', () {
      viewModel.previousWeek();
      now = DateTime(2026, 9, 14);

      viewModel.refreshToday();

      expect(viewModel.week.start, DateTime(2026, 8, 31));
      expect(viewModel.today, now);
      expect(viewModel.isCurrentWeek, isFalse);
    });

    test('refresh on the same calendar day does not rebuild observers', () {
      var notifications = 0;
      viewModel.addListener(() => notifications++);
      now = DateTime(2026, 9, 12, 23, 59);

      viewModel.refreshToday();

      expect(notifications, 0);
    });

    test('date range labels distinguish both years across New Year', () {
      now = DateTime(2027, 1, 1);
      viewModel.returnToCurrentWeek();

      expect(viewModel.rangeLabel, '2026年12月28日 — 2027年1月3日');
      expect(viewModel.yearLabel, '2026–2027年');
    });
  });
}
