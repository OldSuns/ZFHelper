import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zf_core/zf_core.dart';
import 'package:zfhelper/data/repositories/schedule_repository.dart';
import 'package:zfhelper/data/storage/schedule_store.dart';
import 'package:zfhelper/data/storage/sqlite_schedule_store.dart';

import '../../support/schedule_fakes.dart';

void main() {
  test('manual term selection recovers from catalog failure and retains saved metadata', () async {
    final snapshot = scheduleTestSnapshot();
    final catalog = TermCatalog(
      terms: [snapshot.term],
      selectedTerm: snapshot.term,
      yearOptions: const [TermOption(code: '2026', label: '2026–2027')],
      termOptions: const [
        TermOption(code: '3', label: '第一学期'),
        TermOption(code: '12', label: '第二学期'),
      ],
    );
    final source = TestScheduleSource(account: scheduleTestAccount)
      ..onRead = (term) async {
        if (term == null) {
          throw const ScheduleParseException(
            ScheduleParseCode.missingField,
            '学校页面未提供可识别的学年、学期选项',
            field: 'xnm/xqm',
          );
        }
        return ScheduleImportResult(snapshot: scheduleTestSnapshot(term: term));
      };
    final repository = testScheduleRepository(
      source: source,
      store: TestScheduleStore(
        library: ScheduleLibrary(
          selectedAccount: scheduleTestAccount.scope,
          accounts: [
            StoredScheduleAccount(
              account: scheduleTestAccount,
              catalog: catalog,
              schedules: {snapshot.term.key: snapshot},
              selectedTermKey: snapshot.term.key,
            ),
          ],
        ),
      ),
    );
    addTearDown(source.dispose);
    addTearDown(repository.dispose);
    await repository.initialize();
    expect(await repository.refresh(useSchoolDefault: true), isFalse);
    expect(repository.state.failure!.kind, ScheduleFailureKind.termSelection);
    expect(repository.state.imported, same(snapshot));
    final manual = AcademicTerm.zhengfang(
      startYear: '2026',
      semester: ZhengfangSemester.second,
    );
    expect(await repository.selectTerm(manual), isTrue);
    expect(await repository.refresh(), isTrue);
    expect(repository.state.imported!.term, manual);
    expect(
      repository.state.account!.catalog!.selectedTerm,
      catalog.selectedTerm,
    );
    expect(repository.state.account!.catalog!.yearOptions.single.code, '2026');
    expect(
      repository.state.account!.catalog!.termOptions.map((value) => value.code),
      ['3', '12'],
    );
    expect(repository.state.account!.schedules, hasLength(2));
  });

  test('imports once, retains failed refresh, and reopens SQLite offline with user settings', () async {
    final directory = await Directory.systemTemp.createTemp(
      'zfhelper-repository-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/schedule.sqlite3';
    final source = TestScheduleSource(account: scheduleTestAccount)
      ..onRead = (_) async => _import();
    final repository = ScheduleRepository(
      store: SqliteScheduleStore(databasePath: () async => path),
      source: source,
    );
    await repository.initialize();
    expect(source.requests, 0);
    expect(await repository.refresh(), isTrue);
    final importedAt = repository.state.imported!.fetchedAt;
    await repository.updateSettings(
      target: repository.state.target!,
      update: (settings, _) => settings.copyWith(
        preferAgenda: true,
        calendarOverride: TeachingCalendar(
          firstWeekMonday: DateTime(2026, 8, 31),
          source: TeachingCalendarSource.user,
        ),
      ),
    );
    source.onRead = (_) =>
        Future.error(const LoginFailure(LoginFailureCode.network, '测试断网'));
    expect(await repository.refresh(), isFalse);
    expect(repository.state.imported!.fetchedAt, importedAt);
    expect(repository.state.failure!.kind, ScheduleFailureKind.network);
    await repository.dispose();
    await source.dispose();

    final offline = TestScheduleSource();
    final reopened = ScheduleRepository(
      store: SqliteScheduleStore(databasePath: () async => path),
      source: offline,
    );
    addTearDown(offline.dispose);
    addTearDown(reopened.dispose);
    await reopened.initialize();
    expect(reopened.state.imported!.entries.single.name, '高等数学');
    expect(
      reopened.state.imported!.fetchedAt.isAtSameMomentAs(importedAt),
      isTrue,
    );
    expect(reopened.state.settings.preferAgenda, isTrue);
    expect(
      reopened.state.effective!.calendar.firstWeekMonday,
      DateTime(2026, 8, 31),
    );
    expect(offline.requests, 0);
  });

  test(
    'clearing permits reimport and rejects an editor from before the clear',
    () async {
      const other = AcademicAccountRecord(
        scope: AccountScope(schoolId: 'other-school', accountId: 'student-b'),
        schoolName: '另一学校',
        accountName: '同学B',
        loginName: 'student-b',
      );
      final source = TestScheduleSource(account: scheduleTestAccount)
        ..onRead = (_) async => _import();
      final repository = testScheduleRepository(
        source: source,
        store: TestScheduleStore(
          library: ScheduleLibrary(
            accounts: [
              scheduleTestSaved(),
              StoredScheduleAccount(account: other),
            ],
            selectedAccount: scheduleTestAccount.scope,
          ),
        ),
      );
      addTearDown(source.dispose);
      addTearDown(repository.dispose);
      await repository.initialize();
      final oldTarget = repository.state.target!;
      expect(await repository.removeAccount(scheduleTestAccount.scope), isTrue);
      expect(
        repository.state.account!.account.scope,
        scheduleTestAccount.scope,
      );
      expect(repository.state.imported, isNull);
      expect(await repository.refresh(), isTrue);
      expect(
        await repository.updateSettings(
          target: oldTarget,
          update: (settings, _) => settings.copyWith(preferAgenda: true),
        ),
        isFalse,
      );
      expect(repository.state.settings.preferAgenda, isFalse);
    },
  );

  test(
    'coalesces repeated import clicks and ignores results after clearing',
    () async {
      final pending = Completer<ScheduleImportResult>();
      final source = TestScheduleSource(account: scheduleTestAccount)
        ..onRead = (_) => pending.future;
      final repository = testScheduleRepository(source: source);
      addTearDown(source.dispose);
      addTearDown(repository.dispose);
      await repository.initialize();
      final first = repository.refresh();
      final second = repository.refresh();
      expect(await second, isFalse);
      expect(source.requests, 1);
      await repository.removeAccount(scheduleTestAccount.scope);
      pending.complete(_import());
      expect(await first, isFalse);
      expect(repository.state.imported, isNull);
    },
  );
}

ScheduleImportResult _import() => ScheduleImportResult(
  catalog: TermCatalog(
    terms: [scheduleTestTerm],
    selectedTerm: scheduleTestTerm,
  ),
  snapshot: scheduleTestSnapshot(),
);
