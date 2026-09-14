/// Shared calendar values and authentication logic without a Flutter dependency.
library;

export 'src/calendar_week.dart';
export 'src/school_identity.dart';
export 'src/auth/login_gateway.dart';
export 'src/auth/login_models.dart';
export 'src/auth/school_connection.dart';
export 'src/auth/school_connection_codec.dart';
export 'src/auth/school_address.dart' show recognizeSchoolAddress;
export 'src/auth/auth_repository.dart';
export 'src/auth/stored_login_codec.dart';
export 'src/auth/cookie_header_parser.dart';
export 'src/auth/rsa_password_cipher.dart';
export 'src/auth/zhengfang_login_gateway.dart';
export 'src/auth/account_scope.dart';
export 'src/auth/authenticated_read_client.dart';
export 'src/academic/zhengfang_schedule_gateway.dart';
export 'src/academic/zhengfang_grade_gateway.dart';
export 'src/grades/grade_record.dart';
export 'src/grades/grade_snapshot.dart';
export 'src/grades/grade_codec.dart';
export 'src/grades/grade_parse_exception.dart';
export 'src/grades/grade_summary.dart';
export 'src/grades/grade_term_group.dart'
    show GradeTermGroup, unassignedGradeTermKey;
export 'src/schedule/academic_term.dart';
export 'src/schedule/teaching_calendar.dart';
export 'src/schedule/schedule_entry.dart';
export 'src/schedule/schedule_snapshot.dart';
export 'src/schedule/schedule_settings.dart';
export 'src/schedule/schedule_notation_parser.dart';
export 'src/schedule/schedule_parse_exception.dart';
export 'src/schedule/zhengfang_schedule_parser.dart';
export 'src/schedule/schedule_codec.dart';
