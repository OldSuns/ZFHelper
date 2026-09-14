import 'package:flutter_test/flutter_test.dart';
import 'package:zf_core/src/grades/zhengfang_grade_parser.dart';
import 'package:zfhelper/data/storage/grade_library_codec.dart';
import 'package:zfhelper/data/storage/grade_store.dart';
import 'package:zfhelper/ui/features/grades/view_models/grades_view_model.dart';

import '../../../support/grade_fakes.dart';

// Constructed protocol fields also represent the terms stored by version 1.
void main() {
  test(
    'term aliases share one filter and summary without changing raw terms',
    () async {
      final fields = [
        {'xnm': '2025', 'xqm': '12'},
        {'xnm': '2025', 'xq': '2'},
        {'xnmc': '2025–2026', 'xqmc': '第二学期'},
        {'xnm': '2025', 'xq': '1'},
        {'xnm': '2025', 'xq': '3'},
      ];
      final records = const ZhengfangGradeParser().parseRecords([
        for (final (index, term) in fields.indexed)
          {...term, 'kcmc': '课程 $index', 'xf': '2', 'jd': '3'},
      ]);
      final source = TestGradeSource();
      final account = gradeAccount();
      final store = TestGradeStore(
        library: GradeLibrary(
          accounts: [
            StoredGradeAccount(
              account: account,
              snapshot: gradeSnapshot(records: records),
              selectedTermKey: records.last.term!.key,
            ),
          ],
          selectedAccount: account.scope,
        ),
      );
      final repository = testGradeRepository(store: store, source: source);
      await repository.initialize();
      final model = GradesViewModel(repository: repository);
      addTearDown(repository.dispose);
      addTearDown(source.dispose);
      addTearDown(model.dispose);

      expect(model.terms, hasLength(3));
      expect(model.selectedTermKey, 'grade-term|2025|16');
      expect(model.visibleRecords, [records.last]);
      final term = model.terms.singleWhere((term) => term.termCode == '12');
      expect(term.label, '2025–2026 学年 第二学期');
      expect(await model.selectTerm(term.key), isTrue);
      expect(model.visibleRecords, records.take(3));
      expect(model.summary.recordCount, 3);
      expect(model.summary.totalCredits, 6);
      expect(model.summary.weightedGradePoint, 3);
      expect(
        gradeSnapshot(records: [records.last])
            .resolveTermKey(records[3].termKey),
        isNull,
      );
      final restored = GradeLibraryCodec.decode(
        GradeLibraryCodec.encode(store.library),
      );
      expect(restored.accounts.single.selectedTermKey, term.key);
      expect(
        restored.accounts.single.snapshot!.records[2].term!.termCode,
        '第二学期',
      );
      expect(source.requests, 0);
    },
  );
}
