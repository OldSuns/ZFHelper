import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zf_core/zf_core.dart';
import 'package:zfhelper/ui/core/app_theme.dart';
import 'package:zfhelper/ui/features/schedule/views/schedule_calendar_page.dart';

void main() {
  testWidgets('unknown calendars do not guess the first date or term length', (tester) async {
    await _openCalendar(tester, snapshot: _snapshot(unknownCalendar: true));

    expect(_text(tester, 'calendar-first-monday'), isEmpty);
    expect(_text(tester, 'calendar-total-weeks'), isEmpty);
    expect(find.text('当前教学周待确认'), findsOneWidget);
    await _tap(tester, 'calendar-pick-date');
    final picker = tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
    expect(picker.initialDate, isNull);
    expect(picker.selectableDayPredicate!(DateTime(2026, 9, 7)), isTrue);
    expect(picker.selectableDayPredicate!(DateTime(2026, 9, 8)), isFalse);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    expect(_text(tester, 'calendar-first-monday'), isEmpty);
  });

  testWidgets('date selection accepts a Monday and previews the real teaching week', (tester) async {
    final result = await _openCalendar(tester, snapshot: _snapshot(unknownCalendar: true));
    await _tap(tester, 'calendar-pick-date');
    await tester.tap(find.text('7').last);
    await tester.tap(find.text('选定').last);
    await tester.pumpAndSettle();

    expect(_text(tester, 'calendar-first-monday'), '2026-09-07');
    expect(find.text('按此校历，今天是第 1 教学周'), findsOneWidget);
    await _enter(tester, 'calendar-total-weeks', '32');
    await _tap(tester, 'calendar-save');

    final settings = (await result.future)!;
    expect(settings.calendarOverride!.source, TeachingCalendarSource.user);
    expect(settings.calendarOverride!.firstWeekMonday, DateTime(2026, 9, 7));
    expect(settings.calendarOverride!.totalWeeks, 32);
  });

  testWidgets('saving calendar changes preserves local courses and hidden imports', (tester) async {
    final original = _settings();
    final result = await _openCalendar(tester, settings: original);
    await _enter(tester, 'calendar-first-monday', '2026-09-14');
    await _enter(tester, 'calendar-total-weeks', '');
    expect(find.text('今天处于开学前'), findsOneWidget);
    await _tap(tester, 'calendar-save');

    final edited = (await result.future)!;
    expect(edited.calendarOverride!.firstWeekMonday, DateTime(2026, 9, 14));
    expect(edited.calendarOverride!.totalWeeks, isNull);
    expect(edited.localEntries.single.id, 'local-study');
    expect(edited.hiddenEntryIds, {'school-course'});
    expect(edited.useCustomPeriodTimes, isTrue);
    expect(edited.periodTimes.single.startMinutes, 8 * 60 + 10);
    expect(original.calendarOverride!.firstWeekMonday, DateTime(2026, 9, 7));
  });

  testWidgets('rejects non-Mondays and invalid civil dates instead of correcting silently', (tester) async {
    final result = await _openCalendar(tester);
    await _enter(tester, 'calendar-first-monday', '2026-09-08');
    await _tap(tester, 'calendar-save');
    expect(find.text('第一教学周必须从周一开始'), findsWidgets);
    expect(result.isCompleted, isFalse);

    await _enter(tester, 'calendar-first-monday', '2026-02-30');
    await _tap(tester, 'calendar-save');
    expect(find.text('请按 YYYY-MM-DD 填写有效日期'), findsWidgets);
    expect(result.isCompleted, isFalse);
  });

  testWidgets('restoring the school calendar clears only its override', (tester) async {
    final original = _settings();
    final result = await _openCalendar(tester, settings: original);
    await _tap(tester, 'calendar-restore');
    expect(_text(tester, 'calendar-first-monday'), '2026-08-31');
    expect(_text(tester, 'calendar-total-weeks'), '20');
    await _tap(tester, 'calendar-save');

    final edited = (await result.future)!;
    expect(edited.calendarOverride, isNull);
    expect(edited.periodTimes.single.startMinutes, 8 * 60 + 10);
    expect(edited.useCustomPeriodTimes, isTrue);
    expect(edited.localEntries.single.id, 'local-study');
    expect(edited.hiddenEntryIds, original.hiddenEntryIds);
  });

  testWidgets('editing school times creates an override and keeps its campus', (tester) async {
    final snapshot = _snapshot();
    final result = await _openCalendar(tester, snapshot: snapshot);
    await _enter(tester, 'period-0-end', '09:00');
    await _tap(tester, 'calendar-save');

    final settings = (await result.future)!;
    expect(settings.useCustomPeriodTimes, isTrue);
    expect(settings.periodTimes.single.campus, '北校区');
    expect(settings.periodTimes.single.endMinutes, 9 * 60);
    expect(snapshot.periodTimes.single.endMinutes, 8 * 60 + 45);
  });

  testWidgets('new periods start empty and accept periods beyond the imported range', (tester) async {
    final result = await _openCalendar(tester);
    await _tap(tester, 'period-add');
    await _reveal(tester, 'period-1-number');
    expect(_text(tester, 'period-1-number'), isEmpty);
    expect(_text(tester, 'period-1-start'), isEmpty);
    expect(_text(tester, 'period-1-end'), isEmpty);
    await _tap(tester, 'calendar-save');
    expect(find.text('作息 2：请填写大于 0 的节次'), findsOneWidget);
    expect(result.isCompleted, isFalse);

    await _enter(tester, 'period-1-number', '14');
    await _enter(tester, 'period-1-start', '20:10');
    await _enter(tester, 'period-1-end', '20:55');
    await _tap(tester, 'calendar-save');
    final settings = (await result.future)!;
    final added = settings.periodTimes.singleWhere((period) => period.number == 14);
    expect(added.startMinutes, 20 * 60 + 10);
    expect(added.endMinutes, 20 * 60 + 55);
    expect(added.campus, isNull);
  });

  testWidgets('deleting the final period explicitly clears the displayed timetable times', (tester) async {
    final snapshot = _snapshot();
    final result = await _openCalendar(tester, snapshot: snapshot);
    await _tap(tester, 'period-0-remove');
    await _tap(tester, 'calendar-save');

    final settings = (await result.future)!;
    expect(settings.useCustomPeriodTimes, isTrue);
    expect(settings.periodTimes, isEmpty);
    expect(settings.applyTo(snapshot).periodTimes, isEmpty);
    expect(snapshot.periodTimes, hasLength(1));
  });

  testWidgets('restoring school times also works after an explicit empty override', (tester) async {
    final snapshot = _snapshot();
    final initial = _settings().copyWith(periodTimes: [], useCustomPeriodTimes: true);
    final result = await _openCalendar(tester, snapshot: snapshot, settings: initial);
    await _tap(tester, 'period-restore');
    await _tap(tester, 'calendar-save');

    final restored = (await result.future)!;
    expect(restored.useCustomPeriodTimes, isFalse);
    expect(restored.periodTimes, isEmpty);
    expect(restored.applyTo(snapshot).periodTimes.single.startMinutes, 8 * 60);
    expect(restored.calendarOverride!.firstWeekMonday, DateTime(2026, 9, 7));
    expect(restored.localEntries.single.id, 'local-study');
    expect(restored.hiddenEntryIds, {'school-course'});
  });

  testWidgets('rejects duplicate period numbers within one campus', (tester) async {
    final snapshot = _snapshot(periods: [
      PeriodTime(number: 1, startMinutes: 480, endMinutes: 525, campus: '北校区'),
      PeriodTime(number: 1, startMinutes: 490, endMinutes: 535, campus: '南校区'),
    ]);
    final result = await _openCalendar(tester, snapshot: snapshot);
    await _enter(tester, 'period-1-campus', '北校区');
    await _tap(tester, 'calendar-save');

    expect(find.text('北校区的第 1 节重复，请合并或修改节次'), findsOneWidget);
    expect(result.isCompleted, isFalse);
  });

  testWidgets('preserves distinct campus schedules with the same period number', (tester) async {
    final snapshot = _snapshot(periods: [
      PeriodTime(number: 1, startMinutes: 480, endMinutes: 525, campus: '北校区'),
      PeriodTime(number: 1, startMinutes: 490, endMinutes: 535, campus: '南校区'),
    ]);
    final result = await _openCalendar(tester, snapshot: snapshot);
    await _enter(tester, 'period-1-end', '09:00');
    await _tap(tester, 'calendar-save');

    final settings = (await result.future)!;
    expect(settings.periodTimes, hasLength(2));
    expect(settings.periodTimes.map((period) => period.campus).toSet(), {'北校区', '南校区'});
    expect(settings.periodTimes.every((period) => period.number == 1), isTrue);
  });

  testWidgets('rejects overlaps and reversed times without losing edited values', (tester) async {
    final result = await _openCalendar(tester, settings: ScheduleSettings(periodTimes: [
      PeriodTime(number: 1, startMinutes: 480, endMinutes: 525),
      PeriodTime(number: 2, startMinutes: 520, endMinutes: 565),
    ]));
    await _tap(tester, 'calendar-save');
    expect(find.text('未指定校区的第 2 节早于或重叠第 1 节，请核对时间'), findsOneWidget);
    expect(result.isCompleted, isFalse);

    await _enter(tester, 'period-1-end', '08:00');
    await _tap(tester, 'calendar-save');
    expect(find.text('作息 2：结束时间必须晚于开始时间'), findsOneWidget);
    expect(result.isCompleted, isFalse);
    await _reveal(tester, 'period-1-end');
    expect(_text(tester, 'period-1-end'), '08:00');
  });

  testWidgets('time picker uses 24-hour input and leaves a new time empty until chosen', (tester) async {
    await _openCalendar(tester, snapshot: _snapshot(periods: []));
    await _tap(tester, 'period-add');
    await _reveal(tester, 'period-0-start');
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('period-0-start')),
      matching: find.byTooltip('选择开始时间'),
    ));
    await tester.pumpAndSettle();
    final inputs = find.descendant(of: find.byType(TimePickerDialog), matching: find.byType(TextField));
    expect(inputs, findsNWidgets(2));
    expect(tester.widget<TextField>(inputs.first).controller!.text, isEmpty);
    await tester.enterText(inputs.first, '13');
    await tester.enterText(inputs.last, '15');
    await tester.tap(find.text('选定').last);
    await tester.pumpAndSettle();

    expect(_text(tester, 'period-0-start'), '13:15');
  });

  testWidgets('cancel leaves the original settings unchanged', (tester) async {
    final original = _settings();
    final result = await _openCalendar(tester, settings: original);
    await _enter(tester, 'calendar-first-monday', '2026-09-14');
    await tester.tap(find.byTooltip('取消设置'));
    await tester.pumpAndSettle();

    expect(await result.future, isNull);
    expect(original.calendarOverride!.firstWeekMonday, DateTime(2026, 9, 7));
    expect(original.periodTimes.single.startMinutes, 490);
  });

  for (final layout in [
    (size: const Size(375, 740), scale: 1.0, brightness: Brightness.light, keyboard: 0.0),
    (size: const Size(320, 640), scale: 2.0, brightness: Brightness.dark, keyboard: 200.0),
    (size: const Size(760, 420), scale: 2.0, brightness: Brightness.light, keyboard: 160.0),
    (size: const Size(1200, 800), scale: 2.0, brightness: Brightness.dark, keyboard: 0.0),
  ]) {
    testWidgets('calendar form works at ${layout.size} and ${layout.scale} text scale', (tester) async {
      final result = await _openCalendar(
        tester,
        size: layout.size,
        textScale: layout.scale,
        brightness: layout.brightness,
      );
      tester.view.viewInsets = FakeViewPadding(bottom: layout.keyboard);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await _enter(tester, 'period-0-end', '09:00');
      final save = find.byKey(const ValueKey('calendar-save'));
      expect(tester.getBottomRight(save).dy, lessThanOrEqualTo(layout.size.height - layout.keyboard));
      expect(tester.takeException(), isNull);
      await _tap(tester, 'calendar-save');
      expect((await result.future)!.periodTimes.single.endMinutes, 540);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<Completer<ScheduleSettings?>> _openCalendar(
  WidgetTester tester, {
  ScheduleSnapshot? snapshot,
  ScheduleSettings? settings,
  Size size = const Size(430, 1000),
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  final result = Completer<ScheduleSettings?>();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(brightness),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result.complete(await Navigator.of(context).push<ScheduleSettings>(
                MaterialPageRoute(builder: (_) => ScheduleCalendarPage(
                  snapshot: snapshot ?? _snapshot(),
                  settings: settings ?? ScheduleSettings(),
                  today: DateTime(2026, 9, 13, 10, 30),
                )),
              ));
            },
            child: const Text('打开校历设置'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开校历设置'));
  await tester.pumpAndSettle();
  return result;
}

String _text(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(find.byKey(ValueKey(key))).controller!.text;

Future<void> _reveal(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  if (finder.evaluate().isEmpty) {
    final scrollable = find.byType(Scrollable).first;
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(finder, 260, scrollable: scrollable, maxScrolls: 40);
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String value) async {
  await _reveal(tester, key);
  await tester.enterText(find.byKey(ValueKey(key)), value);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await _reveal(tester, key);
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

ScheduleSnapshot _snapshot({bool unknownCalendar = false, List<PeriodTime>? periods}) =>
    ScheduleSnapshot(
      term: AcademicTerm(yearCode: '2026', termCode: '3', label: '2026–2027 学年第一学期'),
      entries: [
        ScheduleEntry(
          id: 'school-course',
          name: '学校课程',
          weeks: const [32],
          weekday: DateTime.monday,
          startPeriod: 1,
          endPeriod: 2,
        ),
      ],
      fetchedAt: DateTime.utc(2026, 9, 13),
      calendar: unknownCalendar
          ? const TeachingCalendar.unknown()
          : TeachingCalendar(
              firstWeekMonday: DateTime(2026, 8, 31),
              totalWeeks: 20,
              source: TeachingCalendarSource.school,
              sourceLabel: '学校校历',
            ),
      periodTimes: periods ?? [
        PeriodTime(number: 1, startMinutes: 480, endMinutes: 525, campus: '北校区'),
      ],
    );

ScheduleSettings _settings() => ScheduleSettings(
  calendarOverride: TeachingCalendar(
    firstWeekMonday: DateTime(2026, 9, 7),
    totalWeeks: 18,
    source: TeachingCalendarSource.user,
  ),
  periodTimes: [PeriodTime(number: 1, startMinutes: 490, endMinutes: 535, campus: '北校区')],
  localEntries: [
    ScheduleEntry(id: 'local-study', name: '自习', weeks: const [1], origin: ScheduleEntryOrigin.local),
  ],
  hiddenEntryIds: const ['school-course'],
);
