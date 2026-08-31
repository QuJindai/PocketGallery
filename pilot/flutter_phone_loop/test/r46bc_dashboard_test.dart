import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:pocketgallery_phone_pilot/lineage/lineage_models.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_store.dart';
import 'package:pocketgallery_phone_pilot/services/knowledge_engine.dart';
import 'package:pocketgallery_phone_pilot/ui/microscope/lineage_dashboard_visuals.dart';
import 'package:pocketgallery_phone_pilot/ui/microscope/rag_lineage_dashboard_page.dart';
import 'package:pocketgallery_phone_pilot/ui/microscope/rag_stage.dart';

Future<LineageStore> _store(Database db) async {
  final store = LineageStore(database: db);
  await store.initialize();
  await store.putTrace(LineageTrace(
    traceId: 'tr-dashboard',
    sessionId: 's-dashboard',
    turnId: 't-dashboard',
    queryText: '检查完整运行链路',
    requestedMode: 'auto',
    finalMode: 'knowledge',
    scopeJson: '{"type":"all"}',
    activeStrategyId: 'active.r45-body-hybrid',
    startedAt: DateTime.utc(2026, 8, 31, 8),
    completedAt: DateTime.utc(2026, 8, 31, 8, 0, 2),
    status: TraceStatus.complete,
    failureStage: null,
    failureCode: null,
  ));
  await store.appendEvent(const TraceEventRecord(
    eventId: 'evt-fts',
    traceId: 'tr-dashboard',
    seq: 1,
    stage: 'fts',
    kind: 'fts.search_completed',
    truthKind: TruthKind.real,
    lane: RetrievalLane.active,
    strategyId: 'active.r45-body-hybrid',
    timestampUs: 1,
    durationUs: 2500,
    payloadJson: '{"hitCount":2}',
  ));
  await store.appendEvent(const TraceEventRecord(
    eventId: 'evt-router',
    traceId: 'tr-dashboard',
    seq: 2,
    stage: 'router',
    kind: 'router.evaluated',
    truthKind: TruthKind.real,
    lane: RetrievalLane.active,
    strategyId: 'active.r45-body-hybrid',
    timestampUs: 2,
    durationUs: null,
    payloadJson: '{"reason":"lexical_hit"}',
  ));
  return store;
}

void main() {
  test('waterfall preserves unknown duration instead of manufacturing zero',
      () {
    const events = <TraceEventRecord>[
      TraceEventRecord(
        eventId: 'e1',
        traceId: 'tr',
        seq: 1,
        stage: 'fts',
        kind: 'fts.search_completed',
        truthKind: TruthKind.real,
        lane: RetrievalLane.active,
        strategyId: 'active',
        timestampUs: 1,
        durationUs: 2500,
        payloadJson: '{}',
      ),
      TraceEventRecord(
        eventId: 'e2',
        traceId: 'tr',
        seq: 2,
        stage: 'router',
        kind: 'router.evaluated',
        truthKind: TruthKind.real,
        lane: RetrievalLane.active,
        strategyId: 'active',
        timestampUs: 2,
        durationUs: null,
        payloadJson: '{}',
      ),
    ];

    final waterfall = TraceWaterfallModel.fromEvents(events);

    expect(waterfall.totalKnownDurationUs, 2500);
    expect(waterfall.entries.first.durationLabel, '2.5 ms');
    expect(waterfall.entries.last.durationUs, isNull);
    expect(waterfall.entries.last.durationLabel, '未捕获');
    expect(waterfall.entries.last.fractionOfKnownDuration, isNull);
  });

  testWidgets('phone dashboard exposes a horizontal ten-stage strip',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    final store = await _store(db);
    final engine = KnowledgeEngine(lineageStore: store);

    await tester.pumpWidget(MaterialApp(
      home: RagLineageDashboardPage(
        engine: engine,
        lineageStore: store,
        traceId: 'tr-dashboard',
      ),
    ));
    await tester.pumpAndSettle();

    final strip = find.byKey(const ValueKey<String>('rag-stage-strip'));
    expect(strip, findsOneWidget);
    final scroll = tester.widget<SingleChildScrollView>(strip);
    expect(scroll.scrollDirection, Axis.horizontal);
    expect(RagStage.values, hasLength(10));
    for (final stage in RagStage.values) {
      expect(
        find.byKey(ValueKey<String>('rag-stage-${stage.number}')),
        findsOneWidget,
        reason: stage.title,
      );
    }
    expect(find.text('Trace 时间瀑布'), findsOneWidget);
    expect(find.text('Lineage 血缘图'), findsOneWidget);
    expect(find.textContaining('未捕获'), findsWidgets);
    expect(find.textContaining('0 ms'), findsNothing);
  });
}
