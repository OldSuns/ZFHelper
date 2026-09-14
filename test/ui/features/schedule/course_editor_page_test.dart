import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zf_core/zf_core.dart';
import 'package:zfhelper/ui/core/app_theme.dart';
import 'package:zfhelper/ui/features/schedule/views/course_editor_page.dart';

void main() {
  testWidgets('new courses explicitly select only the current week', (tester) async {
    final result = await _openEditor(tester, initialWeek: 7);

    expect(_field(tester, 'course-name').controller!.text, isEmpty);
    expect(_field(tester, 'course-start-period').controller!.text, isEmpty);
    expect(_field(tester, 'course-end-period').controller!.text, isEmpty);
    expect(_field(tester, 'course-weeks').controller!.text, '7');
    await _tap(tester, 'course-save');
    expect(find.text('请填写课程名称'), findsOneWidget);
    expect(find.text('请选择星期'), findsOneWidget);
    expect(result.isCompleted, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('creates a local course beyond the observed weeks and periods', (tester) async {
    final result = await _openEditor(tester, visibleWeekCount: 20, periodCount: 12);
    await _enter(tester, 'course-name', '  晚间专题  ');
    await _enter(tester, 'course-teacher', '测试教师');
    await _enter(tester, 'course-campus', '南校区');
    await _enter(tester, 'course-location', '研究楼 301');
    await _weekday(tester, '周三');
    await _enter(tester, 'course-start-period', '13');
    await _enter(tester, 'course-end-period', '15');
    await _enter(tester, 'course-weeks', '26-30(单),32');
    await _tap(tester, 'course-save');

    final entry = (await result.future)!;
    expect(entry.name, '晚间专题');
    expect(entry.origin, ScheduleEntryOrigin.local);
    expect(entry.id, matches(RegExp(r'^local-[0-9a-f]{32}$')));
    expect(entry.weekday, DateTime.wednesday);
    expect(entry.startPeriod, 13);
    expect(entry.endPeriod, 15);
    expect(entry.weeks, {27, 29, 32});
    expect(entry.rawWeeks, '26-30(单),32');
    expect(entry.teacher, '测试教师');
    expect(entry.campus, '南校区');
    expect(entry.location, '研究楼 301');
  });

  testWidgets('week shortcuts use the visible range and preserve parity', (tester) async {
    final result = await _openEditor(tester, entry: _entry(), visibleWeekCount: 28);
    await _tap(tester, 'course-even-weeks');
    expect(_field(tester, 'course-weeks').controller!.text, '1-28(双)');
    await _tap(tester, 'course-odd-weeks');
    expect(find.text('共 14 个教学周'), findsOneWidget);
    await _tap(tester, 'course-save');

    expect((await result.future)!.weeks, {for (var week = 1; week <= 28; week += 2) week});
  });

  testWidgets('editing a local record retains its identity and metadata', (tester) async {
    final original = _entry();
    final result = await _openEditor(tester, entry: original);
    await _enter(tester, 'course-name', '修改后的自习');
    await _enter(tester, 'course-weeks', '2-10(单),12,28-30');
    await _tap(tester, 'course-save');

    final edited = (await result.future)!;
    expect(edited.id, original.id);
    expect(edited.metadata, original.metadata);
    expect(edited.teachingClassId, original.teachingClassId);
    expect(edited.courseCode, original.courseCode);
    expect(edited.weeks, {3, 5, 7, 9, 12, 28, 29, 30});
    expect(original.name, '原课程');
    expect(original.weeks, {2, 4, 6});
  });

  testWidgets('adjusting an import creates a linked local record', (tester) async {
    final original = _entry(origin: ScheduleEntryOrigin.imported);
    final result = await _openEditor(tester, entry: original);
    await _enter(tester, 'course-location', '新的教室');
    await _tap(tester, 'course-save');

    final edited = (await result.future)!;
    expect(edited.origin, ScheduleEntryOrigin.local);
    expect(edited.id, isNot(original.id));
    expect(edited.metadata['replacesImportedId'], original.id);
    expect(edited.metadata['note'], '保留的信息');
    expect(edited.location, '新的教室');
    expect(original.origin, ScheduleEntryOrigin.imported);
    expect(original.location, '原教室');
  });

  testWidgets('an empty or invalid week expression never becomes every week', (tester) async {
    final result = await _openEditor(tester, entry: _entry());
    await _enter(tester, 'course-weeks', '');
    await _tap(tester, 'course-save');
    expect(find.text('请填写上课周次'), findsOneWidget);
    expect(result.isCompleted, isFalse);

    await _enter(tester, 'course-weeks', '每周随便');
    await _tap(tester, 'course-save');
    expect(find.text('周次无法识别，请核对区间、逗号和单双周标记'), findsOneWidget);
    expect(result.isCompleted, isFalse);
  });

  testWidgets('rejects backwards periods before returning a result', (tester) async {
    final result = await _openEditor(tester, entry: _entry());
    await _enter(tester, 'course-start-period', '6');
    await _enter(tester, 'course-end-period', '3');
    await _tap(tester, 'course-save');

    expect(find.text('结束节次不能早于开始节次'), findsOneWidget);
    expect(result.isCompleted, isFalse);
  });

  testWidgets('cancel discards the draft without changing the source entry', (tester) async {
    final original = _entry();
    final result = await _openEditor(tester, entry: original);
    await _enter(tester, 'course-name', '取消的名字');
    await tester.tap(find.byTooltip('取消编辑'));
    await tester.pumpAndSettle();

    expect(await result.future, isNull);
    expect(original.name, '原课程');
  });

  for (final layout in [
    (size: const Size(375, 740), scale: 1.0, brightness: Brightness.light, keyboard: 0.0),
    (size: const Size(320, 640), scale: 2.0, brightness: Brightness.dark, keyboard: 200.0),
    (size: const Size(760, 420), scale: 2.0, brightness: Brightness.light, keyboard: 160.0),
    (size: const Size(1200, 800), scale: 2.0, brightness: Brightness.dark, keyboard: 0.0),
  ]) {
    testWidgets('course form works at ${layout.size} and ${layout.scale} text scale', (tester) async {
      final result = await _openEditor(
        tester,
        entry: _entry(),
        size: layout.size,
        textScale: layout.scale,
        brightness: layout.brightness,
      );
      tester.view.viewInsets = FakeViewPadding(bottom: layout.keyboard);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await _enter(tester, 'course-weeks', '1-30(单)');
      final save = find.byKey(const ValueKey('course-save'));
      expect(tester.getBottomRight(save).dy, lessThanOrEqualTo(layout.size.height - layout.keyboard));
      expect(tester.takeException(), isNull);
      await _tap(tester, 'course-save');
      expect((await result.future)!.weeks, hasLength(15));
      expect(tester.takeException(), isNull);
    });
  }
}

Future<Completer<ScheduleEntry?>> _openEditor(
  WidgetTester tester, {
  ScheduleEntry? entry,
  int initialWeek = 3,
  int visibleWeekCount = 20,
  int periodCount = 12,
  Size size = const Size(430, 920),
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
  final result = Completer<ScheduleEntry?>();
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
              result.complete(await Navigator.of(context).push<ScheduleEntry>(
                MaterialPageRoute(
                  builder: (_) => CourseEditorPage(
                    entry: entry,
                    initialWeek: initialWeek,
                    visibleWeekCount: visibleWeekCount,
                    periodCount: periodCount,
                  ),
                ),
              ));
            },
            child: const Text('打开课程编辑'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开课程编辑'));
  await tester.pumpAndSettle();
  return result;
}

TextFormField _field(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(find.byKey(ValueKey(key)));

Future<void> _enter(WidgetTester tester, String key, String value) async {
  final field = find.byKey(ValueKey(key));
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _weekday(WidgetTester tester, String day) async {
  await _tap(tester, 'course-weekday');
  await tester.tap(find.text(day).last);
  await tester.pumpAndSettle();
}

ScheduleEntry _entry({ScheduleEntryOrigin origin = ScheduleEntryOrigin.local}) =>
    ScheduleEntry(
      id: 'original-id',
      name: '原课程',
      teachingClassId: 'teaching-class',
      courseCode: 'course-code',
      teacher: '原教师',
      location: '原教室',
      campus: '北校区',
      weekday: DateTime.monday,
      startPeriod: 1,
      endPeriod: 2,
      weeks: const [2, 4, 6],
      origin: origin,
      metadata: const {'note': '保留的信息'},
    );
