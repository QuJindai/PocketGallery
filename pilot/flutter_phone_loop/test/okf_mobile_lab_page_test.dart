import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketgallery_phone_pilot/services/knowledge_engine.dart';
import 'package:pocketgallery_phone_pilot/ui/microscope/okf_mobile_lab_page.dart';

void main() {
  testWidgets('OKF mobile lab exposes six local-model comparison lanes', (
    tester,
  ) async {
    final engine = KnowledgeEngine();
    await tester.pumpWidget(
      MaterialApp(home: OkfMobileLabPage(engine: engine)),
    );

    expect(find.byKey(const ValueKey<String>('okf-mobile-lab-page')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('okf-run-all')), findsOneWidget);
    expect(find.textContaining('单变量验证'), findsOneWidget);

    for (final code in <String>['A', 'B', 'C', 'D', 'E', 'F']) {
      final finder = find.byKey(ValueKey<String>('okf-run-$code'));
      await tester.scrollUntilVisible(finder, 280);
      expect(finder, findsOneWidget);
    }
    expect(find.textContaining('FULL OKF'), findsOneWidget);
  });
}
