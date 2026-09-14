import 'dart:async';

import 'package:zf_core/zf_core.dart';
import 'package:zfhelper/data/repositories/schedule_repository.dart';
import 'package:zfhelper/data/repositories/schedule_source.dart';
import 'package:zfhelper/data/storage/schedule_store.dart';

final class TestScheduleStore implements ScheduleStore {
  TestScheduleStore({ScheduleLibrary? library})
    : library = library ?? ScheduleLibrary();

  ScheduleLibrary library;
  ScheduleStorageException? failure;
  int reads = 0;
  int writes = 0;
  bool closed = false;

  void _check() {
    if (closed) throw StateError('Test store is closed.');
    if (failure case final error?) throw error;
  }

  @override
  Future<ScheduleLibrary> read() async {
    _check();
    reads++;
    return library;
  }

  @override
  Future<void> saveAccount(
    StoredScheduleAccount account, {
    bool select = false,
  }) async {
    _check();
    writes++;
    library = ScheduleLibrary(
      accounts: [
        account,
        ...library.accounts.where(
          (item) => item.account.scope != account.account.scope,
        ),
      ],
      selectedAccount: select ? account.account.scope : library.selectedAccount,
    );
  }

  @override
  Future<void> selectAccount(AccountScope scope) async {
    _check();
    if (!library.accounts.any((account) => account.account.scope == scope)) {
      throw StateError('Unknown test account.');
    }
    library = ScheduleLibrary(
      accounts: library.accounts,
      selectedAccount: scope,
    );
  }

  @override
  Future<void> removeAccount(AccountScope scope) async {
    _check();
    final remaining = library.accounts
        .where((item) => item.account.scope != scope)
        .toList();
    library = ScheduleLibrary(
      accounts: remaining,
      selectedAccount: library.selectedAccount == scope
          ? remaining.firstOrNull?.account.scope
          : library.selectedAccount,
    );
  }

  @override
  Future<void> close() async => closed = true;
}

final class TestScheduleSource implements ScheduleSource {
  TestScheduleSource({this._account});

  final _changes = StreamController<ScheduleAccountChange>.broadcast(
    sync: true,
  );
  ScheduleAccountRecord? _account;
  int generation = 0;
  int requests = 0;
  Future<ScheduleImportResult> Function(AcademicTerm? term)? onRead;

  void connect(ScheduleAccountRecord? account, {bool selectForViewing = true}) {
    _account = account;
    generation++;
    _changes.add(
      ScheduleAccountChange(account, selectForViewing: selectForViewing),
    );
  }

  @override
  ScheduleAccountRecord? get connectedAccount => _account;
  @override
  Stream<ScheduleAccountChange> get accountChanges => _changes.stream;

  @override
  ScheduleReadSession open(AccountScope scope) {
    if (_account?.scope != scope) {
      throw const LoginFailure(LoginFailureCode.expired, '请登录课表所属账号');
    }
    return _TestScheduleRead(this, scope, generation);
  }

  Future<void> dispose() => _changes.close();
}

final class _TestScheduleRead implements ScheduleReadSession {
  _TestScheduleRead(this.source, this.scope, this.generation);
  final TestScheduleSource source;
  final AccountScope scope;
  final int generation;
  @override
  bool get isCurrent =>
      source.generation == generation &&
      source.connectedAccount?.scope == scope;
  @override
  Future<ScheduleImportResult> read({AcademicTerm? term}) {
    source.requests++;
    return source.onRead?.call(term) ??
        (throw StateError('Unexpected schedule network request.'));
  }
}

ScheduleRepository testScheduleRepository({
  TestScheduleStore? store,
  TestScheduleSource? source,
}) => ScheduleRepository(
  store: store ?? TestScheduleStore(),
  source: source ?? TestScheduleSource(),
);

// Synthetic records model the documented new-Zhengfang response fields.
// No record below comes from a student's real account or an online request.
const scheduleTestAccount = ScheduleAccountRecord(
  scope: AccountScope(
    schoolId: 'https://jw.example.test/jwglxt/',
    accountId: 'student-a',
  ),
  schoolName: '示例大学',
  accountName: '测试同学',
  loginName: 'student-a',
);
final scheduleTestTerm = AcademicTerm(
  yearCode: '2026',
  termCode: '3',
  label: '2026–2027学年 第一学期',
);

ScheduleSnapshot scheduleTestSnapshot({
  AcademicTerm? term,
  DateTime? fetchedAt,
  List<ScheduleEntry>? entries,
}) => ScheduleSnapshot(
  term: term ?? scheduleTestTerm,
  fetchedAt: fetchedAt ?? DateTime(2026, 9, 12, 12),
  calendar: TeachingCalendar(
    firstWeekMonday: DateTime(2026, 9, 7),
    totalWeeks: 20,
    source: TeachingCalendarSource.school,
    sourceLabel: '合成校历测试',
  ),
  entries:
      entries ??
      [
        ScheduleEntry(
          id: 'test-math',
          teachingClassId: 'class-math',
          name: '高等数学',
          teacher: '测试教师',
          location: '教学楼101',
          weekday: 1,
          startPeriod: 1,
          endPeriod: 2,
          weeks: List.generate(16, (index) => index + 1),
          rawWeeks: '1-16周',
        ),
      ],
  periodTimes: [
    PeriodTime(number: 1, startMinutes: 8 * 60, endMinutes: 8 * 60 + 45),
    PeriodTime(number: 2, startMinutes: 8 * 60 + 55, endMinutes: 9 * 60 + 40),
  ],
);

StoredScheduleAccount scheduleTestSaved({
  ScheduleSnapshot? snapshot,
  ScheduleSettings? settings,
}) {
  final value = snapshot ?? scheduleTestSnapshot();
  return StoredScheduleAccount(
    account: scheduleTestAccount,
    catalog: TermCatalog(terms: [value.term], selectedTerm: value.term),
    schedules: {value.term.key: value},
    settings: settings == null ? const {} : {value.term.key: settings},
    selectedTermKey: value.term.key,
  );
}
