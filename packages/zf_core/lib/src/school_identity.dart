/// A school's application identifier and display name.
///
/// Login addresses and protocol details belong to a verified school adapter.
final class SchoolIdentity {
  const SchoolIdentity({required this.id, required this.name});

  final String id;
  final String name;
}
