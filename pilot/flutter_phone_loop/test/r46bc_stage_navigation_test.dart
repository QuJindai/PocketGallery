import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:pocketgallery_phone_pilot/lineage/lineage_models.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_store.dart';
import 'package:pocketgallery_phone_pilot/services/knowledge_engine.dart';
import 'package:pocketgallery_phone_pilot/ui/microscope/rag_lineage_dashboard_page.dart';
import 'package:pocketgallery_phone_pilot/ui/microscope/rag_stage.dart';

void main() {
  testWidgets('all ten trace stages open a truthful drill-down page',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    final store = LineageStore(database: db);
    await store.initialize();
    await store.putTrace(LineageTrace(
      traceId: 'tr-navigation',
      sessionId: 's-navigation',
      turnId: 't-navigation',
      queryText: '打开十阶段详情',
      requestedMode: 'auto',
      finalMode: 'knowledge',
      scopeJson: '{"type":"all"}',
      activeStrategyId: 'active.r45-body-hybrid',
      startedAt: DateTime.utc(2026, 8, 31, 8),
      completedAt: DateTime.utc(2026, 8, 31, 8, 0, 1),
      status: TraceStatus.complete,
      failureStage: null,
      failureCode: null,
    ));
    final engine = KnowledgeEngine(lineageStore: store);
    await tester.pumpWidget(MaterialApp(
      home: RagLineageDashboardPage(
        engine: engine,
        lineageStore: store,
        traceId: 'tr-navigation',
      ),
    ));
    await tester.pumpAndSettle();

    for (final stage in RagStage.values) {
      final button = find.byKey(
        ValueKey<String>('rag-stage-summary-${stage.number}'),
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey<String>(stage.pageKey)),
        findsOneWidget,
        reason: '${stage.number} ${stage.title}',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });
}
