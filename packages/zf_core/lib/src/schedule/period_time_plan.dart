import 'teaching_calendar.dart';

enum PeriodSession { morning, afternoon, evening }

final class PeriodTimeException implements Exception {
  const PeriodTimeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A section refers to period numbers; its start time remains on the first row.
final class PeriodTimeSection {
  PeriodTimeSection({
    required this.session,
    required this.firstPeriod,
    required this.lastPeriod,
    String? campus,
  }) : campus = normalizePeriodCampus(campus) {
    if (firstPeriod < 1 || lastPeriod < firstPeriod) {
      throw const PeriodTimeException('时段的起止节次必须为正数，且结束节次不能早于开始节次。');
    }
  }

  final PeriodSession session;
  final int firstPeriod;
  final int lastPeriod;
  final String? campus;

  @override
  bool operator ==(Object other) =>
      other is PeriodTimeSection &&
      session == other.session &&
      firstPeriod == other.firstPeriod &&
      lastPeriod == other.lastPeriod &&
      campus == other.campus;

  @override
  int get hashCode => Object.hash(session, firstPeriod, lastPeriod, campus);
}

final class PeriodSectionInput {
  const PeriodSectionInput({
    required this.session,
    required this.count,
    required this.startMinutes,
  });

  final PeriodSession session;
  final int count;
  final int startMinutes;
}

/// An editable draft, including imported rows that conflict with one another.
/// Transformations check row bounds and section metadata without pushing other
/// sections. Call [validate] to display preview conflicts and before saving.
final class PeriodTimePlan {
  PeriodTimePlan({
    required List<PeriodTime> periods,
    List<PeriodTimeSection> sections = const [],
  }) : periods = List<PeriodTime>.unmodifiable(
         <PeriodTime>[...periods]..sort(_comparePeriods),
       ),
       sections = List<PeriodTimeSection>.unmodifiable(
         <PeriodTimeSection>[...sections]..sort(_compareSections),
       );

  final List<PeriodTime> periods;
  final List<PeriodTimeSection> sections;

  List<PeriodTime> periodsForCampus(String? campus) => List.unmodifiable(
    periods.where(
      (period) =>
          normalizePeriodCampus(period.campus) == normalizePeriodCampus(campus),
    ),
  );

  PeriodTimeSection? sectionFor(PeriodTime period) =>
      _sectionForNumber(period.number, period.campus);

  void validate() {
    PeriodTime? previous;
    for (final period in periods) {
      if (previous != null &&
          normalizePeriodCampus(previous.campus) ==
              normalizePeriodCampus(period.campus)) {
        if (previous.number == period.number) {
          throw PeriodTimeException(
            '${_periodName(period.number, period.campus)}重复，请合并或删除重复节次。',
          );
        }
        if (period.startMinutes < previous.endMinutes) {
          throw PeriodTimeException(
            '${_periodName(period.number, period.campus)}与第${previous.number}节时间重叠或顺序颠倒。',
          );
        }
      }
      previous = period;
    }
    validateSections();
  }

  void validateSections() => validatePeriodTimeSections(periods, sections);

  PeriodTimePlan generate({
    String? campus,
    required List<PeriodSectionInput> inputs,
    required int classMinutes,
    required int breakMinutes,
    int? longBreakEvery,
    int? longBreakMinutes,
  }) {
    if (inputs.isEmpty) {
      throw const PeriodTimeException('请至少启用一个时段。');
    }
    if (inputs.length > PeriodSession.values.length ||
        inputs.map((input) => input.session).toSet().length != inputs.length) {
      throw const PeriodTimeException('上午、下午、晚上每个时段只能设置一次。');
    }
    if (classMinutes <= 0 || breakMinutes < 0) {
      throw const PeriodTimeException('每节课时长必须大于 0，课间时长不能为负数。');
    }
    if ((longBreakEvery == null) != (longBreakMinutes == null) ||
        (longBreakEvery != null &&
            (longBreakEvery <= 0 || longBreakMinutes! < 0))) {
      throw const PeriodTimeException('长课间需要同时填写正数节次间隔和非负时长。');
    }
    final ordered = [...inputs]
      ..sort((a, b) => a.session.index.compareTo(b.session.index));
    var totalCount = 0;
    for (final input in ordered) {
      _validateGenerationWindow(
        input,
        classMinutes: classMinutes,
        breakMinutes: breakMinutes,
        longBreakEvery: longBreakEvery,
        longBreakMinutes: longBreakMinutes,
      );
      totalCount += input.count;
      if (totalCount > PeriodTime.minutesPerDay ~/ classMinutes) {
        throw const PeriodTimeException('所有课节的总时长超过一天，请减少节数或课时长度。');
      }
    }

    final targetCampus = normalizePeriodCampus(campus);
    final generated = <PeriodTime>[];
    final generatedSections = <PeriodTimeSection>[];
    var number = 1;
    for (final input in ordered) {
      final first = number;
      var start = input.startMinutes;
      for (var index = 0; index < input.count; index++) {
        final end = start + classMinutes;
        generated.add(_period(number++, start, end, targetCampus));
        if (index < input.count - 1) {
          final gap =
              longBreakEvery != null && (index + 1) % longBreakEvery == 0
              ? longBreakMinutes!
              : breakMinutes;
          start = end + gap;
        }
      }
      generatedSections.add(
        PeriodTimeSection(
          session: input.session,
          firstPeriod: first,
          lastPeriod: number - 1,
          campus: targetCampus,
        ),
      );
    }
    return _draft(
      [
        ...periods.where(
          (period) => normalizePeriodCampus(period.campus) != targetCampus,
        ),
        ...generated,
      ],
      [
        ...sections.where((section) => section.campus != targetCampus),
        ...generatedSections,
      ],
    );
  }

  PeriodTimePlan withSections({
    String? campus,
    required List<PeriodTimeSection> sections,
  }) {
    final targetCampus = normalizePeriodCampus(campus);
    if (sections.any((section) => section.campus != targetCampus)) {
      throw const PeriodTimeException('时段划分必须属于当前选择的校区。');
    }
    return _draft(periods, [
      ...this.sections.where((section) => section.campus != targetCampus),
      ...sections,
    ]);
  }

  PeriodTimePlan edit({
    required int number,
    String? campus,
    int? startMinutes,
    int? endMinutes,
    bool shiftFollowing = true,
  }) {
    final original = _findPeriod(number, campus);
    final start = startMinutes ?? original.startMinutes;
    if (start < 0 || start >= PeriodTime.minutesPerDay) {
      throw PeriodTimeException(
        '${_periodName(number, campus)}的开始时间必须在 00:00 至 24:00 之间。',
      );
    }
    final end =
        endMinutes ?? (start + original.endMinutes - original.startMinutes);
    final replacement = _period(number, start, end, original.campus);
    var updated = [
      for (final period in periods)
        identical(period, original) ? replacement : period,
    ];
    final section = sectionFor(original);
    if (shiftFollowing && section != null) {
      updated = _shiftFollowing(
        updated,
        section,
        number,
        end - original.endMinutes,
      );
    }
    return _draft(updated, sections);
  }

  PeriodTimePlan changeBreak({
    required int afterNumber,
    String? campus,
    required int minutes,
  }) {
    if (minutes < 0 || minutes > PeriodTime.minutesPerDay) {
      throw const PeriodTimeException('课间时长必须在 0 至 1440 分钟之间。');
    }
    final previous = _findPeriod(afterNumber, campus);
    final section = sectionFor(previous);
    if (section == null || afterNumber == section.lastPeriod) {
      throw PeriodTimeException(
        '${_periodName(afterNumber, campus)}之后没有同一时段的连续课节，不能联动调整课间。',
      );
    }
    final next = _findPeriod(afterNumber + 1, campus);
    final difference = minutes - (next.startMinutes - previous.endMinutes);
    return _draft(
      _shiftFollowing(periods, section, afterNumber, difference),
      sections,
    );
  }

  PeriodTimePlan add(PeriodTime period) {
    if (periods.any(
      (existing) =>
          existing.number == period.number &&
          normalizePeriodCampus(existing.campus) ==
              normalizePeriodCampus(period.campus),
    )) {
      throw PeriodTimeException(
        '${_periodName(period.number, period.campus)}已存在，请编辑现有课节或使用其他节号。',
      );
    }
    return _draft([...periods, period], sections);
  }

  /// Lets the UI announce that deleting an interior period cancels its section.
  bool removalClearsSection({required int number, String? campus}) {
    final section = _sectionForNumber(number, campus);
    return section != null &&
        number > section.firstPeriod &&
        number < section.lastPeriod;
  }

  PeriodTimePlan remove({required int number, String? campus}) {
    final targetCampus = normalizePeriodCampus(campus);
    final remaining = periods
        .where(
          (period) =>
              period.number != number ||
              normalizePeriodCampus(period.campus) != targetCampus,
        )
        .toList();
    if (remaining.length == periods.length) {
      throw PeriodTimeException('${_periodName(number, campus)}不存在。');
    }
    final section = _sectionForNumber(number, campus);
    final updatedSections = <PeriodTimeSection>[];
    for (final existing in sections) {
      if (!identical(existing, section)) {
        updatedSections.add(existing);
        continue;
      }
      if (existing.firstPeriod == existing.lastPeriod ||
          removalClearsSection(number: number, campus: campus)) {
        continue;
      }
      updatedSections.add(
        PeriodTimeSection(
          session: existing.session,
          firstPeriod:
              existing.firstPeriod + (number == existing.firstPeriod ? 1 : 0),
          lastPeriod:
              existing.lastPeriod - (number == existing.lastPeriod ? 1 : 0),
          campus: existing.campus,
        ),
      );
    }
    return _draft(remaining, updatedSections);
  }

  PeriodTime _findPeriod(int number, String? campus) {
    final matching = periodsForCampus(campus)
        .where((period) => period.number == number)
        .toList();
    if (matching.isEmpty) {
      throw PeriodTimeException('${_periodName(number, campus)}不存在。');
    }
    if (matching.length > 1) {
      throw PeriodTimeException('${_periodName(number, campus)}重复，请先合并重复节次。');
    }
    return matching.single;
  }

  PeriodTimeSection? _sectionForNumber(int number, String? campus) {
    final matching = sections
        .where(
          (section) =>
              section.campus == normalizePeriodCampus(campus) &&
              number >= section.firstPeriod &&
              number <= section.lastPeriod,
        )
        .toList();
    if (matching.length > 1) {
      throw PeriodTimeException(
        '${_periodName(number, campus)}属于多个时段，请先修正时段划分。',
      );
    }
    return matching.firstOrNull;
  }
}

/// Checks only section membership, so import-time conflicts remain editable.
void validatePeriodTimeSections(
  Iterable<PeriodTime> periods,
  Iterable<PeriodTimeSection> sections,
) {
  final numbers = <String?, Set<int>>{};
  for (final period in periods) {
    (numbers[normalizePeriodCampus(period.campus)] ??= {}).add(period.number);
  }
  final grouped = <String?, List<PeriodTimeSection>>{};
  for (final section in sections) {
    (grouped[section.campus] ??= []).add(section);
  }
  for (final entry in grouped.entries) {
    final available = numbers[entry.key] ?? const <int>{};
    final ordered = [...entry.value]..sort(_compareSections);
    final used = <PeriodSession>{};
    PeriodTimeSection? previous;
    for (final section in ordered) {
      final name = _sessionName(section.session);
      if (!used.add(section.session)) {
        throw PeriodTimeException('同一校区的$name时段重复。');
      }
      if (previous != null) {
        if (section.firstPeriod <= previous.lastPeriod) {
          throw PeriodTimeException('第${section.firstPeriod}节所在的时段与前一时段重叠。');
        }
        if (section.session.index <= previous.session.index) {
          throw const PeriodTimeException('时段的节次顺序应为上午、下午、晚上。');
        }
      }
      if (!available.contains(section.firstPeriod) ||
          !available.contains(section.lastPeriod)) {
        throw PeriodTimeException(
          '$name时段的首末节必须存在，请检查第${section.firstPeriod}、${section.lastPeriod}节。',
        );
      }
      final count = available
          .where(
            (number) =>
                number >= section.firstPeriod && number <= section.lastPeriod,
          )
          .length;
      if (count != section.lastPeriod - section.firstPeriod + 1) {
        throw PeriodTimeException(
          '$name时段的第${section.firstPeriod}-${section.lastPeriod}节不连续，请先补齐节次或调整划分。',
        );
      }
      previous = section;
    }
  }
}

PeriodTimePlan _draft(
  List<PeriodTime> periods,
  List<PeriodTimeSection> sections,
) {
  final result = PeriodTimePlan(periods: periods, sections: sections);
  result.validateSections();
  return result;
}

void _validateGenerationWindow(
  PeriodSectionInput input, {
  required int classMinutes,
  required int breakMinutes,
  int? longBreakEvery,
  int? longBreakMinutes,
}) {
  final name = _sessionName(input.session);
  if (input.count <= 0) {
    throw PeriodTimeException('$name的节数必须大于 0；未启用的时段应留空。');
  }
  if (input.startMinutes < 0 ||
      input.startMinutes >= PeriodTime.minutesPerDay) {
    throw PeriodTimeException('$name的首课开始时间必须在 00:00 至 24:00 之间。');
  }
  final gaps = input.count - 1;
  final longGaps = longBreakEvery == null ? 0 : gaps ~/ longBreakEvery;
  var remaining = PeriodTime.minutesPerDay - input.startMinutes;
  // Divide before multiplying, so even an untrusted, enormous count cannot
  // overflow or allocate a list before the day's physical capacity is checked.
  for (final (count, minutes) in [
    (input.count, classMinutes),
    (gaps - longGaps, breakMinutes),
    (longGaps, longBreakMinutes ?? 0),
  ]) {
    if (count != 0 && minutes > remaining ~/ count) {
      throw PeriodTimeException('$name的课节与课间超过 24:00，请减少节数或调整时间。');
    }
    remaining -= count * minutes;
  }
}

List<PeriodTime> _shiftFollowing(
  List<PeriodTime> periods,
  PeriodTimeSection section,
  int afterNumber,
  int difference,
) => [
  for (final period in periods)
    if (normalizePeriodCampus(period.campus) == section.campus &&
        period.number > afterNumber &&
        period.number <= section.lastPeriod)
      _period(
        period.number,
        period.startMinutes + difference,
        period.endMinutes + difference,
        period.campus,
      )
    else
      period,
];

PeriodTime _period(int number, int start, int end, String? campus) {
  if (number < 1 ||
      start < 0 ||
      end > PeriodTime.minutesPerDay ||
      start >= end) {
    throw PeriodTimeException(
      '${_periodName(number, campus)}必须在当天 00:00 至 24:00 内结束，且结束时间晚于开始时间。',
    );
  }
  return PeriodTime(
    number: number,
    startMinutes: start,
    endMinutes: end,
    campus: normalizePeriodCampus(campus),
  );
}

int _comparePeriods(PeriodTime a, PeriodTime b) {
  final campus = (normalizePeriodCampus(a.campus) ?? '').compareTo(
    normalizePeriodCampus(b.campus) ?? '',
  );
  if (campus != 0) return campus;
  final number = a.number.compareTo(b.number);
  if (number != 0) return number;
  final start = a.startMinutes.compareTo(b.startMinutes);
  return start != 0 ? start : a.endMinutes.compareTo(b.endMinutes);
}

int _compareSections(PeriodTimeSection a, PeriodTimeSection b) {
  final campus = (a.campus ?? '').compareTo(b.campus ?? '');
  return campus != 0 ? campus : a.firstPeriod.compareTo(b.firstPeriod);
}

/// Uses the same campus identity for imported rows, section boundaries and UI.
String? normalizePeriodCampus(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String _periodName(int number, String? campus) =>
    '${normalizePeriodCampus(campus) == null ? '' : '${normalizePeriodCampus(campus)}的'}第$number节';

String _sessionName(PeriodSession session) => switch (session) {
  PeriodSession.morning => '上午',
  PeriodSession.afternoon => '下午',
  PeriodSession.evening => '晚上',
};
