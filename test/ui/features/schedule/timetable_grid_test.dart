import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zf_core/zf_core.dart';
import 'package:zfhelper/ui/core/app_theme.dart';
import 'package:zfhelper/ui/features/schedule/views/course_detail_sheet.dart';
import 'package:zfhelper/ui/features/schedule/views/timetable_grid.dart';

void main() {
  testWidgets('courses occupy their weekday and period span and open on tap', (
    tester,
  ) async {
    final monday = _lesson('monday', '高等数学', weekday: 1, start: 1, end: 2);
    final tuesday = _lesson('tuesday', '大学英语', weekday: 2, start: 3, end: 5);
    final opened = <ScheduleEntry>[];
    await _pumpGrid(tester, _snapshot([monday, tuesday]), onTap: opened.add);

    final firstRect = tester.getRect(
      find.byKey(const ValueKey('schedule-course-monday')),
    );
    final secondRect = tester.getRect(
      find.byKey(const ValueKey('schedule-course-tuesday')),
    );
    expect(secondRect.left, greaterThan(firstRect.right - 1));
    expect(secondRect.top, closeTo(firstRect.bottom, 1));
    expect(secondRect.height / firstRect.height, closeTo(1.5, 0.01));
    expect(find.text('9/14'), findsOneWidget);
    expect(find.text('周二'), findsOneWidget);
    expect(find.text('今天'), findsOneWidget);

    await tester.tap(find.text('高等数学'));
    expect(opened, [monday]);
    expect(tester.takeException(), isNull);
    await _pumpGrid(
      tester,
      _snapshot([
        _lesson('single', '单节课程', weekday: 1, start: 1, end: 1),
      ], times: _morningTimes),
      size: const Size(1000, 650),
      textScale: 1.4,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'transitive overlaps share a picker and every conflicting course is reachable',
    (tester) async {
      final entries = [
        _lesson('a', '课程甲', weekday: 1, start: 1, end: 2),
        _lesson('b', '课程乙', weekday: 1, start: 2, end: 3),
        _lesson('c', '课程丙', weekday: 1, start: 3, end: 4),
        _lesson('separate', '下一节课程', weekday: 1, start: 5, end: 5),
        _lesson(
          'other-week',
          '其他周课程',
          weekday: 1,
          start: 1,
          end: 4,
          weeks: [3],
        ),
      ];
      final opened = <String>[];
      await _pumpGrid(
        tester,
        _snapshot(entries),
        onTap: (entry) => opened.add(entry.id),
      );

      expect(find.text('冲突 · 3门'), findsOneWidget);
      expect(find.text('其他周课程'), findsNothing);
      expect(
        find.byKey(const ValueKey('schedule-course-separate')),
        findsOneWidget,
      );
      for (final name in ['课程甲', '课程乙', '课程丙']) {
        await tester.tap(find.text('冲突 · 3门'));
        await tester.pumpAndSettle();
        final list = find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(Scrollable),
        );
        await tester.scrollUntilVisible(
          find.text(name),
          160,
          scrollable: list.first,
        );
        await tester.tap(find.text(name));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
      }
      expect(opened, ['a', 'b', 'c']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'practice and unscheduled arrangements retain their week meaning',
    (tester) async {
      final practice = ScheduleEntry(
        id: 'practice',
        name: '本周见习',
        weeks: [2],
        kind: ScheduleEntryKind.practice,
      );
      final unknown = ScheduleEntry(
        id: 'unknown',
        name: '待定讲座',
        weeks: const [],
        kind: ScheduleEntryKind.unscheduled,
      );
      final snapshot = _snapshot([
        _lesson('current', '本周课程', weekday: 1, start: 1, end: 2),
        _lesson('previous', '上周课程', weekday: 1, start: 1, end: 2, weeks: [1]),
        practice,
        unknown,
        ScheduleEntry(
          id: 'future',
          name: '下周见习',
          weeks: [3],
          kind: ScheduleEntryKind.practice,
        ),
      ]);
      final opened = <ScheduleEntry>[];
      await _pumpGrid(tester, snapshot, agenda: true, onTap: opened.add);

      expect(find.text('本周课程'), findsOneWidget);
      expect(find.text('上周课程'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('待定讲座'),
        200,
        scrollable: _gridScrollable(),
      );
      expect(find.text('本周见习'), findsOneWidget);
      expect(find.text('下周见习'), findsNothing);
      expect(find.textContaining('周次待安排'), findsOneWidget);
      await tester.tap(find.text('待定讲座'));
      expect(opened, [unknown]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an unknown term calendar does not invent dates or a current class',
    (tester) async {
      final snapshot = _snapshot(
        [_lesson('lesson', '有节次的课程', weekday: 1, start: 1, end: 2)],
        calendar: const TeachingCalendar.unknown(),
        times: _morningTimes,
      );
      await _pumpGrid(tester, snapshot);

      expect(find.text('有节次的课程'), findsOneWidget);
      expect(find.text('今天'), findsNothing);
      expect(find.byKey(const ValueKey('schedule-date-1')), findsNothing);
      expect(find.byKey(const ValueKey('schedule-current-time')), findsNothing);
      expect(find.text('上课'), findsNothing);
    },
  );

  testWidgets(
    'current class and time line follow school clock periods including breaks',
    (tester) async {
      final snapshot = _snapshot([
        _lesson('lesson', '正在授课的课程', weekday: 1, start: 1, end: 2),
      ], times: _morningTimes);
      await _pumpGrid(tester, snapshot, today: DateTime(2026, 9, 14, 8, 20));
      expect(
        find.byKey(const ValueKey('schedule-current-time')),
        findsOneWidget,
      );
      expect(find.text('上课'), findsOneWidget);

      await _pumpGrid(tester, snapshot, today: DateTime(2026, 9, 14, 8, 50));
      expect(find.byKey(const ValueKey('schedule-current-time')), findsNothing);
      expect(find.text('上课'), findsNothing);

      await _pumpGrid(tester, snapshot, today: DateTime(2026, 9, 14, 9, 15));
      expect(
        find.byKey(const ValueKey('schedule-current-time')),
        findsOneWidget,
      );
      expect(find.text('上课'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'different campus clocks do not create a misleading shared time line',
    (tester) async {
      final snapshot = _snapshot(
        [
          ScheduleEntry(
            id: 'east',
            name: '东校区课程',
            weekday: 1,
            startPeriod: 1,
            endPeriod: 1,
            weeks: [2],
            campus: '东校区',
          ),
        ],
        times: [
          PeriodTime(number: 1, startMinutes: 8 * 60, endMinutes: 8 * 60 + 45),
          PeriodTime(
            number: 1,
            startMinutes: 9 * 60,
            endMinutes: 9 * 60 + 45,
            campus: '东校区',
          ),
        ],
      );
      await _pumpGrid(tester, snapshot, today: DateTime(2026, 9, 14, 8, 20));

      expect(find.byKey(const ValueKey('schedule-current-time')), findsNothing);
      expect(find.text('上课'), findsNothing);
      expect(find.text('多套\n作息'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      '${brightness.name} course cards meet contrast and touch size on a small phone',
      (tester) async {
        final snapshot = _snapshot([
          _lesson('lesson', '高等数学', weekday: 1, start: 1, end: 2),
        ]);
        await _pumpGrid(
          tester,
          snapshot,
          size: const Size(375, 640),
          brightness: brightness,
        );
        final card = find.byKey(const ValueKey('schedule-course-lesson'));
        final rect = tester.getRect(card);
        expect(rect.width, greaterThanOrEqualTo(48));
        expect(rect.height, greaterThanOrEqualTo(48));
        final ink = tester.widget<Ink>(
          find.descendant(of: card, matching: find.byType(Ink)),
        );
        final background = (ink.decoration! as BoxDecoration).color!;
        final text = tester.widget<Text>(find.text('高等数学'));
        final foreground = text.style!.color!;
        final luminances = [
          background.computeLuminance(),
          foreground.computeLuminance(),
        ]..sort();
        expect(
          (luminances.last + 0.05) / (luminances.first + 0.05),
          greaterThanOrEqualTo(4.5),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final layout in [
    (size: const Size(320, 640), scale: 1.0),
    (size: const Size(375, 640), scale: 2.0),
    (size: const Size(900, 420), scale: 2.0),
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'readable agenda at ${layout.size} with ${layout.scale} text in ${brightness.name}',
        (tester) async {
          final longName = '现代中医临床基础与诊疗实践课程——用于检验长课程名称的完整显示';
          final entry = _lesson('long', longName, weekday: 1, start: 1, end: 1);
          final opened = <ScheduleEntry>[];
          await _pumpGrid(
            tester,
            _snapshot([entry]),
            size: layout.size,
            textScale: layout.scale,
            brightness: brightness,
            onTap: opened.add,
          );

          expect(
            find.byKey(const ValueKey('schedule-course-long')),
            findsNothing,
          );
          expect(find.text(longName), findsOneWidget);
          await tester.tap(find.text(longName));
          expect(opened, [entry]);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'the date header stays fixed and only the active page reports scrolling',
    (tester) async {
      final snapshot = _snapshot([
        _lesson('first', '上午课程', weekday: 1, start: 1, end: 2),
        _lesson('late', '晚间课程', weekday: 2, start: 12, end: 14),
      ]);
      final offsets = <double>[];
      await _pumpGrid(
        tester,
        snapshot,
        size: const Size(800, 440),
        onScroll: offsets.add,
      );
      final headerTop = tester.getTopLeft(find.text('9/14')).dy;
      await tester.drag(
        find.byKey(const ValueKey('timetable-vertical-scroll')),
        const Offset(0, -250),
      );
      await tester.pumpAndSettle();
      expect(offsets, isNotEmpty);
      final saved = offsets.last;
      expect(saved, greaterThan(100));
      expect(tester.getTopLeft(find.text('9/14')).dy, headerTop);
      final reports = offsets.length;

      await _pumpGrid(
        tester,
        snapshot,
        size: const Size(800, 440),
        active: false,
        onScroll: offsets.add,
      );
      await tester.drag(
        find.byKey(const ValueKey('timetable-vertical-scroll')),
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      expect(offsets, hasLength(reports));

      await _pumpGrid(
        tester,
        snapshot,
        size: const Size(800, 440),
        scrollOffset: saved,
        onScroll: offsets.add,
      );
      final scrollable = tester.state<ScrollableState>(_gridScrollable());
      expect(scrollable.position.pixels, closeTo(saved, 0.5));
      expect(offsets, hasLength(reports));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'neighboring week pages restore position without sharing a scroll attachment',
    (tester) async {
      _setSize(tester, const Size(800, 450));
      final snapshot = _snapshot([
        _lesson('early', '每周早课', weekday: 1, start: 1, end: 2, weeks: [1, 2]),
        _lesson('late', '每周晚课', weekday: 1, start: 12, end: 14, weeks: [1, 2]),
      ]);
      var page = 0;
      var saved = 0.0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => PageView(
                onPageChanged: (value) => setState(() => page = value),
                children: [
                  for (var index = 0; index < 2; index++)
                    TimetableGrid(
                      key: ValueKey('page-$index'),
                      snapshot: snapshot,
                      week: index + 1,
                      today: DateTime(2026, 9, 14),
                      active: page == index,
                      scrollOffset: saved,
                      onScroll: (offset) => saved = offset,
                      onCourseTap: (_) {},
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.drag(
        find.byKey(const ValueKey('timetable-vertical-scroll')).first,
        const Offset(0, -220),
      );
      await tester.pumpAndSettle();
      final originalOffset = saved;
      expect(originalOffset, greaterThan(100));
      await tester.drag(find.byType(PageView), const Offset(-700, 0));
      await tester.pumpAndSettle();

      expect(page, 1);
      final activeScroll = find.descendant(
        of: find.byKey(const ValueKey('page-1')),
        matching: find.byType(Scrollable),
      );
      expect(
        tester.state<ScrollableState>(activeScroll).position.pixels,
        closeTo(originalOffset, 0.5),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an empty week and a wholly empty term have different messages', (
    tester,
  ) async {
    await _pumpGrid(
      tester,
      _snapshot([
        _lesson('elsewhere', '第三周课程', weekday: 1, start: 1, end: 2, weeks: [3]),
      ]),
    );
    expect(find.text('第 2 周没有排定课程'), findsOneWidget);
    expect(find.text('这个学期暂无课程'), findsNothing);

    await _pumpGrid(tester, _snapshot([]));
    expect(find.text('这个学期暂无课程'), findsOneWidget);
    expect(find.text('第 2 周没有排定课程'), findsNothing);
  });

  testWidgets(
    'details preserve raw weeks, public course information and every teaching arrangement',
    (tester) async {
      final entry = ScheduleEntry(
        id: 'internal-row-id',
        name: '临床医学概论',
        teachingClassId: 'internal-class-id',
        courseCode: 'MED-101',
        teacher: '张老师、李老师',
        campus: '主校区',
        location: '教学楼 A101',
        weekday: 1,
        startPeriod: 1,
        endPeriod: 2,
        weeks: [2, 4, 6],
        rawWeeks: '2-6周(双)',
        metadata: {'jxbmc': '临床医学 2026 级 A 班', 'xf': '3', 'bz': '携带实验记录本'},
      );
      final another = ScheduleEntry(
        id: 'another-row',
        name: entry.name,
        teachingClassId: entry.teachingClassId,
        teacher: '王老师',
        location: '第二实验楼 B202',
        weekday: 4,
        startPeriod: 3,
        endPeriod: 4,
        weeks: [2, 4, 6],
      );
      final snapshot = _snapshot([
        entry,
        another,
        _lesson('conflict', '本周重叠课程', weekday: 1, start: 2, end: 3),
      ], times: _morningTimes);
      await _pumpDetailsLauncher(tester, entry, snapshot);
      await tester.tap(find.text('打开详情'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(_selectable('临床医学概论'), findsOneWidget);
      await _scrollDetailsTo(tester, _selectable('MED-101'));
      expect(_selectable('MED-101'), findsOneWidget);
      expect(_selectable('临床医学 2026 级 A 班'), findsOneWidget);
      expect(find.textContaining('internal-'), findsNothing);
      await _scrollDetailsTo(tester, _selectable('2-6周(双)').first);
      expect(_selectable('2-6周(双)'), findsWidgets);
      await _scrollDetailsTo(tester, _selectable('第二实验楼 B202'));
      expect(_selectable('第二实验楼 B202'), findsOneWidget);
      await _scrollDetailsTo(tester, _selectable('本周重叠课程'));
      expect(_selectable('本周重叠课程'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final origin in ScheduleEntryOrigin.values) {
    testWidgets(
      '${origin.name} detail actions close the sheet before invoking callbacks at 200% text',
      (tester) async {
        final entry = ScheduleEntry(
          id: 'entry',
          name: '长名称课程的详细资料与本地操作验证',
          teacher: '授课老师',
          location: '教学楼 1203',
          weekday: 1,
          startPeriod: 1,
          endPeriod: 2,
          weeks: [2],
          origin: origin,
        );
        var edits = 0;
        var deletes = 0;
        final navigator = GlobalKey<NavigatorState>();
        var callbackHadOpenRoute = false;
        await _pumpDetailsLauncher(
          tester,
          entry,
          _snapshot([entry]),
          size: const Size(375, 640),
          textScale: 2,
          navigatorKey: navigator,
          onEdit: () {
            callbackHadOpenRoute = navigator.currentState!.canPop();
            edits++;
          },
          onDelete: () {
            callbackHadOpenRoute = navigator.currentState!.canPop();
            deletes++;
          },
        );
        await tester.tap(find.text('打开详情'));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        final editLabel = origin == ScheduleEntryOrigin.local ? '编辑课程' : '本地调整';
        await _scrollDetailsTo(tester, find.text(editLabel));
        await tester.tap(find.text(editLabel));
        await tester.pumpAndSettle();
        expect(edits, 1);
        expect(callbackHadOpenRoute, isFalse);
        expect(find.text('课程详情'), findsNothing);

        await tester.tap(find.text('打开详情'));
        await tester.pumpAndSettle();
        final deleteLabel = origin == ScheduleEntryOrigin.local
            ? '删除课程'
            : '隐藏此安排';
        await _scrollDetailsTo(tester, find.text(deleteLabel));
        await tester.tap(find.text(deleteLabel));
        await tester.pumpAndSettle();
        expect(deletes, 1);
        expect(callbackHadOpenRoute, isFalse);
        expect(find.text('课程详情'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

ScheduleEntry _lesson(
  String id,
  String name, {
  required int weekday,
  required int start,
  required int end,
  List<int> weeks = const [2],
}) => ScheduleEntry(
  id: id,
  name: name,
  teachingClassId: 'class-$id',
  teacher: '测试教师',
  location: '教学楼 A101',
  weekday: weekday,
  startPeriod: start,
  endPeriod: end,
  weeks: weeks,
);

ScheduleSnapshot _snapshot(
  List<ScheduleEntry> entries, {
  TeachingCalendar? calendar,
  List<PeriodTime> times = const [],
}) => ScheduleSnapshot(
  term: AcademicTerm(
    yearCode: '2026',
    termCode: '3',
    label: '2026–2027 学年第一学期',
  ),
  entries: entries,
  fetchedAt: DateTime(2026, 9, 13, 18),
  calendar:
      calendar ??
      TeachingCalendar(
        firstWeekMonday: DateTime(2026, 9, 7),
        totalWeeks: 20,
        source: TeachingCalendarSource.school,
      ),
  periodTimes: times,
);

final _morningTimes = [
  PeriodTime(number: 1, startMinutes: 8 * 60, endMinutes: 8 * 60 + 45),
  PeriodTime(number: 2, startMinutes: 9 * 60, endMinutes: 9 * 60 + 45),
];

Future<void> _pumpGrid(
  WidgetTester tester,
  ScheduleSnapshot snapshot, {
  Size size = const Size(800, 650),
  Brightness brightness = Brightness.light,
  double textScale = 1,
  DateTime? today,
  bool agenda = false,
  bool active = true,
  double scrollOffset = 0,
  ValueChanged<ScheduleEntry>? onTap,
  ValueChanged<double>? onScroll,
}) async {
  _setSize(tester, size);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: TimetableGrid(
          snapshot: snapshot,
          week: 2,
          today: today ?? DateTime(2026, 9, 14, 8, 20),
          onCourseTap: onTap ?? (_) {},
          onScroll: onScroll,
          scrollOffset: scrollOffset,
          active: active,
          agenda: agenda,
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpDetailsLauncher(
  WidgetTester tester,
  ScheduleEntry entry,
  ScheduleSnapshot snapshot, {
  Size size = const Size(800, 650),
  double textScale = 1,
  GlobalKey<NavigatorState>? navigatorKey,
  VoidCallback? onEdit,
  VoidCallback? onDelete,
}) async {
  _setSize(tester, size);
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      theme: AppTheme.build(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showScheduleCourseDetails(
                context,
                entry: entry,
                snapshot: snapshot,
                week: 2,
                onEdit: onEdit,
                onDelete: onDelete,
              ),
              child: const Text('打开详情'),
            ),
          ),
        ),
      ),
    ),
  );
}

Finder _gridScrollable() => find.descendant(
  of: find.byKey(const ValueKey('timetable-vertical-scroll')),
  matching: find.byType(Scrollable),
);

Finder _selectable(String value) => find.byWidgetPredicate(
  (widget) => widget is SelectableText && widget.data == value,
);

Future<void> _scrollDetailsTo(WidgetTester tester, Finder finder) =>
    tester.scrollUntilVisible(
      finder,
      180,
      maxScrolls: 60,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('schedule-course-details-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );

void _setSize(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}
