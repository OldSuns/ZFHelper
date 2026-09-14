import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zfhelper/app/app.dart';
import 'package:zfhelper/app/app_configuration.dart';
import 'package:zfhelper/data/storage/appearance_store.dart';
import 'package:zfhelper/platform/secure_appearance_store.dart';
import 'package:zfhelper/ui/features/courses/views/courses_page.dart';
import 'package:zfhelper/ui/features/schedule/views/timetable_page.dart';
import 'package:zfhelper/ui/features/settings/views/account_settings_page.dart';
import 'package:zfhelper/ui/features/settings/views/settings_page.dart';

import 'support/auth_fakes.dart';
import 'support/schedule_fakes.dart';
import 'support/grade_fakes.dart';
import 'support/course_fakes.dart';
import 'support/settings_fakes.dart';

void main() {
  Future<void> pumpApp(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double textScale = 1,
    Brightness brightness = Brightness.light,
    AppClock? clock,
    AppearanceStore? appearanceStore,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      ZfHelperApp(
        configuration: AppConfiguration(
          appearance: testAppearance(store: appearanceStore),
          courses: testCourseRepository(),
          grades: testGradeRepository(),
          auth: testAuth(),
          schedule: testScheduleRepository(),
          clock: clock ?? () => DateTime(2026, 9, 12, 13),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder navigationLabel(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  testWidgets('appearance choices apply globally and survive app recreation', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    await pumpApp(tester, appearanceStore: SecureAppearanceStore());
    await tester.tap(navigationLabel('设置'));
    await tester.pumpAndSettle();

    Future<void> choose(String label) async {
      final entry = find.widgetWithText(ListTile, '外观');
      await tester.scrollUntilVisible(entry, 150);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(SimpleDialog),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
    }

    await choose('深色');
    expect(
      Theme.of(tester.element(find.byType(SettingsPage))).brightness,
      Brightness.dark,
    );
    expect(await SecureAppearanceStore().read(), AppAppearance.dark);

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpApp(tester, appearanceStore: SecureAppearanceStore());
    expect(
      Theme.of(tester.element(find.byType(TimetablePage))).brightness,
      Brightness.dark,
    );
    await tester.tap(navigationLabel('设置'));
    await tester.pumpAndSettle();
    await choose('浅色');
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(SettingsPage))).brightness,
      Brightness.light,
    );

    await choose('跟随系统');
    expect(
      Theme.of(tester.element(find.byType(SettingsPage))).brightness,
      Brightness.dark,
    );
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(SettingsPage))).brightness,
      Brightness.light,
    );
    expect(await SecureAppearanceStore().read(), AppAppearance.system);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android-sized startup opens timetable for the target school', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.byType(TimetablePage), findsOneWidget);
    expect(find.text('示例大学'), findsOneWidget);
    expect(find.text('未连接教务账号'), findsOneWidget);
    expect(find.text('课表还没有同步'), findsOneWidget);
    expect(find.text('9月7日 — 9月13日'), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('第1周'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('week navigation changes dates and returns to current week', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip('下一周'));
    await tester.pump();
    expect(find.text('9月14日 — 9月20日'), findsOneWidget);

    await tester.tap(find.byTooltip('上一周'));
    await tester.pump();
    await tester.tap(find.byTooltip('上一周'));
    await tester.pump();
    expect(find.text('8月31日 — 9月6日'), findsOneWidget);

    await tester.tap(find.text('回到本周'));
    await tester.pump();
    expect(find.text('9月7日 — 9月13日'), findsOneWidget);
  });

  testWidgets('switching destinations preserves the browsed timetable week', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('下一周'));
    await tester.pump();

    await tester.tap(navigationLabel('成绩'));
    await tester.pumpAndSettle();
    expect(find.text('登录后查询成绩'), findsOneWidget);

    await tester.tap(navigationLabel('课表'));
    await tester.pumpAndSettle();
    expect(find.text('9月14日 — 9月20日'), findsOneWidget);
  });

  testWidgets(
    'settings opens account management and returns through both pages',
    (tester) async {
      await pumpApp(tester);
      await tester.tap(navigationLabel('设置'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, '账号与学校'));
      await tester.pumpAndSettle();
      expect(find.byType(AccountSettingsPage), findsOneWidget);
      expect(find.text('这所学校还没有账号'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('add-account')))
            .onPressed,
        isNotNull,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(TimetablePage), findsOneWidget);
    },
  );

  testWidgets(
    'four destinations include courses and Android back returns home',
    (tester) async {
      await pumpApp(tester);
      expect(navigationLabel('任务'), findsNothing);
      expect(
        tester
            .widget<NavigationBar>(find.byType(NavigationBar))
            .destinations
            .cast<NavigationDestination>()
            .map((destination) => destination.label),
        ['课表', '选课', '成绩', '设置'],
      );
      await tester.tap(navigationLabel('选课'));
      await tester.pumpAndSettle();
      expect(find.byType(CoursesPage), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(TimetablePage), findsOneWidget);
    },
  );

  testWidgets('wide window uses side navigation with the same default page', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(1280, 800));

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(TimetablePage), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('选课'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CoursesPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'small phone supports 200% text with system ${brightness.name}',
      (tester) async {
        await pumpApp(
          tester,
          size: const Size(320, 640),
          textScale: 2,
          brightness: brightness,
        );
        expect(
          Theme.of(tester.element(find.byType(TimetablePage))).brightness,
          brightness,
        );
        expect(tester.takeException(), isNull);

        final action = find.widgetWithText(FilledButton, '前往设置');
        await tester.scrollUntilVisible(action, 200);
        await tester.pumpAndSettle();
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(find.byType(SettingsPage), findsOneWidget);
        await tester.scrollUntilVisible(
          find.widgetWithText(ListTile, '关于应用'),
          200,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('landscape content remains scrollable above the navigation', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(780, 360));
    final action = find.widgetWithText(FilledButton, '前往设置');
    await tester.scrollUntilVisible(action, 200);
    await tester.pumpAndSettle();
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short wide windows allow scrolling the side destinations', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(900, 360), textScale: 2);
    final settings = find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text('设置'),
    );
    await tester.ensureVisible(settings);
    await tester.pumpAndSettle();
    await tester.tap(settings);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('home controls are accessible in ${brightness.name} theme', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await pumpApp(tester, brightness: brightness);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        expect(find.bySemanticsLabel('9月12日，星期六，今天'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets(
    'foreground midnight advances the current week and today marker',
    (tester) async {
      var now = DateTime(2026, 9, 13, 23, 59);
      await pumpApp(tester, clock: () => now);
      expect(find.text('9月7日 — 9月13日'), findsOneWidget);

      now = DateTime(2026, 9, 14);
      await tester.pump(const Duration(minutes: 1));
      await tester.pump();

      expect(find.text('9月14日 — 9月20日'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('returning from settings after midnight shows the new week', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 13, 23, 59);
    await pumpApp(tester, clock: () => now);
    await tester.tap(navigationLabel('设置'));
    await tester.pumpAndSettle();

    now = DateTime(2026, 9, 14);
    await tester.pump(const Duration(minutes: 1));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('9月14日 — 9月20日'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
