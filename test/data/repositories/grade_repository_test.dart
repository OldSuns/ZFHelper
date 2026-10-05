import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zf_core/zf_core.dart';
import 'package:zfhelper/data/repositories/grade_repository.dart';
import 'package:zfhelper/data/storage/grade_store.dart';

import '../../support/grade_fakes.dart';

// Constructed records exercise cache behavior without a real school account.
void main() {
  test(
    'refresh retries failed initialization after dismissing its error',
    () async {
      final account = gradeAccount();
      final cached = gradeSnapshot();
      final store =
          TestGradeStore(
              library: GradeLibrary(
                accounts: [
                  StoredGradeAccount(account: account, snapshot: cached),
                ],
                selectedAccount: account.scope,
              ),
            )
            ..beforeWrite = (_) async =>
                throw const GradeStorageException('账号信息暂时无法保存');
      final source = TestGradeSource(account: account)
        ..onRead = () async => gradeSnapshot(records: []);
      final repository = testGradeRepository(store: store, source: source);
      addTearDown(repository.dispose);
      addTearDown(source.dispose);

      await repository.initialize();
      expect(repository.state.snapshot, same(cached));
      expect(repository.state.failure!.kind, GradeFailureKind.storage);
      repository.dismissFailure();
      expect(await repository.selectTerm(gradeTerm().key), isFalse);
      expect(repository.state.failure!.kind, GradeFailureKind.storage);
      store.beforeWrite = null;

      expect(await repository.refresh(), isTrue);
      expect(repository.state.failure, isNull);
      expect(repository.state.snapshot!.records, isEmpty);
      expect(store.reads, 3);
      expect(source.requests, 1);
    },
  );

  test('closing completes local writes that were already accepted', () async {
    final first = gradeAccount();
    final second = gradeAccount(id: 'second');
    final store = TestGradeStore(
      library: GradeLibrary(
        accounts: [
          StoredGradeAccount(account: first),
          StoredGradeAccount(account: second),
        ],
        selectedAccount: first.scope,
      ),
    );
    final source = TestGradeSource();
    final repository = testGradeRepository(store: store, source: source);
    await repository.initialize();
    final started = Completer<void>();
    final release = Completer<void>();
    store.beforeWrite = (_) async {
      if (started.isCompleted) return;
      started.complete();
      await release.future;
    };
    final firstSelection = repository.selectAccount(second.scope);
    await started.future;
    final secondSelection = repository.selectAccount(first.scope);
    await Future<void>.delayed(Duration.zero);
    final closing = repository.dispose();
    release.complete();
    expect(await firstSelection, isTrue);
    expect(await secondSelection, isTrue);
    await closing;
    await source.dispose();
    expect(store.library.selectedAccount, first.scope);
    expect(store.writes, 2);
  });

  test(
    'reloading local grades waits for accepted account selections',
    () async {
      final accounts = [
        gradeAccount(),
        gradeAccount(id: 'second'),
        gradeAccount(id: 'third'),
      ];
      final store = TestGradeStore(
        library: GradeLibrary(
          accounts: [
            for (final account in accounts)
              StoredGradeAccount(account: account),
          ],
          selectedAccount: accounts.first.scope,
        ),
      );
      final source = TestGradeSource();
      final repository = testGradeRepository(store: store, source: source);
      addTearDown(repository.dispose);
      addTearDown(source.dispose);
      await repository.initialize();
      final started = Completer<void>();
      final release = Completer<void>();
      store.beforeWrite = (_) async {
        if (started.isCompleted) return;
        started.complete();
        await release.future;
      };
      final firstSelection = repository.selectAccount(accounts[1].scope);
      await started.future;
      final lastSelection = repository.selectAccount(accounts.last.scope);
      await Future<void>.delayed(Duration.zero);
      final reloading = repository.retryLocalLoad();
      await Future<void>.delayed(Duration.zero);
      expect(store.reads, 1);
      release.complete();
      expect(await firstSelection, isTrue);
      expect(await lastSelection, isTrue);
      await reloading;
      expect(repository.state.account!.account.scope, accounts.last.scope);
      expect(store.library.selectedAccount, accounts.last.scope);
      expect(store.reads, 2);
    },
  );

  test(
    'successful grades and term selection survive an offline reopening',
    () async {
      final account = gradeAccount();
      final source = TestGradeSource(account: account)
        ..onRead = () async => gradeSnapshot();
      final store = TestGradeStore();
      final repository = testGradeRepository(store: store, source: source);
      await repository.initialize();
      expect(source.requests, 0);
      expect(await repository.refresh(), isTrue);
      expect(await repository.selectTerm(gradeTerm().key), isTrue);
      final saved = store.library;
      await repository.dispose();
      await source.dispose();

      final offline = TestGradeSource();
      final restored = testGradeRepository(
        store: TestGradeStore(library: saved),
        source: offline,
      );
      addTearDown(restored.dispose);
      addTearDown(offline.dispose);
      await restored.initialize();
      expect(restored.state.snapshot!.records.single.score, '85');
      expect(restored.state.snapshot!.fetchedAt, DateTime.utc(2026, 9, 14));
      expect(restored.state.account!.selectedTermKey, 'grade-term|2025|3');
      expect(offline.requests, 0);
      expect(restored.canRefresh(account.scope), isFalse);
    },
  );

  test(
    'network and parse failures keep the last complete snapshot and timestamp',
    () async {
      final source = TestGradeSource(account: gradeAccount())
        ..onRead = () async => gradeSnapshot();
      final repository = testGradeRepository(source: source);
      addTearDown(repository.dispose);
      addTearDown(source.dispose);
      await repository.refresh();
      final original = repository.state.snapshot;
      source.onRead = () async =>
          throw const LoginFailure(LoginFailureCode.network, '网络不可用');
      expect(await repository.refresh(), isFalse);
      expect(repository.state.snapshot, same(original));
      expect(repository.state.failure!.kind, GradeFailureKind.network);
      source.onRead = () async =>
          throw const FormatException('Changed response');
      expect(await repository.refresh(), isFalse);
      expect(repository.state.snapshot, same(original));
      expect(repository.state.failure!.kind, GradeFailureKind.protocol);
      source.onRead = () async =>
          gradeSnapshot(records: [], fetchedAt: DateTime.utc(2026, 9, 15));
      expect(await repository.refresh(), isTrue);
      expect(repository.state.snapshot!.records, isEmpty);
      expect(repository.state.snapshot!.fetchedAt, DateTime.utc(2026, 9, 15));
    },
  );

  test(
    'failed persistence does not publish new grades and allows explicit retry',
    () async {
      final store = TestGradeStore();
      final source = TestGradeSource(account: gradeAccount())
        ..onRead = () async => gradeSnapshot();
      final repository = testGradeRepository(source: source, store: store);
      addTearDown(repository.dispose);
      addTearDown(source.dispose);
      await repository.refresh();
      final original = repository.state.snapshot;
      store.failure = const GradeStorageException('磁盘不可写');
      source.onRead = () async => gradeSnapshot(records: []);
      expect(await repository.refresh(), isFalse);
      expect(repository.state.snapshot, same(original));
      expect(store.library.accounts.single.snapshot, same(original));
      expect(repository.state.failure!.kind, GradeFailureKind.storage);
      store.failure = null;
      expect(await repository.refresh(), isTrue);
      expect(repository.state.snapshot!.records, isEmpty);
    },
  );

  test(
    'switching schools with the same account ID rejects a late response',
    () async {
      final first = gradeAccount();
      final second = gradeAccount(school: 'https://other.example/jwglxt/');
      final pending = Completer<GradeSnapshot>();
      final started = Completer<void>();
      final source = TestGradeSource(account: first)
        ..onRead = () {
          started.complete();
          return pending.future;
        };
      final store = TestGradeStore();
      final repository = testGradeRepository(source: source, store: store);
      addTearDown(repository.dispose);
      addTearDown(source.dispose);
      final request = repository.refresh();
      await started.future;
      final changed = repository.changes.firstWhere(
        (state) => state.account?.account.scope == second.scope,
      );
      source.connect(second);
      await changed;
      pending.complete(gradeSnapshot());
      expect(await request, isFalse);
      expect(repository.state.account!.account.scope, second.scope);
      expect(
        store.library.accounts.every((account) => account.snapshot == null),
        isTrue,
      );
    },
  );

  test(
    'clearing grades while reading cannot resurrect the removed snapshot',
    () async {
      final pending = Completer<GradeSnapshot>();
      final started = Completer<void>();
      final source = TestGradeSource(account: gradeAccount())
        ..onRead = () async => gradeSnapshot();
      final repository = testGradeRepository(source: source);
      addTearDown(repository.dispose);
      addTearDown(source.dispose);
      await repository.refresh();
      source.onRead = () {
        started.complete();
        return pending.future;
      };
      final request = repository.refresh();
      await started.future;
      expect(await repository.clearCurrentCache(), isTrue);
      pending.complete(gradeSnapshot());
      expect(await request, isFalse);
      expect(repository.state.snapshot, isNull);
    },
  );

  test(
    'restoring an identity preserves a different account selected offline',
    () async {
      final connected = gradeAccount();
      final selected = gradeAccount(id: 'offline');
      final source = TestGradeSource(account: connected);
      final repository = testGradeRepository(
        source: source,
        store: TestGradeStore(
          library: GradeLibrary(
            accounts: [
              StoredGradeAccount(account: selected, snapshot: gradeSnapshot()),
            ],
            selectedAccount: selected.scope,
          ),
        ),
      );
      addTearDown(repository.dispose);
      addTearDown(source.dispose);
      await repository.initialize();
      expect(repository.state.account!.account.scope, selected.scope);
      expect(source.requests, 0);
    },
  );
}
