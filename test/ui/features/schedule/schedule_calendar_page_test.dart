import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zf_core/zf_core.dart';
import 'package:zfhelper/ui/core/app_theme.dart';
import 'package:zfhelper/ui/features/schedule/views/schedule_calendar_page.dart';

void main() {
  testWidgets('unknown calendars do not guess the first date or term length', (
    tester,
  ) async {
    await _openCalendar(tester, snapshot: _snapshot(unknownCalendar: true));

    expect(_text(tester, 'calendar-first-monday'), isEmpty);
    expect(_text(tester, 'calendar-total-weeks'), isEmpty);
    expect(find.text('当前教学周待确认'), findsOneWidget);
    await _tap(tester, 'calendar-pick-date');
    final picker = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(picker.initialDate, isNull);
    expect(picker.selectableDayPredicate!(DateTime(2026, 9, 7)), isTrue);
    expect(picker.selectableDayPredicate!(DateTime(2026, 9, 8)), isFalse);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    expect(_text(tester, 'calendar-first-monday'), isEmpty);
  });

  testWidgets(
    'date selection accepts a Monday and previews the real teaching week',
    (tester) async {
      final result = await _openCalendar(
        tester,
        snapshot: _snapshot(unknownCalendar: true),
      );
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
    },
  );

  testWidgets(
    'saving calendar changes preserves local courses and hidden imports',
    (tester) async {
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
    },
  );

  testWidgets(
    'rejects non-Mondays and invalid civil dates instead of correcting silently',
    (tester) async {
      final result = await _openCalendar(tester);
      await _enter(tester, 'calendar-first-monday', '2026-09-08');
      await _tap(tester, 'calendar-save');
      expect(find.text('第一教学周必须从周一开始'), findsWidgets);
      expect(result.isCompleted, isFalse);

      await _enter(tester, 'calendar-first-monday', '2026-02-30');
      await _tap(tester, 'calendar-save');
      expect(find.text('请按 YYYY-MM-DD 填写有效日期'), findsWidgets);
      expect(result.isCompleted, isFalse);
    },
  );

  testWidgets('restoring the school calendar clears only its override', (
    tester,
  ) async {
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

  testWidgets(
    'generates long breaks, shifts a section and saves other campuses',
    (tester) async {
      final result = await _openCalendar(
        tester,
        size: const Size(1200, 850),
        snapshot: _snapshot(
          periods: [
            PeriodTime(
              number: 1,
              startMinutes: 480,
              endMinutes: 525,
              campus: '北校区',
            ),
            PeriodTime(
              number: 1,
              startMinutes: 500,
              endMinutes: 550,
              campus: '南校区',
            ),
          ],
        ),
      );
      await _tap(tester, 'period-quick-arrange');
      await _enterFinder(
        tester,
        find.widgetWithText(TextFormField, '节数').at(0),
        '4',
      );
      await _enterFinder(
        tester,
        find.widgetWithText(TextFormField, '首课开始').at(0),
        '08:00',
      );
      await _enterFinder(
        tester,
        find.widgetWithText(TextFormField, '节数').at(1),
        '2',
      );
      await _enterFinder(
        tester,
        find.widgetWithText(TextFormField, '首课开始').at(1),
        '14:00',
      );
      await _enterFinder(
        tester,
        find.widgetWithText(TextFormField, '每节课（分钟）'),
        '45',
      );
      await _enterFinder(
        tester,
        find.widgetWithText(TextFormField, '课间（分钟）'),
        '5',
      );
      await _tapFinder(tester, find.text('周期性长课间'));
      await _enterFinder(
        tester,
        find.widgetWithText(TextFormField, '每隔几节'),
        '2',
      );
      await _enterFinder(
        tester,
        find.widgetWithText(TextFormField, '休息（分钟）'),
        '10',
      );
      await _tapFinder(tester, find.text('生成预览'));
      await _tapFinder(tester, find.text('应用到作息草稿'));
      await _tap(tester, 'period-row-2');
      await _enter(tester, 'period-edit-end', '09:40');
      await _tap(tester, 'period-edit-apply');
      await _tap(tester, 'period-break-1');
      await _enter(tester, 'period-value-input', '10');
      await _tap(tester, 'period-value-apply');
      await _tap(tester, 'period-undo');
      await _tap(tester, 'calendar-save');

      final saved = (await result.future)!;
      final times = saved.periodTimes.where((p) => p.campus == '北校区').toList();
      expect(times.map((p) => (p.startMinutes, p.endMinutes)), [
        (480, 525),
        (530, 580),
        (590, 635),
        (640, 685),
        (840, 885),
        (890, 935),
      ]);
      expect(saved.periodSections.map((s) => (s.firstPeriod, s.lastPeriod)), [
        (1, 4),
        (5, 6),
      ]);
      expect(
        saved.periodTimes.singleWhere((p) => p.campus == '南校区').startMinutes,
        500,
      );
    },
  );

  testWidgets(
    'section-only edits preserve sparse numbers and normalize campus choices',
    (tester) async {
      final original = ScheduleSettings(
        periodTimes: [
          for (final number in [1, 2, 5, 6])
            PeriodTime(
              number: number,
              startMinutes: 420 + number * 60,
              endMinutes: 465 + number * 60,
              campus: '',
            ),
        ],
        periodSections: [
          PeriodTimeSection(
            session: PeriodSession.afternoon,
            firstPeriod: 5,
            lastPeriod: 6,
          ),
        ],
      );
      final result = await _openCalendar(tester, settings: original);
      expect(tester.takeException(), isNull);
      await _tap(tester, 'period-quick-arrange');
      await _tapFinder(tester, find.text('仅划分时段'));
      expect(
        tester
            .widget<DropdownButtonFormField<int>>(
              find.byKey(const ValueKey('period-section-afternoon-first')),
            )
            .initialValue,
        5,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<int>>(
              find.byKey(const ValueKey('period-section-afternoon-last')),
            )
            .initialValue,
        6,
      );
      await _tap(tester, 'period-section-preview');
      await _tapFinder(tester, find.text('应用到作息草稿'));
      await _tap(tester, 'calendar-save');
      final saved = (await result.future)!;
      expect(saved.periodSections.single.firstPeriod, 5);
      expect(
        saved.periodTimes.map((p) => (p.number, p.startMinutes, p.endMinutes)),
        original.periodTimes.map(
          (p) => (p.number, p.startMinutes, p.endMinutes),
        ),
      );
    },
  );

  testWidgets(
    'empty local times survive restore and undo without affecting courses',
    (tester) async {
      final result = await _openCalendar(tester, settings: _settings());
      await _reveal(tester, 'period-row-1');
      await _tapFinder(tester, find.byTooltip('第 1 节操作'));
      await _tapFinder(tester, find.text('删除课节时间'));
      await _tapFinder(tester, find.text('删除'));
      await _tap(tester, 'period-restore');
      await _tapFinder(tester, find.text('恢复'));
      await _tap(tester, 'period-undo');
      await _tap(tester, 'calendar-save');
      final saved = (await result.future)!;
      expect(saved.useCustomPeriodTimes, isTrue);
      expect(saved.periodTimes, isEmpty);
      expect(saved.periodSections, isEmpty);
      expect(saved.localEntries.single.id, 'local-study');
    },
  );

  testWidgets('cancel discards the draft only after confirmation', (
    tester,
  ) async {
    final original = _settings();
    final result = await _openCalendar(tester, settings: original);
    await _enter(tester, 'calendar-first-monday', '2026-09-14');
    await tester.tap(find.byTooltip('取消设置'));
    await tester.pumpAndSettle();
    await _tapFinder(tester, find.text('放弃修改'));
    expect(await result.future, isNull);
    expect(original.calendarOverride!.firstWeekMonday, DateTime(2026, 9, 7));
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'compact editor and generator work at narrow width, scale $scale',
      (tester) async {
        final result = await _openCalendar(
          tester,
          size: const Size(320, 700),
          textScale: scale,
        );
        await _tap(tester, 'period-quick-arrange');
        await _tapFinder(tester, find.text('仅划分时段'));
        expect(tester.takeException(), isNull);
        await _tapFinder(tester, find.text('取消').last);
        await _tapFinder(tester, find.byType(BackButton));
        await _tap(tester, 'period-row-1');
        await _enter(tester, 'period-edit-end', '09:00');
        await _tap(tester, 'period-edit-apply');
        await _tap(tester, 'calendar-save');
        expect((await result.future)!.periodTimes.single.endMinutes, 540);
        expect(tester.takeException(), isNull);
      },
    );
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
              result.complete(
                await Navigator.of(context).push<ScheduleSettings>(
                  MaterialPageRoute(
                    builder: (_) => ScheduleCalendarPage(
                      snapshot: snapshot ?? _snapshot(),
                      settings: settings ?? ScheduleSettings(),
                      today: DateTime(2026, 9, 13, 10, 30),
                    ),
                  ),
                ),
              );
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

Finder _field(String key) {
  final finder = find.byKey(ValueKey(key));
  return finder.evaluate().single.widget is TextFormField
      ? finder
      : find.descendant(of: finder, matching: find.byType(TextFormField));
}

String _text(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(_field(key)).controller!.text;

Future<void> _enterFinder(
  WidgetTester tester,
  Finder finder,
  String value,
) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
  await tester.pumpAndSettle();
  await tester.enterText(finder, value);
  await tester.pumpAndSettle();
}

Future<void> _tapFinder(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  if (finder.evaluate().isEmpty) {
    final scrollable = find.byType(Scrollable).first;
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      finder,
      260,
      scrollable: scrollable,
      maxScrolls: 40,
    );
  }
  await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String value) async {
  await _reveal(tester, key);
  await tester.enterText(_field(key), value);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await _reveal(tester, key);
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

ScheduleSnapshot _snapshot({
  bool unknownCalendar = false,
  List<PeriodTime>? periods,
}) => ScheduleSnapshot(
  term: AcademicTerm(
    yearCode: '2026',
    termCode: '3',
    label: '2026–2027 学年第一学期',
  ),
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
  periodTimes:
      periods ??
      [
        PeriodTime(
          number: 1,
          startMinutes: 480,
          endMinutes: 525,
          campus: '北校区',
        ),
      ],
);

ScheduleSettings _settings() => ScheduleSettings(
  calendarOverride: TeachingCalendar(
    firstWeekMonday: DateTime(2026, 9, 7),
    totalWeeks: 18,
    source: TeachingCalendarSource.user,
  ),
  periodTimes: [
    PeriodTime(number: 1, startMinutes: 490, endMinutes: 535, campus: '北校区'),
  ],
  localEntries: [
    ScheduleEntry(
      id: 'local-study',
      name: '自习',
      weeks: const [1],
      origin: ScheduleEntryOrigin.local,
    ),
  ],
  hiddenEntryIds: const ['school-course'],
);
