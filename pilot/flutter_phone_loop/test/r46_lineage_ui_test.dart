import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:pocketgallery_phone_pilot/lineage/lineage_models.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_store.dart';
import 'package:pocketgallery_phone_pilot/lineage/runtime_lineage_recorder.dart';
import 'package:pocketgallery_phone_pilot/services/knowledge_engine.dart';
import 'package:pocketgallery_phone_pilot/ui/microscope/rag_lineage_dashboard_page.dart';

void main() {
  test('generation summary exposes measured stream metrics and honest backend',
      () {
    const generation = GenerationStatsRecord(
      traceId: 'trace-ui-measured',
      strategyId: RuntimeLineageRecorder.activeStrategyId,
      lane: RetrievalLane.active,
      ttftMs: 125,
      generationMs: 425,
      outputTokens: 3,
      decodeTokensPerSecond: 10,
      backend: null,
      nativeSessionRebuilt: true,
      sessionResetReason: 'fresh_turn_context_bound',
    );

    expect(
      formatGenerationSummary(generation, citationCount: 1),
      'generation 425 ms · TTFT 125 ms · output 3 tokens · '
      'decode 10.0 tok/s · backend 未暴露 · citations 1',
    );
  });

  testWidgets('RAG Lineage renders captured timings and honest unknowns',
      (tester) async {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    final store = LineageStore(database: db);
    const traceId = 'trace-ui-1';
    const strategy = RuntimeLineageRecorder.activeStrategyId;
    await store.putTrace(LineageTrace(
      traceId: traceId,
      sessionId: 'session-ui',
      turnId: 'turn-ui',
      queryText: '向量检索如何工作？',
      requestedMode: 'auto',
      finalMode: 'knowledge',
      scopeJson: '{"type":"all"}',
      activeStrategyId: strategy,
      startedAt: DateTime.utc(2026, 8, 29, 8),
      completedAt: DateTime.utc(2026, 8, 29, 8, 0, 1),
      status: TraceStatus.complete,
      failureStage: null,
      failureCode: null,
    ));
    await store.appendEvent(TraceEventRecord(
      eventId: 'event-ui-1',
      traceId: traceId,
      seq: 1,
      stage: 'fts',
      kind: 'fts.search_completed',
      truthKind: TruthKind.real,
      lane: RetrievalLane.active,
      strategyId: strategy,
      timestampUs: 1,
      durationUs: 2100,
      payloadJson: '{"hitCount":2}',
    ));
    await store.putGenerationStats(const GenerationStatsRecord(
      traceId: traceId,
      strategyId: strategy,
      lane: RetrievalLane.active,
      ttftMs: null,
      generationMs: 47,
      outputTokens: null,
      decodeTokensPerSecond: null,
      backend: null,
      nativeSessionRebuilt: true,
      sessionResetReason: 'fresh_turn_context',
    ));

    final engine = KnowledgeEngine(lineageStore: store);
    await tester.pumpWidget(MaterialApp(
      home: RagLineageDashboardPage(
        engine: engine,
        lineageStore: store,
        traceId: traceId,
      ),
    ));
    await tester.pumpAndSettle();

    for (final label in <String>[
      '文档解析',
      '切片',
      'FTS5',
      'Embedding',
      '向量空间',
      '候选池',
      '融合/重排',
      '路由决策',
      '证据与上下文',
      '生成与引用',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.textContaining('2.1 ms'), findsWidgets);
    expect(find.textContaining('47 ms'), findsWidgets);
    expect(find.textContaining('TTFT 未捕获'), findsWidgets);
    expect(find.textContaining('backend 未暴露'), findsWidgets);
    expect(find.textContaining('0 ms'), findsNothing);
  });

  test('microscope teaches identities and is reachable from chat and knowledge',
      () async {
    final dashboard = await File(
      'lib/ui/microscope/rag_lineage_dashboard_page.dart',
    ).readAsString();
    final knowledge = await File('lib/ui/knowledge_page.dart').readAsString();
    final chat = await File('lib/ui/chat_page.dart').readAsString();

    for (final label in <String>[
      'Chunk ≠ Vector',
      'Chunk → Embedding',
      'REAL',
      'DERIVED',
      'ACTIVE',
      '未捕获',
      'backend 未暴露',
      'R4.6-B',
    ]) {
      expect(dashboard, contains(label), reason: label);
    }
    expect(knowledge, contains('RAG Lineage'));
    expect(knowledge, contains('RagLineageDashboardPage'));
    expect(chat, contains('lineageStore.traceById'));
    expect(chat, contains('RagLineageDashboardPage'));
    expect(chat, contains('RetrievalTracePage'),
        reason: 'legacy R4.1 traces remain readable as a fallback');
  });
}
