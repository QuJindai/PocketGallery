import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:pocketgallery_phone_pilot/lineage/lineage_ids.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_models.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_store.dart';
import 'package:pocketgallery_phone_pilot/lineage/runtime_lineage_recorder.dart';

CandidateRecord candidate(String traceId, int rank) => CandidateRecord(
      candidateId: LineageIds.candidateId(
        traceId,
        RuntimeLineageRecorder.activeStrategyId,
        'chunk-$rank',
      ),
      traceId: traceId,
      strategyId: RuntimeLineageRecorder.activeStrategyId,
      lane: RetrievalLane.active,
      chunkId: 'chunk-$rank',
      embeddingId: null,
      sourceChannels: 'fts5',
      ftsRank: rank,
      rawBm25: -rank.toDouble(),
      vectorRank: null,
      rawCosine: null,
      fusionRank: rank,
      fusionScore: 1 / rank,
      rerankRank: null,
      rerankScore: null,
      finalRank: rank,
      selectedForEvidence: rank <= 3,
      dropReason: rank <= 3 ? null : 'max_evidence',
    );

void main() {
  test('events are ordered and a failed trace keeps prior evidence', () async {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    final store = LineageStore(database: db);
    var tick = 0;
    final recorder = RuntimeLineageRecorder(
      store: store,
      clock: () => DateTime.utc(2026, 8, 29).add(
        Duration(microseconds: tick++),
      ),
    );

    final trace = await recorder.startTrace(
      sessionId: 'session-1',
      turnId: 'turn-1',
      queryText: '端侧模型如何测试',
      requestedMode: 'auto',
      scopeJson: '{"type":"all"}',
    );
    await recorder.event(
      traceId: trace.traceId,
      stage: 'fts',
      kind: 'fts.search_completed',
      payload: const {'hitCount': 3},
    );
    await recorder.failTrace(
      trace.traceId,
      stage: 'generation',
      error: StateError('authorization=secret-value'),
    );

    final events = await store.eventsForTrace(trace.traceId);
    expect(events.map((event) => event.seq), [1, 2, 3]);
    expect(events.map((event) => event.kind), [
      'trace.started',
      'fts.search_completed',
      'trace.failed',
    ]);
    expect(events.last.payloadJson, isNot(contains('secret-value')));
    final failed = await store.traceById(trace.traceId);
    expect(failed!.status, TraceStatus.failed);
    expect(failed.failureStage, 'generation');
    expect(failed.failureCode, 'STATE_ERROR');
  });

  test('candidate batches are capped per channel and cap metadata is recorded',
      () async {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    final store = LineageStore(database: db);
    final recorder = RuntimeLineageRecorder(
      store: store,
      maxCandidatesPerChannelStrategy: 50,
    );
    final trace = await recorder.startTrace(
      sessionId: 'session-2',
      turnId: 'turn-2',
      queryText: '候选池',
      requestedMode: 'knowledge',
      scopeJson: '{"type":"all"}',
    );

    await recorder.candidates(
      traceId: trace.traceId,
      records: [for (var i = 1; i <= 55; i++) candidate(trace.traceId, i)],
    );

    expect(await store.candidatesForTrace(trace.traceId), hasLength(50));
    final event = (await store.eventsForTrace(trace.traceId)).last;
    expect(event.kind, 'candidate.pool_built');
    final payload = jsonDecode(event.payloadJson) as Map<String, dynamic>;
    expect(payload['received'], 55);
    expect(payload['persisted'], 50);
    expect(payload['droppedByCap'], 5);
    expect(payload['capPerChannelStrategy'], 50);
  });

  test('default retention keeps 200 traces and never removes chunk embeddings',
      () async {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    final store = LineageStore(database: db);
    final recorder = RuntimeLineageRecorder(store: store);
    final bodyId = LineageIds.bodyEmbeddingId('persistent-chunk');
    await store.putEmbedding(LineageEmbedding.test(
      embeddingId: bodyId,
      sourceKind: 'chunk',
      sourceId: 'persistent-chunk',
      chunkId: 'persistent-chunk',
      representation: EmbeddingRepresentation.body,
      vector: const [0.8, 0.2],
      modelIdentity: 'EmbeddingGemma-test',
      taskMode: 'retrieval_document',
    ));

    for (var i = 0; i < 201; i++) {
      final trace = await recorder.startTrace(
        sessionId: 'retention',
        turnId: 'turn-$i',
        queryText: 'query-$i',
        requestedMode: 'auto',
        scopeJson: '{"type":"all"}',
      );
      await recorder.completeTrace(trace.traceId, finalMode: 'knowledge');
    }

    expect(await store.latestTraces(limit: 1000), hasLength(200));
    expect(
      await store.traceById(LineageIds.traceId('retention', 'turn-0')),
      isNull,
    );
    expect(await store.embeddingById(bodyId), isNotNull);
  });
}
