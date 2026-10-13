import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zf_core/zf_core.dart';
import 'package:zfhelper/ui/features/settings/views/jwxt_browser_page.dart';

void main() {
  testWidgets('不支持网页组件的平台会提示而不是崩溃', (tester) async {
    // Widget tests have no WebView platform implementation; linux is neither
    // Android nor Windows, so the page must degrade to a notice instead of
    // constructing the native view.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final profile = SchoolConnection.fromInput(
      name: '测试学校',
      address: 'https://jwxt.example.edu.cn',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: JwxtBrowserPage(profile: profile, cookies: const []),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('测试学校 · 教务网页'), findsOneWidget);
    expect(find.text('当前平台尚不支持应用内教务网页'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Must reset inside the body: framework invariants are checked before
    // tear-down callbacks run.
    debugDefaultTargetPlatformOverride = null;
  });
}
