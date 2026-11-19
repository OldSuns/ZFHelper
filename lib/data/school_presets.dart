import 'package:zf_core/zf_core.dart';

/// The school and campus explicitly configured for the LXY edition.
abstract final class GingkoSchoolPreset {
  static const name = '成都银杏酒店管理学院';
  static const loginAddress =
      'https://jwxt.gingkoc.edu.cn/xtgl/login_slogin.html';
  static const yibinCampus = '宜宾校区';

  static final _baseUri = recognizeSchoolAddress(loginAddress);

  static bool matches(Uri? baseUri) => baseUri == _baseUri;

  static final yibinTimes = PeriodTimePlan(
    periods: [
      for (final (index, (start, end)) in const [
        (8 * 60 + 30, 9 * 60 + 15),
        (9 * 60 + 20, 10 * 60 + 5),
        (10 * 60 + 20, 11 * 60 + 5),
        (11 * 60 + 10, 11 * 60 + 55),
        (12 * 60, 13 * 60),
        (13 * 60 + 10, 13 * 60 + 55),
        (14 * 60, 14 * 60 + 45),
        (14 * 60 + 50, 15 * 60 + 35),
        (15 * 60 + 50, 16 * 60 + 35),
        (16 * 60 + 40, 17 * 60 + 25),
        (18 * 60 + 20, 19 * 60 + 5),
        (19 * 60 + 10, 19 * 60 + 55),
        (20 * 60, 20 * 60 + 45),
      ].indexed)
        PeriodTime(
          number: index + 1,
          startMinutes: start,
          endMinutes: end,
          campus: yibinCampus,
        ),
    ],
    sections: [
      for (final (session, first, last) in const [
        (PeriodSession.morning, 1, 5),
        (PeriodSession.afternoon, 6, 10),
        (PeriodSession.evening, 11, 13),
      ])
        PeriodTimeSection(
          session: session,
          firstPeriod: first,
          lastPeriod: last,
          campus: yibinCampus,
        ),
    ],
  );
}
