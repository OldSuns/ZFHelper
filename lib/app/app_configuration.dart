import 'package:path_provider/path_provider.dart';
import 'package:zf_core/zf_core.dart';

import '../data/repositories/schedule_repository.dart';
import '../data/repositories/schedule_source.dart';
import '../data/repositories/grade_repository.dart';
import '../data/repositories/grade_source.dart';
import '../data/services/dio_auth_transport.dart';
import '../data/storage/sqlite_schedule_store.dart';
import '../data/storage/sqlite_grade_store.dart';
import '../platform/secure_login_vault.dart';

typedef AppClock = DateTime Function();

final class AppConfiguration {
  AppConfiguration({
    required this.auth,
    required this.clock,
    required this.schedule,
    required this.grades,
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
    return AppConfiguration(
      auth: auth,
      clock: DateTime.now,
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
}
