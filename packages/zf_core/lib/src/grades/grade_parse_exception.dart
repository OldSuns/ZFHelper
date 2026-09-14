enum GradeParseCode {
  invalidResponse,
  missingField,
  invalidValue,
  schoolRejected,
  incompleteResponse,
  identityMismatch,
}

/// A grade protocol error without a raw payload or account identifier.
final class GradeParseException extends FormatException {
  const GradeParseException(
    this.code,
    String message, {
    this.field,
    this.recordIndex,
  }) : super(message);

  final GradeParseCode code;
  final String? field;
  final int? recordIndex;

  @override
  String toString() =>
      'GradeParseException(${code.name}'
      '${field == null ? '' : ', $field'}'
      '${recordIndex == null ? '' : ', row $recordIndex'}): $message';
}
