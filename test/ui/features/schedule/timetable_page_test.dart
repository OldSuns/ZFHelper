import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zf_core/zf_core.dart';
import 'package:zfhelper/app/app.dart';
import 'package:zfhelper/app/app_configuration.dart';
import 'package:zfhelper/data/storage/schedule_store.dart';
import 'package:zfhelper/ui/core/app_theme.dart';
import 'package:zfhelper/ui/features/schedule/view_models/schedule_agenda.dart';
import 'package:zfhelper/ui/features/schedule/view_models/timetable_view_model.dart';
import 'package:zfhelper/ui/features/schedule/views/course_editor_page.dart';
import 'package:zfhelper/ui/features/schedule/views/schedule_day_widgets.dart';
import 'package:zfhelper/ui/features/schedule/views/timetable_page.dart';
import 'package:zfhelper/ui/features/settings/views/schedule_settings_section.dart';

import '../../../support/auth_fakes.dart';
import '../../../support/schedule_fakes.dart';
import '../../../support/grade_fakes.dart';
import '../../../support/course_fakes.dart';
import '../../../support/settings_fakes.dart';

void main() {
  testWidgets(
    'agenda preserves period order and full ranges without clock times',
    (tester) async {
      final date = DateTime(2026, 9, 7);
      final entries = [
        for (final (name, start, end) in [
          ('A', 6, 7),
          ('Z', 1, 2),
          ('B', 10, 11),
        ])
          ScheduleEntry(
            id: name,
            name: name,
            weekday: 1,
            startPeriod: start,
            endPeriod: end,
            weeks: [1],
          ),
      ];
      for (final times in [
        <PeriodTime>[],
        [
          PeriodTime(number: 10, startMinutes: 1140, endMinutes: 1185),
          PeriodTime(number: 11, startMinutes: 1195, endMinutes: 1240),
        ],
      ]) {
        final day = ScheduleDay.fromSnapshot(
          scheduleTestSnapshot(entries: entries).copyWith(periodTimes: times),
          date,
        );
        final agenda = scheduleAgendaItems(day, const []);
        expect(day.lessons.map((lesson) => lesson.entry.startPeriod), [
          1,
          6,
          10,
        ]);
        expect(agenda.map((item) => item.lesson!.entry.startPeriod), [
          1,
          6,
          10,
        ]);
        expect(
          agenda.any((item) => item.group == AgendaTimeGroup.unspecified),
          isFalse,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ScheduleLessonTile(
                lesson: day.lessons[1],
                now: date,
                onTap: () {},
              ),
            ),
          ),
        );
        final label = find.text('第 6–7 节');
        expect(label, findsOneWidget);
        expect(
          tester.getTopLeft(label).dx,
          lessThan(tester.getTopLeft(find.text('A')).dx),
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'first use asks for school and address without any prefilled institution',
    (tester) async {
      final auth = AuthRepository(
        gatewayFactory: (_) => throw StateError('Unexpected login'),
        vault: TestLoginVault(),
      );
      final repository = testScheduleRepository();
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      await tester.pumpWidget(
        ZfHelperApp(
          configuration: AppConfiguration(
            appearance: testAppearance(),
            courses: testCourseRepository(),
            grades: testGradeRepository(),
            auth: auth,
            schedule: repository,
            clock: DateTime.now,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final address = find.byKey(const ValueKey('school-address'));
      final name = find.byKey(const ValueKey('school-name'));
      expect(tester.widget<TextField>(address).controller!.text, isEmpty);
      expect(tester.widget<TextField>(name).controller!.text, isEmpty);
      expect(auth.state.profile, isNull);
      await tester.enterText(
        address,
        'https://campus.example.test/jwglxt/xtgl/login_slogin.html',
      );
      await tester.ensureVisible(name);
      await tester.enterText(name, '用户填写的学校');
      final submit = find.byKey(const ValueKey('school-save'));
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(auth.state.profile!.name, '用户填写的学校');
      expect(auth.state.profile!.baseUri.host, 'campus.example.test');
      expect(find.text('登录教务系统'), findsOneWidget);
      expect(auth.state.isSignedIn, isFalse);
    },
  );

  testWidgets(
    'browses cached weeks offline and manages the timetable from settings',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = TestScheduleSource()..connect(scheduleTestAccount);
      final snapshot = scheduleTestSnapshot(
        entries: [
          ...scheduleTestSnapshot().entries,
          ScheduleEntry(id: 'undated', name: '待公布课程', weeks: [1]),
          ScheduleEntry(
            id: 'late-course',
            name: '学期末实验',
            weekday: 3,
            startPeriod: 3,
            endPeriod: 4,
            weeks: [21],
          ),
        ],
      );
      // Storage futures and stream cancellation belong to the real async zone;
      // only the widget's clock/timer is controlled by FakeAsync.
      final repository = (await tester.runAsync(() async {
        final repository = testScheduleRepository(
          source: source,
          store: TestScheduleStore(
            library: ScheduleLibrary(
              accounts: [scheduleTestSaved(snapshot: snapshot)],
              selectedAccount: scheduleTestAccount.scope,
            ),
          ),
        );
        await repository.initialize();
        return repository;
      }))!;
      final model = TimetableViewModel(
        repository: repository,
        clock: () => DateTime(2026, 9, 7),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(Brightness.light),
            home: Scaffold(
              body: TimetablePage(
                viewModel: model,
                schoolName: '测试学校',
                isSignedIn: false,
                onOpenSettings: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.drag(
          find.byKey(const ValueKey('timetable-week-pages')),
          const Offset(-350, 0),
        );
        await tester.pumpAndSettle();
        expect(model.selectedWeek, 2);
        await tester.tap(find.byTooltip('下一周'));
        await tester.pumpAndSettle();
        expect(model.selectedWeek, 3);
        await tester.tap(find.byTooltip('查找课程'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('schedule-search-input')),
          '学期末',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('学期末实验'));
        await tester.pumpAndSettle();
        expect(model.selectedWeek, 21);
        expect(find.text('课程详情'), findsOneWidget);
        final edit = find.widgetWithText(FilledButton, '本地调整');
        final hide = find.widgetWithText(OutlinedButton, '隐藏此安排');
        await tester.ensureVisible(hide);
        expect(tester.getSize(edit).height, tester.getSize(hide).height);
        await tester.tap(find.byTooltip('关闭课程详情'));
        await tester.pumpAndSettle();
        for (final size in [const Size(1366, 768), const Size(390, 844)]) {
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          expect(model.selectedWeek, 21);
          expect(find.text('学期末实验'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        expect(source.requests, 0);
        expect(tester.takeException(), isNull);

        expect(
          find.byKey(const ValueKey('schedule-section-today')),
          findsNothing,
        );
        await tester.tap(find.byKey(const ValueKey('schedule-section-agenda')));
        await tester.pumpAndSettle();
        expect(model.dayOn(model.agendaDate).week, 1);
        expect(model.selectedWeek, 21);
        expect(find.text('高等数学'), findsOneWidget);
        expect(find.text('待排安排'), findsNothing);
        expect(find.text('待公布课程'), findsNothing);
        expect(find.text('新建日程'), findsNothing);
        final addEvent = find.byKey(const ValueKey('schedule-add-event'));
        expect(tester.getCenter(addEvent).dx, greaterThan(320));
        await tester.tap(addEvent);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('schedule-event-title')),
          '小组讨论',
        );
        await tester.runAsync(
          () => tester.tap(find.byKey(const ValueKey('schedule-event-save'))),
        );
        await tester.pumpAndSettle();
        expect(model.events.single.title, '小组讨论');
        final checkbox = find.byType(Checkbox);
        await tester.ensureVisible(checkbox);
        await tester.runAsync(() => tester.tap(checkbox));
        await tester.pumpAndSettle();
        expect(model.events.single.completed, isTrue);
        for (final size in [const Size(1366, 768), const Size(320, 640)]) {
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        tester.view.physicalSize = const Size(390, 844);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('小组讨论'));
        await tester.tap(find.text('小组讨论'));
        await tester.pumpAndSettle();
        await tester.runAsync(() => tester.tap(find.byTooltip('删除日程')));
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => tester.tap(find.widgetWithText(FilledButton, '删除')),
        );
        await tester.pumpAndSettle();
        expect(model.events, isEmpty);
        expect(source.requests, 0);

        source.onRead = (_) async => ScheduleImportResult(snapshot: snapshot);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(Brightness.light),
            home: Scaffold(
              body: SingleChildScrollView(
                child: ScheduleSettingsSection(viewModel: model),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => tester.tap(find.widgetWithText(ListTile, '更新课表')),
        );
        await tester.pumpAndSettle();
        expect(source.requests, 1);
        expect(model.data.failure, isNull);
        await tester.ensureVisible(find.byType(SwitchListTile));
        await tester.runAsync(() => tester.tap(find.byType(SwitchListTile)));
        await tester.pumpAndSettle();
        expect(model.agenda, isTrue);
        expect(repository.state.settings.preferAgenda, isTrue);
        final addCourse = find.widgetWithText(ListTile, '添加课程');
        await tester.ensureVisible(addCourse);
        await tester.tap(addCourse);
        await tester.pumpAndSettle();
        expect(find.byType(CourseEditorPage), findsOneWidget);
        expect(source.requests, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        model.dispose();
        await tester.pump();
        await tester.runAsync(() async {
          await repository.dispose();
          await source.dispose();
        });
      }
    },
  );
}
