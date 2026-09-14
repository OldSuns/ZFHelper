import 'package:zf_core/zf_core.dart';

/// Account labels saved with academic data, without credentials or cookies.
final class AcademicAccountRecord {
  const AcademicAccountRecord({
    required this.scope,
    required this.schoolName,
    required this.accountName,
    required this.loginName,
  });

  final AccountScope scope;
  final String schoolName;
  final String accountName;
  final String loginName;
}
