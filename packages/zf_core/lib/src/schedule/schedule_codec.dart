import 'dart:convert';

import 'academic_term.dart';
import 'schedule_entry.dart';
import 'schedule_settings.dart';
import 'schedule_snapshot.dart';
import 'teaching_calendar.dart';

/// Versioned persistence for successful timetable imports.
abstract final class ScheduleSnapshotCodec {
  static String encode(ScheduleSnapshot snapshot) => jsonEncode({
    'version': _version,
    'kind': 'scheduleSnapshot',
    'term': _writeTerm(snapshot.term),
    'entries': snapshot.entries.map(_writeEntry).toList(),
    'fetchedAt': snapshot.fetchedAt.toUtc().toIso8601String(),
    'calendar': _writeCalendar(snapshot.calendar),
    'periodTimes': snapshot.periodTimes.map(_writePeriod).toList(),
    'sourceLabel': snapshot.sourceLabel,
    'importWarnings': snapshot.importWarnings,
  });

  /// Restores a snapshot or throws [FormatException] for invalid saved data.
  static ScheduleSnapshot decode(String source) => _decode(source, (data) {
    _kind(data, 'scheduleSnapshot');
    return ScheduleSnapshot(
      term: _readTerm(data['term']),
      entries: _list(data, 'entries').map(_readEntry).toList(),
      fetchedAt: _timestamp(_string(data, 'fetchedAt')),
      calendar: _readCalendar(data['calendar']),
      periodTimes: _list(data, 'periodTimes').map(_readPeriod).toList(),
      sourceLabel: _optionalString(data, 'sourceLabel'),
      importWarnings: data.containsKey('importWarnings')
          ? _list(data, 'importWarnings').map((value) {
              if (value is! String) _invalid('importWarnings');
              return value;
            }).toList()
          : const [],
    );
  });
}

/// Versioned persistence for user changes independent of imported courses.
abstract final class ScheduleSettingsCodec {
  static String encode(ScheduleSettings settings) => jsonEncode({
    'version': _version,
    'kind': 'scheduleSettings',
    'calendarOverride': settings.calendarOverride == null
        ? null
        : _writeCalendar(settings.calendarOverride!),
    'periodTimes': settings.periodTimes.map(_writePeriod).toList(),
    'useCustomPeriodTimes': settings.useCustomPeriodTimes,
    'localEntries': settings.localEntries.map(_writeEntry).toList(),
    'hiddenEntryIds': settings.hiddenEntryIds.toList()..sort(),
    'preferAgenda': settings.preferAgenda,
  });

  static ScheduleSettings decode(String source) => _decode(source, (data) {
    _kind(data, 'scheduleSettings');
    return ScheduleSettings(
      calendarOverride: data['calendarOverride'] == null
          ? null
          : _readCalendar(data['calendarOverride']),
      periodTimes: _list(data, 'periodTimes').map(_readPeriod).toList(),
      useCustomPeriodTimes: _boolean(data, 'useCustomPeriodTimes'),
      // Older version-1 settings predate the saved view preference.
      preferAgenda: data.containsKey('preferAgenda')
          ? _boolean(data, 'preferAgenda')
          : false,
      localEntries: _list(data, 'localEntries').map(_readEntry).toList(),
      hiddenEntryIds: _list(data, 'hiddenEntryIds').map((value) {
        if (value is! String || value.trim().isEmpty) {
          _invalid('hiddenEntryIds');
        }
        return value;
      }),
    );
  });
}

/// Versioned persistence for school selector options and known term pairs.
abstract final class TermCatalogCodec {
  static String encode(TermCatalog catalog) => jsonEncode({
    'version': _version,
    'kind': 'termCatalog',
    'terms': catalog.terms.map(_writeTerm).toList(),
    'selectedTerm': catalog.selectedTerm == null
        ? null
        : _writeTerm(catalog.selectedTerm!),
    'yearOptions': catalog.yearOptions.map(_writeOption).toList(),
    'termOptions': catalog.termOptions.map(_writeOption).toList(),
  });

  static TermCatalog decode(String source) => _decode(source, (data) {
    _kind(data, 'termCatalog');
    return TermCatalog(
      terms: _list(data, 'terms').map(_readTerm).toList(),
      selectedTerm: data['selectedTerm'] == null
          ? null
          : _readTerm(data['selectedTerm']),
      yearOptions: _list(data, 'yearOptions').map(_readOption).toList(),
      termOptions: _list(data, 'termOptions').map(_readOption).toList(),
    );
  });
}

const _version = 1;

Map<String, Object?> _writeTerm(AcademicTerm term) => {
  'yearCode': term.yearCode,
  'termCode': term.termCode,
  'label': term.label,
};

AcademicTerm _readTerm(Object? value) {
  final data = _map(value);
  return AcademicTerm(
    yearCode: _string(data, 'yearCode'),
    termCode: _string(data, 'termCode'),
    label: _string(data, 'label'),
  );
}

Map<String, Object?> _writeOption(TermOption option) => {
  'code': option.code,
  'label': option.label,
};

TermOption _readOption(Object? value) {
  final data = _map(value);
  return TermOption(code: _string(data, 'code'), label: _string(data, 'label'));
}

Map<String, Object?> _writeEntry(ScheduleEntry entry) => {
  'id': entry.id,
  'teachingClassId': entry.teachingClassId,
  'courseCode': entry.courseCode,
  'name': entry.name,
  'teacher': entry.teacher,
  'location': entry.location,
  'campus': entry.campus,
  'weekday': entry.weekday,
  'startPeriod': entry.startPeriod,
  'endPeriod': entry.endPeriod,
  'weeks': entry.weeks.toList(),
  'rawWeeks': entry.rawWeeks,
  'metadata': entry.metadata,
  'origin': entry.origin.name,
  'kind': entry.kind.name,
};

ScheduleEntry _readEntry(Object? value) {
  final data = _map(value);
  final metadata = _map(data['metadata']);
  return ScheduleEntry(
    id: _string(data, 'id'),
    teachingClassId: _optionalString(data, 'teachingClassId'),
    courseCode: _optionalString(data, 'courseCode'),
    name: _string(data, 'name'),
    teacher: _optionalString(data, 'teacher'),
    location: _optionalString(data, 'location'),
    campus: _optionalString(data, 'campus'),
    weekday: _optionalInteger(data, 'weekday'),
    startPeriod: _optionalInteger(data, 'startPeriod'),
    endPeriod: _optionalInteger(data, 'endPeriod'),
    weeks: _list(data, 'weeks').map((value) {
      if (value is! int) _invalid('weeks');
      return value;
    }),
    rawWeeks: _optionalString(data, 'rawWeeks'),
    metadata: {
      for (final key in metadata.keys)
        key: _string(metadata, key, allowEmpty: true),
    },
    origin: _enum(data, 'origin', ScheduleEntryOrigin.values),
    kind: _enum(data, 'kind', ScheduleEntryKind.values),
  );
}

Map<String, Object?> _writeCalendar(TeachingCalendar calendar) => {
  'firstWeekMonday': calendar.firstWeekMonday == null
      ? null
      : _dateString(calendar.firstWeekMonday!),
  'totalWeeks': calendar.totalWeeks,
  'source': calendar.source.name,
  'sourceLabel': calendar.sourceLabel,
};

TeachingCalendar _readCalendar(Object? value) {
  final data = _map(value);
  final date = _optionalString(data, 'firstWeekMonday');
  return TeachingCalendar(
    firstWeekMonday: date == null ? null : _civilDate(date),
    totalWeeks: _optionalInteger(data, 'totalWeeks'),
    source: _enum(data, 'source', TeachingCalendarSource.values),
    sourceLabel: _optionalString(data, 'sourceLabel'),
  );
}

Map<String, Object?> _writePeriod(PeriodTime period) => {
  'number': period.number,
  'startMinutes': period.startMinutes,
  'endMinutes': period.endMinutes,
  'campus': period.campus,
};

PeriodTime _readPeriod(Object? value) {
  final data = _map(value);
  return PeriodTime(
    number: _integer(data, 'number'),
    startMinutes: _integer(data, 'startMinutes'),
    endMinutes: _integer(data, 'endMinutes'),
    campus: _optionalString(data, 'campus'),
  );
}

T _decode<T>(String source, T Function(Map<String, Object?> data) read) {
  try {
    final data = _map(jsonDecode(source));
    if (_integer(data, 'version') != _version) {
      throw const FormatException('Unsupported saved schedule version.');
    }
    return read(data);
  } on FormatException catch (error) {
    // JSON's own FormatException carries source text; never expose that payload.
    if (error.source != null) {
      throw const FormatException('Invalid saved schedule JSON.');
    }
    rethrow;
  } on ArgumentError {
    throw const FormatException(
      'Saved schedule data violates its model rules.',
    );
  }
}

void _kind(Map<String, Object?> data, String expected) {
  if (_string(data, 'kind') != expected) _invalid('kind');
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Invalid saved schedule structure.');
  }
  return value;
}

List<Object?> _list(Map<String, Object?> data, String key) {
  final value = data[key];
  if (value is! List<Object?>) _invalid(key);
  return value;
}

String _string(
  Map<String, Object?> data,
  String key, {
  bool allowEmpty = false,
}) {
  final value = data[key];
  if (value is! String || (!allowEmpty && value.trim().isEmpty)) _invalid(key);
  return value;
}

String? _optionalString(Map<String, Object?> data, String key) {
  final value = data[key];
  if (value != null && value is! String) _invalid(key);
  return value as String?;
}

int _integer(Map<String, Object?> data, String key) {
  final value = data[key];
  if (value is! int) _invalid(key);
  return value;
}

bool _boolean(Map<String, Object?> data, String key) {
  final value = data[key];
  if (value is! bool) _invalid(key);
  return value;
}

int? _optionalInteger(Map<String, Object?> data, String key) {
  final value = data[key];
  if (value != null && value is! int) _invalid(key);
  return value as int?;
}

T _enum<T extends Enum>(Map<String, Object?> data, String key, List<T> values) {
  final name = _string(data, key);
  final value = values.where((entry) => entry.name == name).firstOrNull;
  if (value == null) _invalid(key);
  return value;
}

String _dateString(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime _civilDate(String source) {
  final parts = RegExp(r'^(-?\d{4,6})-(\d{2})-(\d{2})$').firstMatch(source);
  if (parts == null) _invalid('firstWeekMonday');
  final date = DateTime(
    int.parse(parts.group(1)!),
    int.parse(parts.group(2)!),
    int.parse(parts.group(3)!),
  );
  if (_dateString(date) != source) _invalid('firstWeekMonday');
  return date;
}

DateTime _timestamp(String source) {
  final date = DateTime.tryParse(source);
  if (date == null || date.toUtc().toIso8601String() != source) {
    _invalid('fetchedAt');
  }
  return date;
}

Never _invalid(String key) =>
    throw FormatException('Invalid saved schedule field: $key.');
