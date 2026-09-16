import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zf_core/zf_core.dart';
import 'package:zfhelper/data/repositories/schedule_repository.dart';
import 'package:zfhelper/data/storage/appearance_store.dart';
import 'package:zfhelper/data/storage/schedule_store.dart';
import 'package:zfhelper/platform/schedule_widget_platform.dart';
import 'package:zfhelper/ui/features/schedule/view_models/schedule_widget_projection.dart';
import 'package:zfhelper/ui/features/settings/view_models/schedule_widget_view_model.dart';

import '../../../support/schedule_fakes.dart';
import '../../../support/settings_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'projects every explicit week without inventing dates or clock times',
    () {
      final snapshot = scheduleTestSnapshot(
        entries: [
          ScheduleEntry(
            id: 'dated',
            name: '实验课',
            weekday: 1,
            startPeriod: 6,
            endPeriod: 7,
            weeks: [1, 3, 21],
          ),
          ScheduleEntry(id: 'undated', name: '待公布课程', weeks: [1]),
        ],
      );
      Map<String, Object?> project(ScheduleSnapshot value) =>
          projectScheduleWidget(
            ScheduleRepositoryState(
              initialized: true,
              library: ScheduleLibrary(
                accounts: [scheduleTestSaved(snapshot: value)],
                selectedAccount: scheduleTestAccount.scope,
              ),
            ),
          );

      final projection = project(snapshot);
      final days = (projection['days']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(days.map((day) => day['date']), [
        '2026-09-07',
        '2026-09-21',
        '2027-01-25',
      ]);
      expect(days.last['week'], 21);
      final lesson =
          (days.first['lessons']! as List<Object?>).single!
              as Map<String, Object?>;
      expect(days.first['byPeriod'], isTrue);
      expect(lesson['periodLabel'], '第 6–7 节');
      expect(lesson['startMinutes'], isNull);
      expect(lesson['endMinutes'], isNull);

      final unknown = project(
        snapshot.copyWith(calendar: const TeachingCalendar.unknown()),
      );
      expect(unknown['status'], 'calendarMissing');
      expect(unknown['days'], isEmpty);
    },
  );

  test(
    'drains changes during publishing and status reads before completing',
    () async {
      const channel = MethodChannel('zfhelper/schedule_widget');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final publishStarted = Completer<void>();
      final publishGate = Completer<void>();
      final statusStarted = Completer<void>();
      final statusGate = Completer<void>();
      final writes = <Map<String, Object?>>[];
      String? failure;
      var failNext = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'publish':
            if (failNext) {
              failNext = false;
              failure = '小组件写入失败';
              throw PlatformException(code: 'widget_storage', message: failure);
            }
            final arguments = call.arguments as Map<Object?, Object?>;
            writes.add(
              jsonDecode(arguments['payload']! as String)
                  as Map<String, Object?>,
            );
            if (!publishStarted.isCompleted) {
              publishStarted.complete();
              await publishGate.future;
            }
            failure = null;
            return null;
          case 'capabilities':
            if (!statusStarted.isCompleted) {
              statusStarted.complete();
              await statusGate.future;
            }
            return {
              'supported': true,
              'canPin': true,
              'count': 1,
              'failure': failure,
            };
          default:
            throw StateError('Unexpected widget method: ${call.method}');
        }
      });
      final repository = testScheduleRepository(
        store: TestScheduleStore(
          library: ScheduleLibrary(
            accounts: [scheduleTestSaved()],
            selectedAccount: scheduleTestAccount.scope,
          ),
        ),
      );
      final appearance = testAppearance();
      await repository.initialize();
      await appearance.initialize();
      final model = ScheduleWidgetViewModel(
        repository: repository,
        appearance: appearance,
        platform: AndroidScheduleWidgetPlatform(channel: channel),
        clock: () => DateTime(2026, 9, 16),
      );
      addTearDown(() async {
        model.dispose();
        appearance.dispose();
        await repository.dispose();
        messenger.setMockMethodCallHandler(channel, null);
      });

      final syncing = model.synchronize();
      await publishStarted.future;
      await appearance.select(AppAppearance.dark);
      publishGate.complete();
      await statusStarted.future;
      expect(await repository.removeAccount(scheduleTestAccount.scope), isTrue);
      statusGate.complete();
      expect(await syncing, isTrue);
      expect(writes.map((value) => value['status']), [
        'ready',
        'ready',
        'noAccount',
      ]);
      expect(writes.last['account'], isNull);
      expect(writes.last['days'], isEmpty);
      expect(writes.last['appearance'], 'dark');
      expect(model.busy, isFalse);

      failNext = true;
      expect(await model.synchronize(), isFalse);
      expect(model.failure, '小组件写入失败');
      expect(await model.synchronize(), isTrue);
      expect(model.failure, isNull);
    },
  );
}
