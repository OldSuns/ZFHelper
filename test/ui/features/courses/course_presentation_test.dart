import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zf_core/src/selection/zhengfang_selection_parser.dart';
import 'package:zf_core/zf_core.dart';
import 'package:zfhelper/ui/features/courses/views/course_list_tile.dart';

// Constructed from the reference project's sksj/jxdd line-break fields.
void main() {
  final round = SelectionRound(
    controlKey: 'xkkz_id',
    controlId: 'round',
    categoryCode: '01',
  );
  final course = CourseOffering(
    roundKey: round.key,
    courseId: 'course-001',
    name: '算法',
    credit: '2.5',
    capacity: 120,
    selected: 115,
    location: '课程级地点',
  );
  const firstTime = '1-16周 星期一 第1-2节';
  const secondTime = '1-16周 星期三 第3-4节';

  testWidgets('course summary has room beside short names and reflows', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    for (final width in [800.0, 375.0]) {
      tester.view.physicalSize = Size(width, 600);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(
                textScaler: TextScaler.linear(width < 500 ? 2 : 1),
              ),
              child: CourseListTile(
                course: course,
                isSelected: false,
                compact: true,
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      if (width > 500) {
        final title = tester.getRect(find.text(course.name));
        final summary = tester.getRect(find.textContaining('已选 115/120'));
        expect(width - summary.left, greaterThan(title.width));
      }
    }
  });

  testWidgets('section times stay beside their corresponding locations', (
    tester,
  ) async {
    final context = SelectionContext(
      rounds: [round],
      fetchedAt: DateTime(2026),
      pageUri: Uri.parse('https://school.example.test/'),
    );
    for (final (location, expected) in [
      (
        '教学楼 A101<br>实验楼 B202<br>',
        '时间：$firstTime\n地点：教学楼 A101\n\n时间：$secondTime\n地点：实验楼 B202',
      ),
      (
        '<br>实验楼 B202',
        '时间：$firstTime\n地点：学校未提供\n\n时间：$secondTime\n地点：实验楼 B202',
      ),
      (null, '时间：$firstTime\n地点：学校未提供\n\n时间：$secondTime\n地点：学校未提供'),
      (
        '教学楼 A101',
        '学校提供的时间与地点段数不一致，无法确定对应关系\n'
            '时间：$firstTime\n时间：$secondTime\n地点：教学楼 A101',
      ),
      (
        '教学楼 A101<br>实验楼 B202<br>体育馆 C303<br>',
        '学校提供的时间与地点段数不一致，无法确定对应关系\n'
            '时间：$firstTime\n时间：$secondTime\n'
            '地点：教学楼 A101\n地点：实验楼 B202\n地点：体育馆 C303',
      ),
    ]) {
      final sections = const ZhengfangSelectionParser().parseSections(
        jsonEncode([
          {
            'jxb_id': 'section',
            'sksj': '$firstTime<br/>$secondTime<br/>',
            'jxdd': location,
          },
        ]),
        context: context,
        course: course,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RadioGroup<String>(
              groupValue: null,
              onChanged: (_) {},
              child: CourseSectionTile(
                section: sections.single,
                enabled: true,
                selected: false,
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining(expected), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
