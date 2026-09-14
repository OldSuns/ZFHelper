import 'package:path_provider/path_provider.dart';
import 'package:zf_core/zf_core.dart';

import '../data/repositories/schedule_repository.dart';
import '../data/repositories/schedule_source.dart';
import '../data/repositories/grade_repository.dart';
import '../data/repositories/grade_source.dart';
import '../data/repositories/course_repository.dart';
import '../data/repositories/course_source.dart';
import '../data/services/dio_auth_transport.dart';
import '../data/storage/sqlite_schedule_store.dart';
import '../data/storage/sqlite_grade_store.dart';
import '../data/storage/sqlite_selection_store.dart';
import '../platform/secure_login_vault.dart';
import '../platform/secure_appearance_store.dart';
import '../platform/selection_runtime.dart';
import '../ui/features/settings/view_models/appearance_view_model.dart';

typedef AppClock = DateTime Function();

final class AppConfiguration {
  AppConfiguration({
    required this.auth,
    required this.clock,
    required this.schedule,
    required this.grades,
    required this.courses,
    required this.appearance,
  });

  factory AppConfiguration.standard() {
    final auth = AuthRepository(
      gatewayFactory: (profile) => ZhengfangLoginGateway(
        profile: profile,
        transport: DioAuthTransport(),
        cipher: const RsaPasswordCipher(),
        clock: DateTime.now,
      ),
      vault: SecureLoginVault(),
    );
    final selectionStore = SqliteSelectionStore(
      databasePath: () async {
        final directory = await getApplicationSupportDirectory();
        await directory.create(recursive: true);
        return directory.uri.resolve('zfhelper-selection.sqlite3').toFilePath();
      },
    );
    return AppConfiguration(
      appearance: AppearanceViewModel(store: SecureAppearanceStore()),
      auth: auth,
      clock: DateTime.now,
      courses: CourseRepository(
        store: selectionStore,
        operationStore: selectionStore,
        source: AuthenticatedCourseSource(auth: auth, clock: DateTime.now),
        runtime: createSelectionRuntime(),
        clock: DateTime.now,
      ),
      grades: GradeRepository(
        store: SqliteGradeStore(
          databasePath: () async {
            final directory = await getApplicationSupportDirectory();
            await directory.create(recursive: true);
            return directory.uri
                .resolve('zfhelper-grades.sqlite3')
                .toFilePath();
          },
        ),
        source: AuthenticatedGradeSource(auth: auth, clock: DateTime.now),
      ),
      schedule: ScheduleRepository(
        store: SqliteScheduleStore(
          databasePath: () async {
            final directory = await getApplicationSupportDirectory();
            await directory.create(recursive: true);
            return directory.uri
                .resolve('zfhelper-timetable.sqlite3')
                .toFilePath();
          },
        ),
        source: AuthenticatedScheduleSource(auth: auth, clock: DateTime.now),
      ),
    );
  }

  final AuthRepository auth;
  final AppClock clock;
  final ScheduleRepository schedule;
  final GradeRepository grades;
  final CourseRepository courses;
  final AppearanceViewModel appearance;

  Future<void> removeSchoolData(String schoolId) async {
    await Future.wait([
      courses.initialize(),
      schedule.initialize(),
      grades.initialize(),
    ]);
    if (!courses.state.initialized ||
        !schedule.state.initialized ||
        !grades.state.initialized) {
      throw const LoginFailure(
        LoginFailureCode.storage,
        '本地数据尚未完整读取，学校未移除。请先在对应页面重试读取数据，再移除学校。',
      );
    }
    final scopes = <AccountScope>{
      for (final account in auth.state.accounts) account.scope,
      for (final account in courses.state.library.accounts)
        account.account.scope,
      for (final account in schedule.state.library.accounts)
        account.account.scope,
      for (final account in grades.state.library.accounts)
        account.account.scope,
      for (final operation in courses.state.operations) operation.target.scope,
    }.where((scope) => scope.schoolId == schoolId).toList();
    for (final scope in scopes) {
      await removeAccountData(scope);
    }
  }

  Future<void> removeAccountData(AccountScope scope) async {
    // The account owner invalidates its session before reaching this callback.
    if (!await courses.removeAccount(scope)) {
      throw LoginFailure(
        LoginFailureCode.storage,
        courses.state.failure ?? '选课数据未能清除，请重试删除账号',
      );
    }
    if (!await schedule.removeAccount(scope)) {
      throw LoginFailure(
        LoginFailureCode.storage,
        schedule.state.failure?.message ?? '课表数据未能清除，请重试删除账号',
      );
    }
    if (!await grades.removeAccount(scope)) {
      throw LoginFailure(
        LoginFailureCode.storage,
        grades.state.failure?.message ?? '成绩数据未能清除，请重试删除账号',
      );
    }
  }
}
