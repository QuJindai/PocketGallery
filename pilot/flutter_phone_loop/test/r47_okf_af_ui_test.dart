import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketgallery_phone_pilot/services/knowledge_engine.dart';
import 'package:pocketgallery_phone_pilot/ui/microscope/okf_af_benchmark_page.dart';

void main() {
  testWidgets('A-F lab exposes six same-model lanes and aggregate actions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: OkfAfBenchmarkPage(engine: KnowledgeEngine())),
    );

    expect(find.byKey(const ValueKey<String>('okf-af-benchmark-page')), findsOneWidget);
    expect(find.textContaining('同一模型'), findsWidgets);
    expect(find.byKey(const ValueKey<String>('okf-af-run-current')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('okf-af-run-full')), findsOneWidget);

    for (final code in <String>['A', 'B', 'C', 'D', 'E', 'F']) {
      final finder = find.byKey(ValueKey<String>('okf-af-run-$code'));
      await tester.scrollUntilVisible(finder, 260);
      expect(finder, findsOneWidget);
    }
  });
}
