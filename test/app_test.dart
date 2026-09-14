import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zfhelper/app/app.dart';
import 'package:zfhelper/app/app_configuration.dart';
import 'package:zfhelper/ui/features/schedule/views/timetable_page.dart';
import 'package:zfhelper/ui/features/settings/views/account_settings_page.dart';

import 'support/auth_fakes.dart';
import 'support/schedule_fakes.dart';

void main() {
  Future<void> pumpApp(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double textScale = 1,
    Brightness brightness = Brightness.light,
    AppClock? clock,
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
    expect(find.text('查看学期成绩'), findsOneWidget);

    await tester.tap(navigationLabel('课表'));
    await tester.pumpAndSettle();
    expect(find.text('9月14日 — 9月20日'), findsOneWidget);
  });

  testWidgets('account settings offers generic login and returns', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('账号与设置'));
    await tester.pumpAndSettle();

    expect(find.byType(AccountSettingsPage), findsOneWidget);
    expect(find.text('支持自定义学校与新正方教务地址'), findsOneWidget);
    expect(find.text('尚未连接'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(TimetablePage), findsOneWidget);
  });

  testWidgets('task action routes to courses and Android back returns home', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(navigationLabel('任务'));
    await tester.pumpAndSettle();
    expect(find.text('还没有选课任务'), findsOneWidget);

    await tester.tap(find.text('前往选课'));
    await tester.pumpAndSettle();
    expect(find.text('查看可选课程'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TimetablePage), findsOneWidget);
  });

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
    expect(find.text('查看可选课程'), findsOneWidget);
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

        final action = find.widgetWithText(FilledButton, '账号与设置');
        await tester.scrollUntilVisible(action, 200);
        await tester.pumpAndSettle();
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(find.byType(AccountSettingsPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('landscape content remains scrollable above the navigation', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(780, 360));
    final action = find.widgetWithText(FilledButton, '账号与设置');
    await tester.scrollUntilVisible(action, 200);
    await tester.pumpAndSettle();
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.byType(AccountSettingsPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short wide windows allow scrolling the side destinations', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(900, 360), textScale: 2);
    final grades = find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text('成绩'),
    );
    await tester.ensureVisible(grades);
    await tester.pumpAndSettle();
    await tester.tap(grades);
    await tester.pumpAndSettle();
    expect(find.text('查看学期成绩'), findsOneWidget);
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
    await tester.tap(find.byTooltip('账号与设置'));
    await tester.pumpAndSettle();

    now = DateTime(2026, 9, 14);
    await tester.pump(const Duration(minutes: 1));
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('9月14日 — 9月20日'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
