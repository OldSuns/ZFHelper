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
import '../platform/selection_runtime.dart';

typedef AppClock = DateTime Function();

final class AppConfiguration {
  AppConfiguration({
    required this.auth,
    required this.clock,
    required this.schedule,
    required this.grades,
    required this.courses,
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
