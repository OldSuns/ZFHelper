import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:zf_core/zf_core.dart';
import 'package:zfhelper/data/storage/schedule_store.dart';
import 'package:zfhelper/data/storage/sqlite_schedule_store.dart';

// Constructed offline data; these tests never connect to a school or read
// the application's database. Every test owns a new system temporary folder.
void main() {
  late Directory directory;
  late String databasePath;
  late SqliteScheduleStore store;
  final stores = <SqliteScheduleStore>[];

  SqliteScheduleStore openStore() {
    final opened = SqliteScheduleStore(databasePath: () async => databasePath);
    stores.add(opened);
    return opened;
  }

  void inspectDatabase(void Function(Database) inspect) {
    final database = sqlite3.open(databasePath);
    try {
      inspect(database);
    } finally {
      database.close();
    }
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'zfhelper_schedule_store_',
    );
    databasePath = '${directory.path}${Platform.pathSeparator}schedule.sqlite';
    store = openStore();
  });

  tearDown(() async {
    await Future.wait(stores.map((opened) => opened.close()));
    stores.clear();
    final target = await directory.resolveSymbolicLinks();
    final temporaryRoot = await Directory.systemTemp.resolveSymbolicLinks();
    expect(Directory(target).parent.path, temporaryRoot);
    await Directory(target).delete(recursive: true);
  });

  test('creates an explicitly versioned empty library', () async {
    final library = await store.read();

    expect(library.accounts, isEmpty);
    expect(library.selectedAccount, isNull);
    expect(await File(databasePath).exists(), isTrue);
    inspectDatabase((database) => expect(database.userVersion, 1));
  });

  test(
    'reopening restores terms, selections, imports and user settings',
    () async {
      final autumn = _term();
      final spring = _term(termCode: '12', label: '2026–2027 学年第二学期');
      final first = _snapshot(autumn);
      final second = _snapshot(spring, name: '大学物理');
      final settings = _settings();
      final account = _account(
        catalog: TermCatalog(
          terms: [autumn, spring],
          selectedTerm: autumn,
          yearOptions: const [TermOption(code: '2026', label: '2026–2027')],
          termOptions: const [
            TermOption(code: '3', label: '第一学期'),
            TermOption(code: '12', label: '第二学期'),
          ],
        ),
        schedules: {autumn.key: first, spring.key: second},
        settings: {autumn.key: settings},
        selectedTermKey: spring.key,
      );
      await store.saveAccount(account, select: true);
      await store.close();

      final library = await openStore().read();
      final restored = library.accounts.single;

      expect(library.selectedAccount, account.account.scope);
      expect(restored.account.schoolName, '测试大学');
      expect(restored.account.accountName, '测试同学');
      expect(restored.account.loginName, '20260001');
      expect(restored.selectedTermKey, spring.key);
      expect(restored.catalog!.selectedTerm, autumn);
      expect(restored.catalog!.terms, [autumn, spring]);
      expect(restored.catalog!.yearOptions.single.code, '2026');
      expect(restored.catalog!.termOptions.map((term) => term.code), [
        '3',
        '12',
      ]);
      expect(restored.schedules[autumn.key]!.entries.single.name, '高等数学');
      expect(restored.schedules[spring.key]!.entries.single.name, '大学物理');
      expect(restored.schedules[autumn.key]!.fetchedAt, first.fetchedAt);
      expect(
        restored.schedules[autumn.key]!.calendar.firstWeekMonday,
        DateTime(2026, 8, 31),
      );
      final userSettings = restored.settings[autumn.key]!;
      expect(
        userSettings.calendarOverride!.firstWeekMonday,
        DateTime(2026, 9, 7),
      );
      expect(
        userSettings.calendarOverride!.source,
        TeachingCalendarSource.user,
      );
      expect(userSettings.localEntries.single.name, '自习');
      expect(
        userSettings.localEntries.single.origin,
        ScheduleEntryOrigin.local,
      );
      expect(userSettings.hiddenEntryIds, {'school-math'});
      expect(userSettings.periodTimes.single.startMinutes, 8 * 60 + 15);
    },
  );

  test(
    'isolates identical account IDs at different schools and classmates',
    () async {
      final term = _term();
      final records = [
        _account(
          schoolId: 'school-a',
          schedules: {term.key: _snapshot(term, name: '学校甲课程')},
        ),
        _account(
          schoolId: 'school-b',
          schedules: {term.key: _snapshot(term, name: '学校乙课程')},
        ),
        _account(
          schoolId: 'school-a',
          accountId: 'other-student',
          schedules: {term.key: _snapshot(term, name: '另一同学课程')},
        ),
      ];
      for (final record in records) {
        await store.saveAccount(record);
      }
      await store.selectAccount(records.first.account.scope);

      final library = await openStore().read();

      expect(library.accounts, hasLength(3));
      for (final record in records) {
        final restored = library.accounts.singleWhere(
          (item) => item.account.scope == record.account.scope,
        );
        expect(
          restored.schedules[term.key]!.entries.single.name,
          record.schedules[term.key]!.entries.single.name,
        );
      }
      expect(library.selectedAccount, records.first.account.scope);
    },
  );

  test('keeps an empty successful import distinct from no import', () async {
    final term = _term();
    final empty = ScheduleSnapshot(
      term: term,
      entries: const [],
      fetchedAt: DateTime.utc(2001, 1, 1),
    );
    await store.saveAccount(
      _account(schedules: {term.key: empty}, selectedTermKey: term.key),
    );
    await store.saveAccount(_account(accountId: 'not-imported'));

    final library = await openStore().read();
    final imported = library.accounts.singleWhere(
      (item) => item.account.scope.accountId == 'student',
    );
    final untouched = library.accounts.singleWhere(
      (item) => item.account.scope.accountId == 'not-imported',
    );

    expect(imported.schedules[term.key]!.entries, isEmpty);
    expect(imported.schedules[term.key]!.fetchedAt, DateTime.utc(2001, 1, 1));
    expect(untouched.schedules, isEmpty);
    expect((await store.read()).accounts, hasLength(2));
  });

  test('preserves Unicode and SQL punctuation as ordinary values', () async {
    final term = _term();
    final account = _account(
      schoolId: "school'); DROP TABLE schedule_accounts; --",
      accountId: '学生/α?&|',
      schedules: {term.key: _snapshot(term, name: "线性代数 'SQL' ?")},
    );
    await store.saveAccount(account, select: true);
    await store.saveAccount(_account(accountId: 'unrelated'));

    final library = await openStore().read();
    final restored = library.accounts.singleWhere(
      (item) => item.account.scope == account.account.scope,
    );

    expect(library.accounts, hasLength(2));
    expect(library.selectedAccount, account.account.scope);
    expect(restored.schedules[term.key]!.entries.single.name, "线性代数 'SQL' ?");
  });

  test(
    'refreshes an import while retaining separately supplied local settings',
    () async {
      final term = _term();
      await store.saveAccount(
        _account(
          schedules: {term.key: _snapshot(term)},
          settings: {term.key: _settings()},
        ),
        select: true,
      );
      final previous = (await store.read()).accounts.single;
      final updated = _snapshot(term, name: '更新后的课程');
      await store.saveAccount(
        StoredScheduleAccount(
          account: previous.account,
          schedules: {term.key: updated},
          settings: previous.settings,
        ),
      );

      final restored = (await openStore().read()).accounts.single;

      expect(restored.schedules[term.key]!.entries.single.name, '更新后的课程');
      expect(restored.settings[term.key]!.localEntries.single.name, '自习');
      expect(restored.settings[term.key]!.hiddenEntryIds, {'school-math'});
      expect(
        restored.schedules[term.key]!.calendar.source,
        TeachingCalendarSource.school,
      );
      expect(
        restored.settings[term.key]!.calendarOverride!.source,
        TeachingCalendarSource.user,
      );
    },
  );

  test('copies caller collections before asynchronous persistence', () async {
    final term = _term();
    final schedules = {term.key: _snapshot(term)};
    final settings = {term.key: _settings()};
    final record = _account(schedules: schedules, settings: settings);
    schedules.clear();
    settings.clear();
    await store.saveAccount(record);

    final library = await store.read();

    expect(library.accounts.single.schedules, hasLength(1));
    expect(library.accounts.single.settings, hasLength(1));
    expect(() => library.accounts.clear(), throwsUnsupportedError);
    expect(
      () => library.accounts.single.schedules.clear(),
      throwsUnsupportedError,
    );
    expect(
      () => library.accounts.single.settings.clear(),
      throwsUnsupportedError,
    );
  });

  test(
    'deletion chooses the most recently selected remaining account',
    () async {
      final first = _account(accountId: 'first');
      final second = _account(accountId: 'second');
      final third = _account(accountId: 'third');
      for (final account in [first, second, third]) {
        await store.saveAccount(account, select: true);
      }
      await store.selectAccount(first.account.scope);
      await store.selectAccount(third.account.scope);
      // A background write must not count as browsing another account.
      await store.saveAccount(second);
      await store.removeAccount(third.account.scope);

      expect((await store.read()).selectedAccount, first.account.scope);
      await store.removeAccount(first.account.scope);
      expect((await store.read()).selectedAccount, second.account.scope);
      await store.removeAccount(second.account.scope);
      final empty = await openStore().read();
      expect(empty.accounts, isEmpty);
      expect(empty.selectedAccount, isNull);
      await store.removeAccount(second.account.scope);
      expect((await store.read()).accounts, isEmpty);
    },
  );

  test(
    'removing a different school leaves the selected account unchanged',
    () async {
      final selected = _account(schoolId: 'selected-school');
      final other = _account(schoolId: 'other-school');
      await store.saveAccount(selected, select: true);
      await store.saveAccount(other);

      await store.removeAccount(other.account.scope);

      final library = await openStore().read();
      expect(library.accounts.single.account.scope, selected.account.scope);
      expect(library.selectedAccount, selected.account.scope);
    },
  );

  test(
    'rejects selecting a missing account without changing the selection',
    () async {
      final account = _account();
      await store.saveAccount(account, select: true);

      await expectLater(
        store.selectAccount(
          const AccountScope(schoolId: 'missing', accountId: 'student'),
        ),
        throwsA(isA<ScheduleStorageException>()),
      );

      expect((await store.read()).selectedAccount, account.account.scope);
    },
  );

  test(
    'rolls back a write and its selection when a later statement fails',
    () async {
      final term = _term();
      final original = _account(schedules: {term.key: _snapshot(term)});
      final other = _account(accountId: 'selected');
      await store.saveAccount(original);
      await store.saveAccount(other, select: true);
      inspectDatabase((database) {
        database.execute('''
        CREATE TRIGGER reject_selection
        BEFORE UPDATE OF selected_school_id ON schedule_metadata
        BEGIN
          SELECT RAISE(ABORT, 'synthetic failure after account write');
        END
      ''');
      });

      final replacement = _account(
        schedules: {term.key: _snapshot(term, name: '必须回滚的课程')},
        settings: {term.key: _settings()},
        selectedTermKey: term.key,
      );
      await expectLater(
        store.saveAccount(replacement, select: true),
        throwsA(
          isA<ScheduleStorageException>().having(
            (error) => error.sqliteCode,
            'SQLite failure code',
            isNotNull,
          ),
        ),
      );
      final unchanged = await store.read();
      final restored = unchanged.accounts.singleWhere(
        (item) => item.account.scope == original.account.scope,
      );
      expect(restored.schedules[term.key]!.entries.single.name, '高等数学');
      expect(restored.settings, isEmpty);
      expect(restored.selectedTermKey, isNull);
      expect(unchanged.selectedAccount, other.account.scope);

      inspectDatabase(
        (database) => database.execute('DROP TRIGGER reject_selection'),
      );
      await store.saveAccount(replacement, select: true);
      final retried = await openStore().read();
      expect(retried.selectedAccount, original.account.scope);
      expect(
        retried.accounts.first.schedules[term.key]!.entries.single.name,
        '必须回滚的课程',
      );
    },
  );

  test(
    'refuses a mismatched term key without replacing the previous import',
    () async {
      final term = _term();
      await store.saveAccount(_account(schedules: {term.key: _snapshot(term)}));

      await expectLater(
        store.saveAccount(
          _account(schedules: {'different-term': _snapshot(term)}),
        ),
        throwsA(isA<ScheduleStorageException>()),
      );

      expect((await store.read()).accounts.single.schedules.keys, [term.key]);
    },
  );

  test(
    'rolls back deletion when updating its selected account fails',
    () async {
      final term = _term();
      final original = _account(
        schedules: {term.key: _snapshot(term)},
        settings: {term.key: _settings()},
      );
      await store.saveAccount(original, select: true);
      inspectDatabase((database) {
        database.execute('''
        CREATE TRIGGER reject_deselection
        BEFORE UPDATE OF selected_school_id ON schedule_metadata
        BEGIN
          SELECT RAISE(ABORT, 'synthetic failure during account removal');
        END
      ''');
      });

      await expectLater(
        store.removeAccount(original.account.scope),
        throwsA(isA<ScheduleStorageException>()),
      );

      final restored = await openStore().read();
      expect(restored.selectedAccount, original.account.scope);
      expect(
        restored.accounts.single.schedules[term.key]!.entries.single.name,
        '高等数学',
      );
      expect(
        restored.accounts.single.settings[term.key]!.localEntries.single.name,
        '自习',
      );
    },
  );

  test('does not reset or downgrade an unknown database version', () async {
    await store.saveAccount(_account(), select: true);
    inspectDatabase((database) => database.userVersion = 99);

    await expectLater(store.read(), throwsA(isA<ScheduleStorageException>()));
    await expectLater(
      store.saveAccount(_account()),
      throwsA(isA<ScheduleStorageException>()),
    );

    inspectDatabase((database) {
      expect(database.userVersion, 99);
      expect(database.select('SELECT * FROM schedule_accounts'), hasLength(1));
    });
  });

  test('keeps an unversioned existing database untouched', () async {
    inspectDatabase((database) {
      database.execute('CREATE TABLE existing_data (value TEXT NOT NULL)');
      database.execute('INSERT INTO existing_data VALUES (?)', ['preserve']);
    });

    await expectLater(store.read(), throwsA(isA<ScheduleStorageException>()));

    inspectDatabase((database) {
      expect(database.userVersion, 0);
      expect(
        database.select('SELECT value FROM existing_data').single['value'],
        'preserve',
      );
      expect(
        database.select(
          "SELECT name FROM sqlite_master WHERE name = 'schedule_accounts'",
        ),
        isEmpty,
      );
    });
  });

  test('rolls back partially executed first-schema creation', () async {
    inspectDatabase((database) {
      database.execute(
        'CREATE VIEW schedule_metadata AS SELECT 1 AS preserved',
      );
    });

    await expectLater(store.read(), throwsA(isA<ScheduleStorageException>()));

    inspectDatabase((database) {
      expect(database.userVersion, 0);
      expect(
        database
            .select('SELECT preserved FROM schedule_metadata')
            .single['preserved'],
        1,
      );
      expect(
        database.select(
          "SELECT name FROM sqlite_master WHERE name = 'schedule_accounts'",
        ),
        isEmpty,
      );
    });
  });

  test(
    'reports corrupt JSON without disclosing or overwriting the payload',
    () async {
      await store.saveAccount(_account());
      const damaged = '{ damaged private course title';
      inspectDatabase((database) {
        database.execute('UPDATE schedule_accounts SET schedules_payload = ?', [
          damaged,
        ]);
      });

      await expectLater(
        store.read(),
        throwsA(
          isA<ScheduleStorageException>().having(
            (error) => error.toString(),
            'safe diagnostic',
            isNot(contains('private course title')),
          ),
        ),
      );
      await expectLater(
        openStore().read(),
        throwsA(isA<ScheduleStorageException>()),
      );

      inspectDatabase((database) {
        expect(
          database
              .select('SELECT schedules_payload FROM schedule_accounts')
              .single['schedules_payload'],
          damaged,
        );
      });
    },
  );

  test('rejects unsupported domain payload versions', () async {
    final term = _term();
    await store.saveAccount(_account(schedules: {term.key: _snapshot(term)}));
    inspectDatabase((database) {
      final encoded =
          database
                  .select('SELECT schedules_payload FROM schedule_accounts')
                  .single['schedules_payload']
              as String;
      final schedules = jsonDecode(encoded) as Map<String, Object?>;
      final snapshot = schedules[term.key] as Map<String, Object?>;
      snapshot['version'] = 999;
      database.execute('UPDATE schedule_accounts SET schedules_payload = ?', [
        jsonEncode(schedules),
      ]);
    });

    await expectLater(store.read(), throwsA(isA<ScheduleStorageException>()));
  });

  test(
    'reports invalid metadata instead of inventing a selected account',
    () async {
      await store.saveAccount(_account(), select: true);
      inspectDatabase((database) {
        database.execute('PRAGMA foreign_keys = OFF');
        database.execute(
          'UPDATE schedule_metadata SET selected_school_id = ?',
          ['missing-school'],
        );
      });

      await expectLater(store.read(), throwsA(isA<ScheduleStorageException>()));
    },
  );

  test(
    'reports filesystem failure and permits a later explicit retry',
    () async {
      final blockingFile = File(
        '${directory.path}${Platform.pathSeparator}blocked',
      );
      await blockingFile.writeAsString('synthetic filesystem failure');
      final inaccessible = SqliteScheduleStore(
        databasePath: () async =>
            '${blockingFile.path}${Platform.pathSeparator}schedule.sqlite',
      );
      stores.add(inaccessible);

      await expectLater(
        inaccessible.saveAccount(_account()),
        throwsA(isA<ScheduleStorageException>()),
      );

      await blockingFile.delete();
      await inaccessible.saveAccount(_account());
      expect((await inaccessible.read()).accounts, hasLength(1));
    },
  );

  test('serializes accepted writes without an account-count quota', () async {
    final records = [
      for (var i = 0; i < 8; i++) _account(accountId: 'student-$i'),
    ];
    await Future.wait([
      for (final record in records) store.saveAccount(record, select: true),
    ]);

    final library = await openStore().read();

    expect(library.accounts, hasLength(records.length));
    expect(library.selectedAccount, records.last.account.scope);
    expect(
      library.accounts.map((item) => item.account.scope.accountId),
      records.reversed.map((item) => item.account.scope.accountId),
    );
  });

  test(
    'reports path-provider failure and resolves it again on explicit retry',
    () async {
      var attempts = 0;
      final deferred = SqliteScheduleStore(
        databasePath: () async {
          attempts++;
          if (attempts == 1) throw Exception('synthetic path-provider failure');
          return databasePath;
        },
      );
      stores.add(deferred);

      await expectLater(
        deferred.read(),
        throwsA(isA<ScheduleStorageException>()),
      );
      await deferred.saveAccount(_account());
      expect((await deferred.read()).accounts, hasLength(1));
      expect(attempts, 2);
    },
  );

  test(
    'rejects an in-memory path instead of reporting a durable save',
    () async {
      final volatile = SqliteScheduleStore(
        databasePath: () async => ':memory:',
      );
      stores.add(volatile);

      await expectLater(
        volatile.saveAccount(_account()),
        throwsA(isA<ScheduleStorageException>()),
      );
      expect(await File(databasePath).exists(), isFalse);
    },
  );

  test(
    'independent store instances can initialize and write one file safely',
    () async {
      final peers = [store, openStore(), openStore(), openStore()];
      await Future.wait([
        for (var i = 0; i < peers.length; i++)
          peers[i].saveAccount(_account(accountId: 'parallel-$i')),
      ]);

      expect((await store.read()).accounts, hasLength(peers.length));
    },
  );

  test(
    'close drains accepted work and immediately rejects later requests',
    () async {
      final pathReady = Completer<String>();
      final delayed = SqliteScheduleStore(databasePath: () => pathReady.future);
      stores.add(delayed);
      final saved = delayed.saveAccount(_account(), select: true);
      var closed = false;
      final closing = delayed.close().then((_) => closed = true);

      await expectLater(
        delayed.read(),
        throwsA(isA<ScheduleStorageException>()),
      );
      expect(closed, isFalse);
      pathReady.complete(databasePath);
      await saved;
      await closing;
      await delayed.close();

      expect((await openStore().read()).accounts, hasLength(1));
      expect(closed, isTrue);
    },
  );
}

AcademicTerm _term({
  String termCode = '3',
  String label = '2026–2027 学年第一学期',
}) => AcademicTerm(yearCode: '2026', termCode: termCode, label: label);

StoredScheduleAccount _account({
  String schoolId = 'school',
  String accountId = 'student',
  TermCatalog? catalog,
  Map<String, ScheduleSnapshot> schedules = const {},
  Map<String, ScheduleSettings> settings = const {},
  String? selectedTermKey,
}) => StoredScheduleAccount(
  account: AcademicAccountRecord(
    scope: AccountScope(schoolId: schoolId, accountId: accountId),
    schoolName: '测试大学',
    accountName: '测试同学',
    loginName: '20260001',
  ),
  catalog: catalog,
  schedules: schedules,
  settings: settings,
  selectedTermKey: selectedTermKey,
);

ScheduleSnapshot _snapshot(AcademicTerm term, {String name = '高等数学'}) =>
    ScheduleSnapshot(
      term: term,
      entries: [
        ScheduleEntry(
          id: 'school-math',
          name: name,
          teachingClassId: 'math-class-1',
          teacher: '测试教师',
          location: '教学楼 A101',
          weekday: DateTime.monday,
          startPeriod: 1,
          endPeriod: 2,
          weeks: const [1, 3, 5, 7, 9],
          rawWeeks: '1–10 周（单）',
        ),
      ],
      fetchedAt: DateTime.utc(2026, 9, 13, 4, 12, 35),
      calendar: TeachingCalendar(
        firstWeekMonday: DateTime(2026, 8, 31),
        totalWeeks: 20,
        source: TeachingCalendarSource.school,
        sourceLabel: '学校校历',
      ),
      periodTimes: [
        PeriodTime(number: 1, startMinutes: 8 * 60, endMinutes: 8 * 60 + 45),
      ],
      sourceLabel: '离线测试样本',
    );

ScheduleSettings _settings() => ScheduleSettings(
  calendarOverride: TeachingCalendar(
    firstWeekMonday: DateTime(2026, 9, 7),
    totalWeeks: 18,
    source: TeachingCalendarSource.user,
    sourceLabel: '用户校正',
  ),
  periodTimes: [
    PeriodTime(number: 1, startMinutes: 8 * 60 + 15, endMinutes: 9 * 60),
  ],
  localEntries: [
    ScheduleEntry(
      id: 'local-study',
      name: '自习',
      weekday: DateTime.wednesday,
      startPeriod: 3,
      endPeriod: 4,
      weeks: const [1, 2, 3],
      origin: ScheduleEntryOrigin.local,
    ),
  ],
  hiddenEntryIds: const ['school-math'],
);
