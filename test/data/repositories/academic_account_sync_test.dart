import 'package:flutter_test/flutter_test.dart';
import 'package:zf_core/zf_core.dart';
import 'package:zfhelper/app/app_configuration.dart';
import 'package:zfhelper/data/repositories/course_source.dart';
import 'package:zfhelper/data/repositories/grade_repository.dart';
import 'package:zfhelper/data/repositories/grade_source.dart';
import 'package:zfhelper/data/repositories/schedule_repository.dart';
import 'package:zfhelper/data/repositories/schedule_source.dart';
import 'package:zfhelper/data/storage/schedule_store.dart';

import '../../support/auth_fakes.dart';
import '../../support/course_fakes.dart';
import '../../support/grade_fakes.dart';
import '../../support/schedule_fakes.dart';
import '../../support/settings_fakes.dart';

void main() {
  test(
    'offline identity selection, school edits and removal reach every cache',
    () async {
      final otherSchool = SchoolConnection.create(
        name: '另一所学校',
        baseUri: Uri.parse('https://other.example/jwglxt/'),
      );
      final accounts = [
        StoredAuthAccount(profile: testProfile, account: testSession().account),
        StoredAuthAccount(
          profile: testProfile,
          account: testSession(id: 'second').account,
        ),
        StoredAuthAccount(profile: otherSchool, account: testSession().account),
      ];
      final auth = testAuth(
        vault: TestLoginVault()
          ..library = StoredLoginLibrary(
            accounts: accounts,
            selectedScope: accounts.first.scope,
          ),
      );
      final scheduleStore = TestScheduleStore();
      final schedule = ScheduleRepository(
        store: scheduleStore,
        source: AuthenticatedScheduleSource(auth: auth, clock: DateTime.now),
      );
      final grades = GradeRepository(
        store: TestGradeStore(),
        source: AuthenticatedGradeSource(auth: auth, clock: DateTime.now),
      );
      final courses = testCourseRepository(
        source: AuthenticatedCourseSource(auth: auth, clock: DateTime.now),
      );
      final app = AppConfiguration(
        appearance: testAppearance(),
        auth: auth,
        schedule: schedule,
        grades: grades,
        courses: courses,
        clock: DateTime.now,
      );
      addTearDown(auth.dispose);
      addTearDown(schedule.dispose);
      addTearDown(grades.dispose);
      addTearDown(courses.dispose);
      addTearDown(app.appearance.dispose);
      await auth.restore();
      await Future.wait([
        schedule.initialize(),
        grades.initialize(),
        courses.initialize(),
      ]);

      Future<void> select(
        Future<bool> Function() change,
        AccountScope? scope,
      ) async {
        final synced = Future.wait([
          schedule.changes.firstWhere(
            (state) => state.library.selectedAccount == scope,
          ),
          grades.changes.firstWhere(
            (state) => state.library.selectedAccount == scope,
          ),
          courses.changes.firstWhere(
            (state) => state.library.selectedAccount == scope,
          ),
        ]);
        expect(await change(), isTrue);
        await synced;
      }

      scheduleStore.failure = const ScheduleStorageException(
        operation: 'saveAccount',
        message: 'synthetic write failure',
      );
      final failedSelection = schedule.changes.firstWhere(
        (s) => s.failure != null,
      );
      await auth.selectAccount(accounts[1].scope);
      await failedSelection;
      expect(schedule.state.library.selectedAccount, accounts.first.scope);
      scheduleStore.failure = null;
      await schedule.retryLocalLoad();
      expect(schedule.state.library.selectedAccount, accounts[1].scope);

      for (final account in accounts.skip(2)) {
        await select(() => auth.selectAccount(account.scope), account.scope);
        expect(schedule.canRefresh(account.scope), isFalse);
        expect(grades.canRefresh(account.scope), isFalse);
        expect(courses.canQuery(account.scope), isFalse);
      }
      await select(
        () => auth.selectSchool(testProfile.school.id),
        accounts[1].scope,
      );
      final renamed = SchoolConnection(
        schoolId: testProfile.school.id,
        name: '新学校名称',
        baseUri: testProfile.baseUri,
      );
      final renamedCaches = Future.wait([
        schedule.changes.firstWhere(
          (s) => s.library.accounts
              .where((a) => a.account.scope.schoolId == testProfile.school.id)
              .every((a) => a.account.schoolName == renamed.name),
        ),
        grades.changes.firstWhere(
          (s) => s.library.accounts
              .where((a) => a.account.scope.schoolId == testProfile.school.id)
              .every((a) => a.account.schoolName == renamed.name),
        ),
        courses.changes.firstWhere(
          (s) => s.library.accounts
              .where((a) => a.account.scope.schoolId == testProfile.school.id)
              .every((a) => a.account.schoolName == renamed.name),
        ),
      ]);
      await auth.configureSchool(renamed);
      await renamedCaches;
      await auth.signOutSchool(testProfile.school.id);
      await app.removeSchoolData(testProfile.school.id);
      await select(
        () => auth.removeSchool(testProfile.school.id),
        accounts.last.scope,
      );
      expect(
        schedule.state.library.accounts.single.account.scope,
        accounts.last.scope,
      );
      expect(
        grades.state.library.accounts.single.account.scope,
        accounts.last.scope,
      );
      expect(
        courses.state.library.accounts.single.account.scope,
        accounts.last.scope,
      );
      expect(auth.state.accounts.single.scope, accounts.last.scope);

      final emptySchool = SchoolConnection.create(
        name: '未登录的学校',
        baseUri: Uri.parse('https://empty.example/'),
      );
      await select(() async {
        await auth.configureSchool(emptySchool);
        return true;
      }, null);
      expect(schedule.state.library.accounts, hasLength(1));
      expect(grades.state.library.accounts, hasLength(1));
      expect(courses.state.library.accounts, hasLength(1));
    },
  );
}
