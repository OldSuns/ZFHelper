import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zf_core/zf_core.dart';
import 'package:zfhelper/app/app.dart';
import 'package:zfhelper/app/app_configuration.dart';
import 'package:zfhelper/data/storage/schedule_store.dart';
import 'package:zfhelper/ui/core/app_theme.dart';
import 'package:zfhelper/ui/features/schedule/view_models/timetable_view_model.dart';
import 'package:zfhelper/ui/features/schedule/views/timetable_page.dart';

import '../../../support/auth_fakes.dart';
import '../../../support/schedule_fakes.dart';
import '../../../support/grade_fakes.dart';
import '../../../support/course_fakes.dart';
import '../../../support/settings_fakes.dart';

void main() {
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
    'swipes saved weeks and searches all term courses without networking',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = TestScheduleSource();
      final snapshot = scheduleTestSnapshot(
        entries: [
          ...scheduleTestSnapshot().entries,
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
