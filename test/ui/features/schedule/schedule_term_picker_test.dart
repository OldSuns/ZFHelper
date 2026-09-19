import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zf_core/zf_core.dart';
import 'package:zfhelper/data/storage/schedule_store.dart';
import 'package:zfhelper/ui/features/schedule/views/schedule_picker_sheets.dart';

import '../../../support/schedule_fakes.dart';

void main() {
  testWidgets(
    'manual year and semester are available without any school catalog',
    (tester) async {
      final result = Completer<AcademicTerm?>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async => result.complete(
                  await showScheduleTermPicker(
                    context,
                    account: StoredScheduleAccount(
                      account: scheduleTestAccount,
                    ),
                    forImport: true,
                  ),
                ),
                child: const Text('选择导入学期'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('选择导入学期'));
      await tester.pumpAndSettle();
      final year = find.byKey(const ValueKey('schedule-manual-year'));
      expect(find.text('手动选择学年学期'), findsOneWidget);
      expect(year, findsNothing);
      await tester.tap(find.text('手动选择学年学期'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(year).controller!.text, isEmpty);
      await tester.enterText(year, '2025');
      final semester = find.byKey(const ValueKey('schedule-manual-semester'));
      await tester.ensureVisible(semester);
      await tester.pumpAndSettle();
      await tester.tap(semester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('第二学期').last);
      await tester.pumpAndSettle();
      final submit = find.byKey(const ValueKey('schedule-manual-term-submit'));
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pumpAndSettle();
      final selected = (await result.future)!;
      expect(selected.yearCode, '2025');
      expect(selected.termCode, '12');
      expect(selected.label, '2025–2026 学年 第二学期');
      expect(tester.takeException(), isNull);
    },
  );
}
