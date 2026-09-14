enum ScheduleParseCode {
  invalidResponse,
  missingField,
  invalidValue,
  unsupported,
  schoolRejected,
}

/// A protocol diagnostic containing field locations but no raw server payload.
final class ScheduleParseException extends FormatException {
  const ScheduleParseException(
    this.code,
    String message, {
    this.field,
    this.recordIndex,
  }) : super(message);

  final ScheduleParseCode code;
  final String? field;
  final int? recordIndex;

  @override
  String toString() =>
      'ScheduleParseException(${code.name}'
      '${field == null ? '' : ', $field'}'
      '${recordIndex == null ? '' : ', row $recordIndex'}): $message';
}
