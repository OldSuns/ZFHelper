/// A stable school and account key for business data and requests.
final class AccountScope {
  const AccountScope({required this.schoolId, required this.accountId});

  final String schoolId;
  final String accountId;

  @override
  bool operator ==(Object other) =>
      other is AccountScope &&
      other.schoolId == schoolId &&
      other.accountId == accountId;

  @override
  int get hashCode => Object.hash(schoolId, accountId);
}
