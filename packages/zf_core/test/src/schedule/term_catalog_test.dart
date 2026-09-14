import 'package:test/test.dart';
import 'package:zf_core/src/schedule/academic_term.dart';
import 'package:zf_core/src/schedule/schedule_parse_exception.dart';
import 'package:zf_core/src/schedule/zhengfang_schedule_parser.dart';

void main() {
  const parser = ZhengfangScheduleParser();

  test(
    'manual school terms use explicit years and reference semester codes',
    () {
      expect(
        [
          for (final semester in ZhengfangSemester.values)
            AcademicTerm.zhengfang(
              startYear: '2025',
              semester: semester,
            ).termCode,
        ],
        ['3', '12', '16'],
      );
      final chosen = AcademicTerm.zhengfang(
        startYear: '2025',
        semester: ZhengfangSemester.second,
      );
      expect(chosen.yearCode, '2025');
      expect(chosen.label, '2025–2026 学年 第二学期');
      expect(
        () => AcademicTerm.zhengfang(
          startYear: '',
          semester: ZhengfangSemester.first,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'retains school codes and selector labels without a Cartesian catalog',
    () {
      final catalog = parser.parseTermCatalog('''
      <select name="xnm">
        <option value="2025">2025–2026 学年</option>
        <option selected value="2026">2026–2027 学年</option>
      </select>
      <select name="xqm">
        <option value="3">秋季学期</option>
        <option selected value="12">春季学期</option>
        <option value="16">小学期</option>
      </select>
    ''');
      expect(catalog.yearOptions.map((option) => option.code), [
        '2025',
        '2026',
      ]);
      expect(catalog.termOptions.map((option) => option.code), [
        '3',
        '12',
        '16',
      ]);
      expect(catalog.terms, hasLength(1));
      expect(catalog.selectedTerm!.yearCode, '2026');
      expect(catalog.selectedTerm!.termCode, '12');
      expect(catalog.selectedTerm!.label, '2026–2027 学年 春季学期');
    },
  );

  test(
    'keeps unknown term codes and never derives the current term from month',
    () {
      final catalog = parser.parseTermCatalog('''
      <select name="xnm"><option selected value="2020-A">旧学年</option></select>
      <select name="xqm"><option selected value="S/04">医学短学期</option></select>
    ''');
      expect(catalog.selectedTerm!.yearCode, '2020-A');
      expect(catalog.selectedTerm!.termCode, 'S/04');
    },
  );

  test('honors the browser default and a selected empty placeholder', () {
    final defaultSelection = parser.parseTermCatalog('''
      <select id="xnm"><option value="2024">2024</option><option value="2025">2025</option></select>
      <select id="xqm"><option value="12">第二学期</option><option value="3">第一学期</option></select>
    ''');
    expect(defaultSelection.selectedTerm!.yearCode, '2024');
    expect(defaultSelection.selectedTerm!.termCode, '12');
    final pending = parser.parseTermCatalog('''
      <select name="xnm"><option value="" selected>请选择学年</option><option value="2025">2025</option></select>
      <select name="xqm"><option value="3">第一学期</option></select>
    ''');
    expect(pending.selectedTerm, isNull);
    expect(pending.terms, isEmpty);
    expect(pending.yearOptions.single.code, '2025');
  });

  test(
    'supports explicit paired options without guessing semester conversion',
    () {
      final catalog = parser.parseTermCatalog('''
      <select name="terms">
        <option data-xnm="2025" data-xqm="summer" value="opaque" selected>2025 暑期</option>
        <option data-xnm="2026" data-xqm="fall" value="opaque-2">2026 秋季</option>
      </select>
    ''');
      expect(catalog.terms.map((term) => term.termCode), ['summer', 'fall']);
      expect(catalog.selectedTerm!.yearCode, '2025');
    },
  );

  test('reads server-selected hidden values and excludes disabled options', () {
    final hidden = parser.parseTermCatalog('''
      <input name="xnm" type="hidden" value="2026" data-label="2026 学年">
      <input name="xqm" type="hidden" value="3" data-label="秋季">
    ''');
    expect(hidden.selectedTerm!.label, '2026 学年 秋季');
    final catalog = parser.parseTermCatalog('''
      <select name="xnm"><option value="2025" disabled>2025</option><option value="2026" selected>2026</option></select>
      <select name="xqm"><optgroup disabled><option value="12">春季</option></optgroup><option value="3" selected>秋季</option></select>
    ''');
    expect(catalog.yearOptions.map((option) => option.code), ['2026']);
    expect(catalog.termOptions.map((option) => option.code), ['3']);
  });

  test('a login or error page is not an empty term catalog', () {
    for (final source in [
      '<h1>学校系统错误</h1>',
      '<input type="password" name="mm">',
    ]) {
      expect(
        () => parser.parseTermCatalog(source),
        throwsA(isA<ScheduleParseException>()),
      );
    }
  });

  test('term identity is independent of display labels and key delimiters', () {
    final first = AcademicTerm(
      yearCode: '2026',
      termCode: 'a|b',
      label: 'Old label',
    );
    final renamed = AcademicTerm(
      yearCode: '2026',
      termCode: 'a|b',
      label: 'New label',
    );
    final different = AcademicTerm(
      yearCode: '2026|a',
      termCode: 'b',
      label: 'Other',
    );
    expect(first, renamed);
    expect(first.hashCode, renamed.hashCode);
    expect(first.key, isNot(different.key));
  });
}
