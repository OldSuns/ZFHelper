import 'dart:convert';

import 'package:zf_core/zf_core.dart';

import 'academic_account.dart';
import 'course_store.dart';

/// Durable course data, deliberately excluding live request forms and tokens.
abstract final class CourseLibraryCodec {
  static String encode(CourseLibrary library) {
    final data = <String, Object?>{
      'version': 1,
      'selectedAccount': library.selectedAccount == null
          ? null
          : _writeScope(library.selectedAccount!),
      'accounts': [
        for (final stored in library.accounts) _writeAccount(stored),
      ],
    };
    // Validate the durable projection once, with the same rules used on reads.
    _readLibrary(data);
    return jsonEncode(data);
  }

  static CourseLibrary decode(String source) =>
      _readLibrary(jsonDecode(source));
}

/// Operations remain readable after their round disappears from the catalog.
abstract final class SelectionOperationsCodec {
  static String encode(List<SelectionOperation> operations) {
    final data = <String, Object?>{
      'version': 1,
      'operations': [
        for (final operation in operations) _writeOperation(operation),
      ],
    };
    _readOperations(data);
    return jsonEncode(data);
  }

  static List<SelectionOperation> decode(String source) =>
      _readOperations(jsonDecode(source));
}

CourseLibrary _readLibrary(Object? value) {
  final data = _versioned(value);
  final library = CourseLibrary(
    accounts: _list(data['accounts'], _readAccount),
    selectedAccount: data['selectedAccount'] == null
        ? null
        : _readScope(data['selectedAccount']),
  );
  final scopes = <AccountScope>{};
  for (final account in library.accounts) {
    if (!scopes.add(account.account.scope)) {
      throw const FormatException('Duplicate saved course account.');
    }
  }
  if (library.selectedAccount != null &&
      !scopes.contains(library.selectedAccount)) {
    throw const FormatException('Selected course account is missing.');
  }
  return library;
}

Map<String, Object?> _writeAccount(StoredCourseAccount stored) => {
  'scope': _writeScope(stored.account.scope),
  'schoolName': stored.account.schoolName,
  'accountName': stored.account.accountName,
  'loginName': stored.account.loginName,
  'rounds': [for (final round in stored.rounds) _writeRound(round)],
  'catalogs': [for (final catalog in stored.catalogs) _writeCatalog(catalog)],
  'selectedRoundKey': stored.selectedRoundKey,
  'roundsFetchedAt': _writeDate(stored.roundsFetchedAt),
};

StoredCourseAccount _readAccount(Object? value) {
  final data = _map(value);
  final stored = StoredCourseAccount(
    account: AcademicAccountRecord(
      scope: _readScope(data['scope']),
      schoolName: _string(data['schoolName']),
      accountName: _string(data['accountName']),
      loginName: _string(data['loginName']),
    ),
    rounds: _list(data['rounds'], _readRound),
    catalogs: _list(data['catalogs'], _readCatalog),
    selectedRoundKey: _nullableString(data['selectedRoundKey']),
    roundsFetchedAt: _nullableDate(data['roundsFetchedAt']),
  );
  final rounds = <String, SelectionRound>{};
  for (final round in stored.rounds) {
    if (rounds.containsKey(round.key)) {
      throw const FormatException('Duplicate saved selection round.');
    }
    rounds[round.key] = round;
  }
  if (stored.selectedRoundKey != null &&
      !rounds.containsKey(stored.selectedRoundKey)) {
    throw const FormatException('Selected selection round is missing.');
  }
  final catalogs = <String>{};
  for (final catalog in stored.catalogs) {
    final round = rounds[catalog.roundKey];
    if (round == null || !catalogs.add(catalog.roundKey)) {
      throw const FormatException('Invalid course catalog round.');
    }
    for (final selected in catalog.selectedCourses) {
      if (round.term != null &&
          selected.term != null &&
          round.term != selected.term) {
        throw const FormatException('Selected course belongs to another term.');
      }
    }
  }
  return stored;
}

Map<String, Object?> _writeRound(SelectionRound round) => {
  'controlKey': round.controlKey,
  'controlId': round.controlId,
  'categoryCode': round.categoryCode,
  'categoryLabel': round.categoryLabel,
  'label': round.label,
  'term': _writeTerm(round.term),
  'gradeId': round.gradeId,
  'majorId': round.majorId,
};

SelectionRound _readRound(Object? value) {
  final data = _map(value);
  return SelectionRound(
    controlKey: _string(data['controlKey']),
    controlId: _string(data['controlId']),
    categoryCode: _string(data['categoryCode']),
    categoryLabel: _text(data['categoryLabel']),
    label: _string(data['label']),
    term: _readTerm(data['term']),
    gradeId: _text(data['gradeId']),
    majorId: _text(data['majorId']),
  );
}

Map<String, Object?> _writeCatalog(CourseRoundCache cache) => {
  'roundKey': cache.roundKey,
  'courses': [for (final course in cache.courses) _writeOffering(course)],
  'selectedCourses': [
    for (final course in cache.selectedCourses) _writeSelected(course),
  ],
  'fetchedAt': _writeDate(cache.fetchedAt),
  'selectedFetchedAt': _writeDate(cache.selectedFetchedAt),
};

CourseRoundCache _readCatalog(Object? value) {
  final data = _map(value);
  final cache = CourseRoundCache(
    roundKey: _string(data['roundKey']),
    courses: _list(data['courses'], _readOffering),
    selectedCourses: _list(data['selectedCourses'], _readSelected),
    fetchedAt: _date(data['fetchedAt']),
    selectedFetchedAt: _nullableDate(data['selectedFetchedAt']),
  );
  final courses = <String>{};
  for (final course in cache.courses) {
    if (course.roundKey != cache.roundKey || !courses.add(course.key)) {
      throw const FormatException('Invalid or duplicate course identity.');
    }
  }
  final selected = <String>{};
  for (final course in cache.selectedCourses) {
    if (!selected.add(course.key)) {
      throw const FormatException('Duplicate selected course identity.');
    }
  }
  return cache;
}

Map<String, Object?> _writeOffering(CourseOffering course) => {
  'roundKey': course.roundKey,
  'courseId': course.courseId,
  'name': course.name,
  'sectionId': course.sectionId,
  'teacher': course.teacher,
  'time': course.time,
  'location': course.location,
  'credit': course.credit,
  'capacity': course.capacity,
  'selected': course.selected,
  'sectionCount': course.sectionCount,
  'sectionAvailability': course.sectionAvailability,
  'availabilityFetchedAt': _writeDate(course.availabilityFetchedAt),
  'isSelected': course.isSelected,
};

CourseOffering _readOffering(Object? value) {
  final data = _map(value);
  final sectionCount = _nullableCount(data['sectionCount']);
  final available = _nullableCount(data['sectionAvailability']);
  final fetchedAt = _nullableDate(data['availabilityFetchedAt']);
  if ((sectionCount != null && fetchedAt == null) ||
      (sectionCount == null && available != null)) {
    throw const FormatException('Invalid course availability summary.');
  }
  return CourseOffering(
    roundKey: _string(data['roundKey']),
    courseId: _string(data['courseId']),
    name: _string(data['name']),
    sectionId: _nullableText(data['sectionId']),
    teacher: _nullableText(data['teacher']),
    time: _nullableText(data['time']),
    location: _nullableText(data['location']),
    credit: _nullableText(data['credit']),
    capacity: _nullableCount(data['capacity']),
    selected: _nullableCount(data['selected']),
    sectionCount: sectionCount,
    sectionAvailability: available,
    availabilityFetchedAt: fetchedAt,
    isSelected: data['isSelected'] == null
        ? null
        : _boolean(data['isSelected']),
  );
}

Map<String, Object?> _writeSelected(SelectedCourse course) => {
  'courseId': course.courseId,
  'sectionId': course.sectionId,
  'name': course.name,
  'term': _writeTerm(course.term),
  'teacher': course.teacher,
  'time': course.time,
  'location': course.location,
};

SelectedCourse _readSelected(Object? value) {
  final data = _map(value);
  return SelectedCourse(
    courseId: _string(data['courseId']),
    sectionId: _text(data['sectionId']),
    name: _string(data['name']),
    term: _readTerm(data['term']),
    teacher: _nullableText(data['teacher']),
    time: _nullableText(data['time']),
    location: _nullableText(data['location']),
  );
}

Map<String, Object?> _writeOperation(SelectionOperation operation) => {
  'id': operation.id,
  'target': _writeTarget(operation.target),
  'mode': operation.mode.name,
  'status': operation.status.name,
  'createdAt': _writeDate(operation.createdAt),
  'updatedAt': _writeDate(operation.updatedAt),
  'expiresAt': _writeDate(operation.expiresAt),
  'intervalMicroseconds': operation.interval.inMicroseconds,
  'durationMicroseconds': operation.duration.inMicroseconds,
  'checks': operation.checks,
  'submissions': operation.submissions,
  'message': operation.message,
  'nextCheckAt': _writeDate(operation.nextCheckAt),
  'cancelRequested': operation.cancelRequested,
};

List<SelectionOperation> _readOperations(Object? value) {
  final data = _versioned(value);
  final operations = _list(data['operations'], _readOperation);
  final ids = <String>{};
  for (final operation in operations) {
    if (!ids.add(operation.id)) {
      throw const FormatException('Duplicate selection operation.');
    }
  }
  return List.unmodifiable(operations);
}

SelectionOperation _readOperation(Object? value) {
  final data = _map(value);
  return SelectionOperation(
    id: _string(data['id']),
    target: _readTarget(data['target']),
    mode: _enum(data['mode'], SelectionMode.values),
    status: _enum(data['status'], SelectionStatus.values),
    createdAt: _date(data['createdAt']),
    updatedAt: _date(data['updatedAt']),
    expiresAt: _date(data['expiresAt']),
    interval: Duration(
      microseconds: _positiveCount(data['intervalMicroseconds']),
    ),
    duration: Duration(
      microseconds: _positiveCount(data['durationMicroseconds']),
    ),
    checks: _count(data['checks']),
    submissions: _count(data['submissions']),
    message: _text(data['message']),
    nextCheckAt: _nullableDate(data['nextCheckAt']),
    cancelRequested: _boolean(data['cancelRequested']),
  );
}

Map<String, Object?> _writeTarget(SelectionTarget target) => {
  'scope': _writeScope(target.scope),
  'schoolName': target.schoolName,
  'accountName': target.accountName,
  'round': _writeRound(target.round),
  'courseId': target.courseId,
  'sectionId': target.sectionId,
  'name': target.name,
  'teacher': target.teacher,
  'time': target.time,
  'location': target.location,
};

SelectionTarget _readTarget(Object? value) {
  final data = _map(value);
  return SelectionTarget(
    scope: _readScope(data['scope']),
    schoolName: _string(data['schoolName']),
    accountName: _string(data['accountName']),
    round: _readRound(data['round']),
    courseId: _string(data['courseId']),
    sectionId: _string(data['sectionId']),
    name: _string(data['name']),
    teacher: _nullableText(data['teacher']),
    time: _nullableText(data['time']),
    location: _nullableText(data['location']),
  );
}

Map<String, Object?> _writeScope(AccountScope scope) => {
  'schoolId': scope.schoolId,
  'accountId': scope.accountId,
};

AccountScope _readScope(Object? value) {
  final data = _map(value);
  return AccountScope(
    schoolId: _string(data['schoolId']),
    accountId: _string(data['accountId']),
  );
}

Map<String, Object?>? _writeTerm(AcademicTerm? term) => term == null
    ? null
    : {
        'yearCode': term.yearCode,
        'termCode': term.termCode,
        'label': term.label,
      };

AcademicTerm? _readTerm(Object? value) {
  if (value == null) return null;
  final data = _map(value);
  return AcademicTerm(
    yearCode: _string(data['yearCode']),
    termCode: _string(data['termCode']),
    label: _string(data['label']),
  );
}

Map<String, Object?> _versioned(Object? value) {
  final data = _map(value);
  if (data['version'] is! int || data['version'] != 1) {
    throw const FormatException('Unsupported saved selection data version.');
  }
  return data;
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Invalid saved selection object.');
  }
  return value;
}

List<T> _list<T>(Object? value, T Function(Object?) decode) {
  if (value is! List<Object?>) {
    throw const FormatException('Invalid saved selection list.');
  }
  return value.map(decode).toList(growable: false);
}

String _text(Object? value) {
  if (value is! String) {
    throw const FormatException('Invalid saved selection text.');
  }
  return value;
}

String _string(Object? value) {
  final text = _text(value);
  if (text.trim().isEmpty) {
    throw const FormatException('Empty saved selection identity or label.');
  }
  return text;
}

String? _nullableText(Object? value) => value == null ? null : _text(value);
String? _nullableString(Object? value) => value == null ? null : _string(value);

bool _boolean(Object? value) {
  if (value is! bool) {
    throw const FormatException('Invalid saved selection flag.');
  }
  return value;
}

int _count(Object? value) {
  if (value is! int || value < 0) {
    throw const FormatException('Invalid saved selection count.');
  }
  return value;
}

int? _nullableCount(Object? value) => value == null ? null : _count(value);

int _positiveCount(Object? value) {
  final count = _count(value);
  if (count == 0) {
    throw const FormatException('Invalid saved selection duration.');
  }
  return count;
}

T _enum<T extends Enum>(Object? value, List<T> values) {
  final name = _string(value);
  for (final item in values) {
    if (item.name == name) return item;
  }
  throw const FormatException('Unknown saved selection state.');
}

String? _writeDate(DateTime? date) => date?.toUtc().toIso8601String();
DateTime? _nullableDate(Object? value) => value == null ? null : _date(value);

DateTime _date(Object? value) {
  final text = _string(value);
  final date = DateTime.tryParse(text);
  if (date == null || !date.isUtc || date.toIso8601String() != text) {
    throw const FormatException('Invalid saved selection timestamp.');
  }
  return date;
}
