import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:pocketgallery_phone_pilot/experiments/representation_builder.dart';
import 'package:pocketgallery_phone_pilot/experiments/retrieval_experiment_engine.dart';
import 'package:pocketgallery_phone_pilot/experiments/retrieval_strategy.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_ids.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_models.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_store.dart';
import 'package:pocketgallery_phone_pilot/retrieval/query_embedding_runtime.dart';
import 'package:pocketgallery_phone_pilot/services/lexical_fts_store.dart';
import 'package:pocketgallery_phone_pilot/ui/microscope/retrieval_experiment_center_page.dart';

class _NoopGenerator implements EmbeddingGenerator {
  @override
  Future<List<double>> generateDocument(String text) async =>
      const <double>[1, 0];

  @override
  Future<List<double>> generateQuery(String text) =>
      throw StateError('center must not generate a query vector');
}

Future<LineageStore> _putTrace(Database db, {required bool withQuery}) async {
  final store = LineageStore(database: db);
  await store.initialize();
  await store.putTrace(LineageTrace(
    traceId: 'tr-center',
    sessionId: 's1',
    turnId: 't1',
    queryText: '检查实验中心',
    requestedMode: 'auto',
    finalMode: 'knowledge',
    scopeJson: '{"type":"all"}',
    activeStrategyId: RetrievalStrategies.activeControl.id,
    startedAt: DateTime.utc(2026, 8, 31),
    completedAt: DateTime.utc(2026, 8, 31, 0, 0, 1),
    status: TraceStatus.complete,
    failureStage: null,
    failureCode: null,
  ));
  if (withQuery) {
    await store.putEmbedding(LineageEmbedding.test(
      embeddingId: LineageIds.queryEmbeddingId('tr-center'),
      sourceKind: 'query',
      sourceId: 'tr-center',
      chunkId: null,
      representation: EmbeddingRepresentation.query,
      vector: const <double>[1, 0],
      modelIdentity: 'test',
      taskMode: 'retrieval_query',
    ));
  }
  return store;
}

RetrievalExperimentEngine _engine(
  LineageStore store,
  LexicalFtsStore lexical,
) =>
    RetrievalExperimentEngine(
      store: store,
      lexicalStore: lexical,
      representationBuilder: RepresentationBuilder(
        store: store,
        lexicalStore: lexical,
        generator: _NoopGenerator(),
        modelIdentity: 'test',
      ),
    );

void main() {
  testWidgets('experiment runs are disabled without exact query embedding',
      (tester) async {
    final lineageDb = sqlite3.openInMemory();
    final lexicalDb = sqlite3.openInMemory();
    addTearDown(lineageDb.close);
    addTearDown(lexicalDb.close);
    final store = await _putTrace(lineageDb, withQuery: false);
    final lexical = LexicalFtsStore(database: lexicalDb);
    await lexical.initialize();

    await tester.pumpWidget(MaterialApp(
      home: RetrievalExperimentCenterPage(
        store: store,
        experimentEngine: _engine(store, lexical),
        traceId: 'tr-center',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('ACTIVE Control'), findsOneWidget);
    expect(find.textContaining('缺少精确 Query Embedding'), findsOneWidget);
    for (final strategy in RetrievalStrategies.all.where((item) => item.onDemand)) {
      final finder = find.byKey(
        ValueKey<String>('experiment-run-${strategy.id}'),
      );
      expect(finder, findsOneWidget);
      expect(tester.widget<ButtonStyleButton>(finder).onPressed, isNull);
    }
  });

  testWidgets('center exposes persisted progress failure and retry action',
      (tester) async {
    final lineageDb = sqlite3.openInMemory();
    final lexicalDb = sqlite3.openInMemory();
    addTearDown(lineageDb.close);
    addTearDown(lexicalDb.close);
    final store = await _putTrace(lineageDb, withQuery: true);
    final lexical = LexicalFtsStore(database: lexicalDb);
    await lexical.initialize();
    final strategy = RetrievalStrategies.headingBodyMultivector;
    await store.putBuildJob(BuildJobRecord(
      jobId: LineageIds.buildJobId('d1', strategy.id),
      jobType: 'heading-build',
      strategyId: strategy.id,
      documentId: 'd1',
      status: BuildJobStatus.failed,
      totalItems: 2,
      completedItems: 1,
      checkpointJson: '{"completedEmbeddingIds":["emb-1"]}',
      currentSource: 'sec-2',
      failureCode: 'REPRESENTATION_BUILD_FAILED',
      failureDetail: 'fixture build interruption',
      createdAt: DateTime.utc(2026, 8, 31),
      updatedAt: DateTime.utc(2026, 8, 31, 0, 0, 1),
    ));
    await store.putExperimentRun(ExperimentRunRecord(
      experimentRunId: 'run-failed',
      traceId: 'tr-center',
      strategyId: strategy.id,
      lane: RetrievalLane.shadow,
      status: ExperimentRunStatus.failed,
      startedAt: DateTime.utc(2026, 8, 31),
      completedAt: DateTime.utc(2026, 8, 31, 0, 0, 2),
      completedItems: 1,
      totalItems: 2,
      metricJson: null,
      failureCode: 'SHADOW_EXECUTION_FAILED',
      failureDetail: 'fixture shadow failure',
    ));

    await tester.pumpWidget(MaterialApp(
      home: RetrievalExperimentCenterPage(
        store: store,
        experimentEngine: _engine(store, lexical),
        traceId: 'tr-center',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('1/2'), findsWidgets);
    expect(find.textContaining('SHADOW FAILED'), findsOneWidget);
    expect(find.textContaining('fixture shadow failure'), findsOneWidget);
    expect(find.textContaining('fixture build interruption'), findsOneWidget);
    final retry = find.byKey(
      ValueKey<String>('experiment-run-${strategy.id}'),
    );
    expect(tester.widget<ButtonStyleButton>(retry).onPressed, isNotNull);
    expect(find.textContaining('自动提升'), findsNothing);
    expect(find.textContaining('需用户明确批准'), findsOneWidget);
  });

  testWidgets('requested trace remains selectable beyond the latest 30',
      (tester) async {
    final lineageDb = sqlite3.openInMemory();
    final lexicalDb = sqlite3.openInMemory();
    addTearDown(lineageDb.close);
    addTearDown(lexicalDb.close);
    final store = await _putTrace(lineageDb, withQuery: true);
    final lexical = LexicalFtsStore(database: lexicalDb);
    await lexical.initialize();
    for (var index = 0; index < 31; index++) {
      final startedAt = DateTime.utc(2026, 8, 31, 1, index);
      await store.putTrace(LineageTrace(
        traceId: 'tr-newer-$index',
        sessionId: 's-newer-$index',
        turnId: 't-newer-$index',
        queryText: 'newer query $index',
        requestedMode: 'auto',
        finalMode: 'knowledge',
        scopeJson: '{"type":"all"}',
        activeStrategyId: RetrievalStrategies.activeControl.id,
        startedAt: startedAt,
        completedAt: startedAt.add(const Duration(seconds: 1)),
        status: TraceStatus.complete,
        failureStage: null,
        failureCode: null,
      ));
    }

    await tester.pumpWidget(MaterialApp(
      home: RetrievalExperimentCenterPage(
        store: store,
        experimentEngine: _engine(store, lexical),
        traceId: 'tr-center',
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('检查实验中心 · complete'), findsOneWidget);
  });
}
