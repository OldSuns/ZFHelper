import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zfhelper/ui/core/app_theme.dart';

void main() {
  group('AppTheme.courseColorAssignments', () {
    test('assigns every distinct name a unique color within the palette', () {
      final names = [for (var i = 0; i < 12; i++) '课程$i'];
      final assignments = AppTheme.courseColorAssignments(
        Brightness.light,
        names,
      );
      expect(assignments.length, 12);
      expect(assignments.values.toSet(), hasLength(12));
    });

    test('keeps one color per duplicated name', () {
      final assignments = AppTheme.courseColorAssignments(Brightness.dark, [
        '高数',
        '英语',
        '高数',
        '高数',
      ]);
      expect(assignments, hasLength(2));
      expect(assignments['高数'], isNot(equals(assignments['英语'])));
    });

    test('cycles the palette only after it is exhausted', () {
      final names = [for (var i = 0; i < 13; i++) '课程$i'];
      final assignments = AppTheme.courseColorAssignments(
        Brightness.light,
        names,
      );
      expect(assignments['课程12'], equals(assignments['课程0']));
      expect(assignments['课程12'], isNot(equals(assignments['课程1'])));
    });

    test('keeps hashed accents within the original eight colors', () {
      const original = [
        Color(0xFF8839EF),
        Color(0xFF1E66F5),
        Color(0xFF179299),
        Color(0xFFFE640B),
        Color(0xFFEA76CB),
        Color(0xFF40A02B),
        Color(0xFFD20F39),
        Color(0xFF7287FD),
      ];
      for (final key in ['event:提醒', 'event:考试', '高数']) {
        expect(
          original,
          contains(AppTheme.courseAccent(Brightness.light, key)),
        );
      }
    });

    test('is deterministic for the same name order in both brightnesses', () {
      final names = ['高数', '英语', '体育'];
      final first = AppTheme.courseColorAssignments(Brightness.light, names);
      final second = AppTheme.courseColorAssignments(Brightness.light, names);
      final dark = AppTheme.courseColorAssignments(Brightness.dark, names);
      expect(first, equals(second));
      expect(dark, hasLength(first.length));
      expect(dark['高数'], isNot(equals(first['高数'])));
    });
  });
}
