import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:zfhelper/data/storage/grade_store.dart';
import 'package:zfhelper/data/storage/sqlite_grade_store.dart';

import '../../support/grade_fakes.dart';

void main() {
  late Directory directory;
  late String path;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('zfhelper-grade-store-');
    path = '${directory.path}${Platform.pathSeparator}grades.sqlite3';
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'reopening preserves school/account isolation, term and fetch time',
    () async {
      final first = gradeAccount(id: "student'one");
      final second = gradeAccount(
        school: 'https://other.example/',
        id: "student'one",
      );
      final store = SqliteGradeStore(databasePath: () async => path);
      await store.write(
        GradeLibrary(
          accounts: [
            StoredGradeAccount(
              account: first,
              snapshot: gradeSnapshot(),
              selectedTermKey: gradeTerm().key,
            ),
            StoredGradeAccount(
              account: second,
              snapshot: gradeSnapshot(records: []),
            ),
          ],
          selectedAccount: first.scope,
        ),
      );
      await store.close();
      final reopened = SqliteGradeStore(databasePath: () async => path);
      try {
        final restored = await reopened.read();
        expect(restored.selectedAccount, first.scope);
        expect(restored.accounts.first.selectedTermKey, 'grade-term|2025|3');
        expect(restored.accounts.first.snapshot!.records.single.score, '85');
        expect(
          restored.accounts.first.snapshot!.fetchedAt,
          gradeSnapshot().fetchedAt,
        );
        expect(restored.accounts.last.snapshot!.records, isEmpty);
        await expectLater(
          reopened.write(GradeLibrary(selectedAccount: first.scope)),
          throwsA(isA<GradeStorageException>()),
        );
        expect((await reopened.read()).accounts.length, 2);
      } finally {
        await reopened.close();
      }
    },
  );

  test(
    'a corrupt payload remains on disk instead of becoming an empty success',
    () async {
      final store = SqliteGradeStore(databasePath: () async => path);
      await store.write(GradeLibrary());
      await store.close();
      final database = sqlite3.open(path);
      database.execute('UPDATE grade_library SET payload = ? WHERE id = 1', [
        '{broken',
      ]);
      database.close();
      final reopened = SqliteGradeStore(databasePath: () async => path);
      await expectLater(reopened.read(), throwsA(isA<GradeStorageException>()));
      await reopened.close();
      final preserved = sqlite3.open(path);
      try {
        expect(
          preserved
              .select('SELECT payload FROM grade_library')
              .single['payload'],
          '{broken',
        );
      } finally {
        preserved.close();
      }
    },
  );
}
