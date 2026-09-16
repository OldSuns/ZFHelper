import 'dart:convert';

enum ScheduleEventCategory { todo, activity, exam, homework, other }

enum ScheduleEventPhase { upcoming, ongoing, finished }

/// A local account's dated event, independent of imported academic terms.
final class ScheduleEvent {
  ScheduleEvent({
    required this.id,
    required this.title,
    required DateTime date,
    required this.category,
    this.startMinutes,
    this.endMinutes,
    this.location,
    this.note,
    this.completed = false,
  }) : date = DateTime(date.year, date.month, date.day) {
    if (id.trim().isEmpty || title.trim().isEmpty) {
      throw ArgumentError('An event needs an identity and title.');
    }
    if (date.year < 1 || date.year > 9999) {
      throw ArgumentError('An event needs a supported civil date.');
    }
    if ((startMinutes == null) != (endMinutes == null) ||
        (startMinutes != null &&
            (startMinutes! < 0 ||
                endMinutes! > minutesPerDay ||
                startMinutes! >= endMinutes!))) {
      throw ArgumentError('An event needs a valid paired time range.');
    }
    if (completed && !canComplete) {
      throw ArgumentError('Only tasks and homework can be completed.');
    }
  }

  static const minutesPerDay = 24 * 60;

  final String id;
  final String title;
  final DateTime date;
  final ScheduleEventCategory category;
  final int? startMinutes;
  final int? endMinutes;
  final String? location;
  final String? note;
  final bool completed;

  bool get isAllDay => startMinutes == null;
  bool get canComplete =>
      category == ScheduleEventCategory.todo ||
      category == ScheduleEventCategory.homework;

  DateTime get startsAt =>
      DateTime(date.year, date.month, date.day, 0, startMinutes ?? 0);
  DateTime get endsAt =>
      DateTime(date.year, date.month, date.day, 0, endMinutes ?? minutesPerDay);

  /// Clock progress is independent of whether a task has been checked off.
  ScheduleEventPhase phaseAt(DateTime now) => now.isBefore(startsAt)
      ? ScheduleEventPhase.upcoming
      : now.isBefore(endsAt)
      ? ScheduleEventPhase.ongoing
      : ScheduleEventPhase.finished;

  ScheduleEvent copyWith({
    String? id,
    String? title,
    DateTime? date,
    ScheduleEventCategory? category,
    int? startMinutes,
    int? endMinutes,
    bool clearTime = false,
    String? location,
    bool clearLocation = false,
    String? note,
    bool clearNote = false,
    bool? completed,
  }) => ScheduleEvent(
    id: id ?? this.id,
    title: title ?? this.title,
    date: date ?? this.date,
    category: category ?? this.category,
    startMinutes: clearTime ? null : startMinutes ?? this.startMinutes,
    endMinutes: clearTime ? null : endMinutes ?? this.endMinutes,
    location: clearLocation ? null : location ?? this.location,
    note: clearNote ? null : note ?? this.note,
    completed: completed ?? this.completed,
  );

  @override
  bool operator ==(Object other) =>
      other is ScheduleEvent &&
      id == other.id &&
      title == other.title &&
      date == other.date &&
      category == other.category &&
      startMinutes == other.startMinutes &&
      endMinutes == other.endMinutes &&
      location == other.location &&
      note == other.note &&
      completed == other.completed;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    date,
    category,
    startMinutes,
    endMinutes,
    location,
    note,
    completed,
  );
}

/// Versioned persistence that keeps civil dates independent of time zones.
abstract final class ScheduleEventCodec {
  static const _version = 1;

  static String encode(ScheduleEvent event) => jsonEncode({
    'version': _version,
    'kind': 'scheduleEvent',
    'id': event.id,
    'title': event.title,
    'date':
        '${event.date.year.toString().padLeft(4, '0')}-'
        '${event.date.month.toString().padLeft(2, '0')}-'
        '${event.date.day.toString().padLeft(2, '0')}',
    'category': event.category.name,
    'startMinutes': event.startMinutes,
    'endMinutes': event.endMinutes,
    'location': event.location,
    'note': event.note,
    'completed': event.completed,
  });

  static ScheduleEvent decode(String source) {
    try {
      final data = jsonDecode(source);
      if (data is! Map<String, Object?> ||
          data['version'] is! int ||
          data['version'] != _version ||
          data['kind'] != 'scheduleEvent' ||
          data['completed'] is! bool) {
        _invalid();
      }
      final category = ScheduleEventCategory.values
          .where((value) => value.name == data['category'])
          .firstOrNull;
      if (category == null) _invalid();
      return ScheduleEvent(
        id: _string(data, 'id'),
        title: _string(data, 'title'),
        date: _date(_string(data, 'date')),
        category: category,
        startMinutes: _optionalInteger(data, 'startMinutes'),
        endMinutes: _optionalInteger(data, 'endMinutes'),
        location: _optionalString(data, 'location'),
        note: _optionalString(data, 'note'),
        completed: data['completed'] as bool,
      );
    } on FormatException {
      // JSON errors may carry private event text in their source.
      _invalid();
    } on ArgumentError {
      _invalid();
    }
  }

  static DateTime _date(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) _invalid();
    final year = int.parse(value.substring(0, 4));
    final month = int.parse(value.substring(5, 7));
    final day = int.parse(value.substring(8, 10));
    final result = DateTime(year, month, day);
    if (year < 1 ||
        result.year != year ||
        result.month != month ||
        result.day != day) {
      _invalid();
    }
    return result;
  }

  static String _string(Map<String, Object?> data, String key) {
    final value = data[key];
    if (value is! String || value.trim().isEmpty) _invalid();
    return value;
  }

  static String? _optionalString(Map<String, Object?> data, String key) {
    if (!data.containsKey(key)) _invalid();
    final value = data[key];
    if (value != null && value is! String) _invalid();
    return value as String?;
  }

  static int? _optionalInteger(Map<String, Object?> data, String key) {
    if (!data.containsKey(key)) _invalid();
    final value = data[key];
    if (value != null && value is! int) _invalid();
    return value as int?;
  }

  static Never _invalid() =>
      throw const FormatException('Invalid saved schedule event.');
}
