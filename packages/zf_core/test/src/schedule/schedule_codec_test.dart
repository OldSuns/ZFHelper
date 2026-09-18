import 'dart:convert';

import 'package:test/test.dart';
import 'package:zf_core/src/schedule/academic_term.dart';
import 'package:zf_core/src/schedule/period_time_plan.dart';
import 'package:zf_core/src/schedule/schedule_codec.dart';
import 'package:zf_core/src/schedule/schedule_entry.dart';
import 'package:zf_core/src/schedule/schedule_settings.dart';
import 'package:zf_core/src/schedule/schedule_snapshot.dart';
import 'package:zf_core/src/schedule/teaching_calendar.dart';

void main() {
  final term = AcademicTerm(
    yearCode: '2026',
    termCode: '16',
    label: '2026 短学期',
  );
  ScheduleEntry lesson({
    String id = 'school-1',
    ScheduleEntryOrigin origin = ScheduleEntryOrigin.imported,
  }) => ScheduleEntry(
    id: id,
    teachingClassId: 'class-1',
    courseCode: 'CHEM',
    name: '化学实验',
    teacher: '测试教师',
    location: '实验楼 301',
    campus: '测试校区',
    weekday: 3,
    startPeriod: 5,
    endPeriod: 6,
    weeks: {1, 3, 5},
    rawWeeks: '1-5周(单)',
    metadata: {'xf': '2.5'},
    origin: origin,
  );
  ScheduleSnapshot snapshot() => ScheduleSnapshot(
    term: term,
    entries: [
      lesson(),
      ScheduleEntry(
        id: 'practice-1',
        name: '实践活动',
        weeks: {6, 7},
        kind: ScheduleEntryKind.practice,
      ),
    ],
    fetchedAt: DateTime.utc(2026, 9, 13, 4, 30, 12, 345, 678),
    calendar: TeachingCalendar(
      firstWeekMonday: DateTime(2026, 9, 7),
      totalWeeks: 8,
      source: TeachingCalendarSource.school,
      sourceLabel: '学校校历',
    ),
    periodTimes: [
      PeriodTime(number: 5, startMinutes: 14 * 60, endMinutes: 14 * 60 + 45),
    ],
    sourceLabel: '教务课表',
  );

  test(
    'snapshot restoration preserves lesson, practice, clock and evidence',
    () {
      final original = snapshot();
      final restored = ScheduleSnapshotCodec.decode(
        ScheduleSnapshotCodec.encode(original),
      );
      expect(restored.term, term);
      expect(restored.term.termCode, '16');
      expect(restored.entries.first.location, '实验楼 301');
      expect(restored.entries.first.rawWeeks, '1-5周(单)');
      expect(restored.entries.first.occursInWeek(2), isFalse);
      expect(restored.entries.first.occursInWeek(3), isTrue);
      expect(restored.entries.first.metadata['xf'], '2.5');
      expect(restored.entries.last.kind, ScheduleEntryKind.practice);
      expect(restored.entries.last.isPlaced, isFalse);
      expect(restored.calendar.firstWeekMonday, DateTime(2026, 9, 7));
      expect(restored.calendar.positionOn(DateTime(2026, 9, 21)).week, 3);
      expect(restored.periodTimes.single.startMinutes, 840);
      expect(restored.fetchedAt, original.fetchedAt);
      expect(restored.periodCampus, isNull);
      expect(restored.sourceLabel, '教务课表');
    },
  );

  test(
    'empty successful snapshots and unknown calendars survive persistence',
    () {
      final restored = ScheduleSnapshotCodec.decode(
        ScheduleSnapshotCodec.encode(
          ScheduleSnapshot(
            term: term,
            entries: [],
            fetchedAt: DateTime.utc(2026),
          ),
        ),
      );
      expect(restored.entries, isEmpty);
      expect(restored.calendar.source, TeachingCalendarSource.unknown);
      expect(restored.calendar.firstWeekMonday, isNull);
      expect(restored.observedMaxWeek, 0);
    },
  );

  test('local settings survive refresh and do not mutate school evidence', () {
    final school = snapshot();
    final settings = ScheduleSettings(
      calendarOverride: TeachingCalendar(
        firstWeekMonday: DateTime(2026, 8, 31),
        totalWeeks: 10,
        source: TeachingCalendarSource.user,
      ),
      periodTimes: [
        PeriodTime(
          number: 5,
          startMinutes: 13 * 60,
          endMinutes: 13 * 60 + 45,
          campus: '北校区',
        ),
      ],
      periodCampus: '北校区',
      periodSections: [
        PeriodTimeSection(
          session: PeriodSession.afternoon,
          firstPeriod: 5,
          lastPeriod: 5,
          campus: '北校区',
        ),
      ],
      localEntries: [
        lesson(id: 'local-course', origin: ScheduleEntryOrigin.local),
      ],
      hiddenEntryIds: ['school-1'],
    );
    final restored = ScheduleSettingsCodec.decode(
      ScheduleSettingsCodec.encode(settings),
    );
    final effective = restored.applyTo(school);
    expect(effective.entries.map((entry) => entry.id), [
      'practice-1',
      'local-course',
    ]);
    expect(effective.calendar.source, TeachingCalendarSource.user);
    expect(effective.calendar.positionOn(DateTime(2026, 9, 7)).week, 2);
    expect(effective.periodTimes.single.startMinutes, 780);
    expect(effective.periodCampus, '北校区');
    expect(restored.periodSections, settings.periodSections);
    expect(restored.periodCampus, '北校区');
    expect(
      restored.reconcileImport(school, snapshot()).periodSections,
      restored.periodSections,
    );
    expect(school.entries.first.id, 'school-1');
    expect(school.calendar.positionOn(DateTime(2026, 9, 7)).week, 1);
    expect(effective.fetchedAt, school.fetchedAt);
    expect(
      restored
          .applyTo(school.copyWith(fetchedAt: DateTime.utc(2026, 9, 20)))
          .entries
          .last
          .origin,
      ScheduleEntryOrigin.local,
    );
  });

  test('clearing overrides restores imported calendar and times', () {
    final settings = ScheduleSettings(
      calendarOverride: TeachingCalendar(
        firstWeekMonday: DateTime(2026, 8, 31),
        source: TeachingCalendarSource.user,
      ),
    ).copyWith(clearCalendarOverride: true);
    expect(
      settings.applyTo(snapshot()).calendar.source,
      TeachingCalendarSource.school,
    );
  });

  test('explicitly empty custom times persist across import refreshes', () {
    final settings = ScheduleSettings(useCustomPeriodTimes: true);
    final restored = ScheduleSettingsCodec.decode(
      ScheduleSettingsCodec.encode(settings),
    );
    expect(restored.useCustomPeriodTimes, isTrue);
    expect(restored.applyTo(snapshot()).periodTimes, isEmpty);
    expect(
      restored
          .applyTo(
            snapshot().copyWith(
              periodTimes: [
                PeriodTime(number: 1, startMinutes: 480, endMinutes: 525),
              ],
            ),
          )
          .periodTimes,
      isEmpty,
    );
    final inherited = restored.copyWith(useCustomPeriodTimes: false);
    expect(inherited.applyTo(snapshot()).periodTimes.single.number, 5);
    expect(ScheduleSettings().useCustomPeriodTimes, isFalse);
  });

  test('custom-time flags reject invalid saved types and remain explicit', () {
    final data = jsonDecode(
      ScheduleSettingsCodec.encode(ScheduleSettings()),
    ) as Map<String, Object?>;
    data['useCustomPeriodTimes'] = 'true';
    expect(
      () => ScheduleSettingsCodec.decode(jsonEncode(data)),
      throwsA(isA<FormatException>()),
    );
    data.remove('useCustomPeriodTimes');
    expect(
      () => ScheduleSettingsCodec.decode(jsonEncode(data)),
      throwsA(isA<FormatException>()),
    );
  });

  test('period section metadata is optional in old records and strict when present', () {
    final data = jsonDecode(
      ScheduleSettingsCodec.encode(
        ScheduleSettings(
          periodTimes: [
            PeriodTime(number: 5, startMinutes: 780, endMinutes: 825),
          ],
        ),
      ),
    ) as Map<String, Object?>;
    data.remove('periodSections');
    expect(
      ScheduleSettingsCodec.decode(jsonEncode(data)).periodSections,
      isEmpty,
    );
    const section = {'session': 'afternoon', 'firstPeriod': 5, 'lastPeriod': 5};
    for (final invalid in <Object?>[
      null,
      {},
      [
        {...section, 'session': 'night'},
      ],
      [
        {...section, 'firstPeriod': 0},
      ],
      [
        {...section, 'firstPeriod': '5'},
      ],
      [
        {...section, 'lastPeriod': 4},
      ],
      [
        {...section, 'campus': 7},
      ],
      [
        {...section, 'firstPeriod': 6, 'lastPeriod': 6},
      ],
    ]) {
      expect(
        () => ScheduleSettingsCodec.decode(
          jsonEncode({...data, 'periodSections': invalid}),
        ),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test(
    'catalog persistence retains independent selectors and unknown selection',
    () {
      final catalog = TermCatalog(
        terms: [term],
        yearOptions: const [
          TermOption(code: '2025', label: '2025–2026'),
          TermOption(code: '2026', label: '2026–2027'),
        ],
        termOptions: const [TermOption(code: '16', label: '短学期')],
      );
      final restored = TermCatalogCodec.decode(
        TermCatalogCodec.encode(catalog),
      );
      expect(restored.terms, [term]);
      expect(restored.yearOptions.map((option) => option.code), [
        '2025',
        '2026',
      ]);
      expect(restored.termOptions.single.label, '短学期');
      expect(restored.selectedTerm, isNull);
    },
  );

  test('unsupported versions fail explicitly for every saved format', () {
    for (final decode in <Object Function(String)>[
      ScheduleSnapshotCodec.decode,
      ScheduleSettingsCodec.decode,
      TermCatalogCodec.decode,
    ]) {
      expect(() => decode('{"version":999}'), throwsA(isA<FormatException>()));
    }
  });

  test(
    'invalid saved model values produce format errors, not program errors',
    () {
      final encoded = ScheduleSnapshotCodec.encode(snapshot());
      for (final patch in <void Function(Map<String, Object?>)>[
        (data) => data['fetchedAt'] = '2026-02-31T04:30:12.345678Z',
        (data) =>
            (data['calendar'] as Map<String, Object?>)['firstWeekMonday'] =
                '2026-09-08',
        (data) =>
            (data['calendar'] as Map<String, Object?>)['firstWeekMonday'] =
                '2026-02-30',
        (data) =>
            ((data['entries'] as List<Object?>).first
                as Map<String, Object?>)['weeks'] = [
              0,
            ],
        (data) =>
            ((data['entries'] as List<Object?>).first
                    as Map<String, Object?>)['endPeriod'] =
                1,
        (data) =>
            ((data['entries'] as List<Object?>).first
                    as Map<String, Object?>)['weekday'] =
                9,
        (data) =>
            ((data['entries'] as List<Object?>).first
                    as Map<String, Object?>)['origin'] =
                'unrecognized',
        (data) =>
            ((data['entries'] as List<Object?>).first
                as Map<String, Object?>)['metadata'] = {
              'xf': 2.5,
            },
      ]) {
        final data = jsonDecode(encoded) as Map<String, Object?>;
        patch(data);
        expect(
          () => ScheduleSnapshotCodec.decode(jsonEncode(data)),
          throwsA(isA<FormatException>()),
        );
      }
    },
  );

  test('invalid local origin in saved preferences is rejected', () {
    final data = jsonDecode(
      ScheduleSettingsCodec.encode(
        ScheduleSettings(
          localEntries: [lesson(origin: ScheduleEntryOrigin.local)],
        ),
      ),
    ) as Map<String, Object?>;
    ((data['localEntries'] as List<Object?>).first
            as Map<String, Object?>)['origin'] =
        'imported';
    expect(
      () => ScheduleSettingsCodec.decode(jsonEncode(data)),
      throwsA(isA<FormatException>()),
    );
  });

  test('corrupt JSON diagnostics do not retain original saved content', () {
    try {
      ScheduleSnapshotCodec.decode('{"private":"not a real credential"');
      fail('Expected a format error.');
    } on FormatException catch (error) {
      expect(error.source, isNull);
      expect(error.toString(), isNot(contains('not a real credential')));
    }
  });
}
