import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zf_core/zf_core.dart';
import 'package:zfhelper/data/storage/academic_account.dart';
import 'package:zfhelper/data/storage/grade_store.dart';
import 'package:zfhelper/ui/core/app_theme.dart';
import 'package:zfhelper/ui/features/grades/view_models/grades_view_model.dart';
import 'package:zfhelper/ui/features/grades/views/grade_record_table.dart';
import 'package:zfhelper/ui/features/grades/views/grades_page.dart';

import '../../../support/grade_fakes.dart';

void main() {
  testWidgets('saved grades support term search and school details offline', (
    tester,
  ) async {
    _smallWindow(tester);
    final account = gradeAccount();
    final term = gradeTerm(semester: ZhengfangSemester.second);
    final source = TestGradeSource();
    final store = TestGradeStore(
      library: GradeLibrary(
        selectedAccount: account.scope,
        accounts: [
          StoredGradeAccount(
            account: account,
            snapshot: gradeSnapshot(
              records: [
                ...gradeSnapshot().records,
                GradeRecord(
                  id: 'practice',
                  name: '临床实践',
                  term: term,
                  score: '合格',
                  credits: '2',
                  courseCode: 'PRACTICE-2026',
                  teacher: '陈老师',
                  details: const {'平时成绩': '优秀', '期末成绩': '合格'},
                ),
              ],
            ),
          ),
        ],
      ),
    );
    await _withGrades(
      tester,
      store: store,
      source: source,
      body: (model) async {
        expect(find.text('本机保存'), findsOneWidget);
        expect(source.requests, 0);
        await _tap(tester, find.text('全部学期'));
        await tester.pumpAndSettle();
        await _tap(tester, find.text(term.label).last);
        await tester.pumpAndSettle();
        expect(model.selectedTermKey, 'grade-term|2025|12');
        expect(find.text('高等数学'), findsNothing);
        await tester.enterText(
          find.byKey(const ValueKey('grades-search')),
          'PRACTICE-2026',
        );
        await tester.pumpAndSettle();
        expect(find.text('临床实践'), findsOneWidget);
        await _tap(tester, find.text('临床实践'));
        await tester.pumpAndSettle();
        expect(find.text('成绩详情'), findsOneWidget);
        final details = find.byKey(const ValueKey('grade-details-scroll'));
        expect(
          find.descendant(of: details, matching: find.text('PRACTICE-2026')),
          findsOneWidget,
        );
        await tester.drag(details, const Offset(0, -380));
        await tester.pumpAndSettle();
        expect(find.text('平时成绩'), findsOneWidget);
        expect(find.text('优秀'), findsOneWidget);
        await _tap(tester, find.byTooltip('关闭成绩详情'));
        tester.view.physicalSize = const Size(1366, 768);
        await tester.pumpAndSettle();
        expect(find.byType(GradeRecordTable), findsOneWidget);
        expect(
          find.descendant(of: details, matching: find.text('PRACTICE-2026')),
          findsOneWidget,
        );
        tester.view.physicalSize = const Size(900, 640);
        await tester.pumpAndSettle();
        expect(find.byType(GradeRecordTable), findsOneWidget);
        expect(
          find.byKey(const ValueKey('grade-details-scroll')),
          findsNothing,
        );
        tester.view.physicalSize = const Size(375, 812);
        await tester.pumpAndSettle();
        expect(find.text('临床实践'), findsOneWidget);
        expect(source.requests, 0);
        expect(tester.takeException(), isNull);
      },
    );
  });

  testWidgets('query is explicit and failed refresh keeps the saved grades', (
    tester,
  ) async {
    _smallWindow(tester);
    final source = TestGradeSource(account: gradeAccount())
      ..onRead = () async => gradeSnapshot();
    final store = TestGradeStore();
    await _withGrades(
      tester,
      store: store,
      source: source,
      body: (model) async {
        expect(source.requests, 0);
        expect(find.text('查询成绩'), findsOneWidget);
        await _tap(tester, find.text('查询成绩'));
        await tester.pumpAndSettle();
        expect(source.requests, 1);
        expect(find.text('高等数学'), findsOneWidget);
        expect(store.library.accounts.single.snapshot, isNotNull);
        final saved = model.snapshot;
        source.onRead = () async =>
            throw const LoginFailure(LoginFailureCode.network, '无法连接学校教务系统');
        await _tap(tester, find.byTooltip('更新成绩'));
        await tester.pumpAndSettle();
        expect(find.textContaining('无法连接学校教务系统'), findsOneWidget);
        expect(find.textContaining('仍显示上次保存的成绩'), findsOneWidget);
        expect(find.text('高等数学'), findsOneWidget);
        expect(model.snapshot, same(saved));
        expect(find.text('学校暂无已公布成绩'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });

  testWidgets(
    'offline account switching and cache confirmation fit large text',
    (tester) async {
      _smallWindow(tester);
      final first = gradeAccount();
      final second = AcademicAccountRecord(
        scope: const AccountScope(
          schoolId: 'https://another.example/jwglxt/',
          accountId: 'another-student',
        ),
        schoolName: '另一所大学',
        accountName: '另一位学生',
        loginName: 'another-student',
      );
      final store = TestGradeStore(
        library: GradeLibrary(
          selectedAccount: first.scope,
          accounts: [
            StoredGradeAccount(account: first, snapshot: gradeSnapshot()),
            StoredGradeAccount(
              account: second,
              snapshot: gradeSnapshot(
                records: [
                  GradeRecord(
                    id: 'another-course',
                    name: '另一账号的基础实验课程',
                    score: '免修',
                  ),
                ],
              ),
            ),
          ],
        ),
      );
      final source = TestGradeSource();
      await _withGrades(
        tester,
        store: store,
        source: source,
        textScale: 2,
        brightness: Brightness.dark,
        body: (model) async {
          await _tap(tester, find.byTooltip('成绩菜单'));
          await tester.pumpAndSettle();
          await _tap(tester, find.text('本机保存的成绩'));
          await tester.pumpAndSettle();
          await _tap(tester, find.text('另一所大学'));
          await tester.pumpAndSettle();
          expect(model.account!.account.scope, second.scope);
          expect(find.textContaining('另一所大学 · 另一位学生'), findsOneWidget);
          expect(find.text('高等数学'), findsNothing);

          Future<void> openClearDialog() async {
            await _tap(tester, find.byTooltip('成绩菜单'));
            await tester.pumpAndSettle();
            await _tap(tester, find.text('清除本机成绩'));
            await tester.pumpAndSettle();
            expect(find.text('清除本机成绩？'), findsOneWidget);
          }

          await openClearDialog();
          await _tap(tester, find.text('取消'));
          await tester.pumpAndSettle();
          expect(model.snapshot, isNotNull);
          await openClearDialog();
          await _tap(tester, find.text('清除本机成绩'));
          await tester.pumpAndSettle();
          expect(model.snapshot, isNull);
          expect(
            store.library.accounts
                .singleWhere((account) => account.account.scope == first.scope)
                .snapshot,
            isNotNull,
          );
          expect(source.requests, 0);
          expect(tester.takeException(), isNull);
        },
      );
    },
  );
}

void _smallWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  // Repository setup, actions, and disposal share the real event queue;
  // WidgetTester.pump controls frame timing separately.
  await tester.runAsync(() => tester.tap(finder));
}

Future<void> _withGrades(
  WidgetTester tester, {
  required TestGradeStore store,
  required TestGradeSource source,
  required Future<void> Function(GradesViewModel) body,
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) async {
  final repository = (await tester.runAsync(() async {
    final repository = testGradeRepository(store: store, source: source);
    await repository.initialize();
    return repository;
  }))!;
  final model = GradesViewModel(repository: repository);
  try {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: GradesPage(
            viewModel: model,
            schoolName: '当前登录学校',
            onOpenSettings: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await body(model);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
    await tester.pump();
    await tester.runAsync(() async {
      await repository.dispose();
      await source.dispose();
    });
  }
}
