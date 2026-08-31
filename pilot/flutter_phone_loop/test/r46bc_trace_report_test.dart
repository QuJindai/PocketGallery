import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:pocketgallery_phone_pilot/lineage/lineage_ids.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_models.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_store.dart';
import 'package:pocketgallery_phone_pilot/lineage/trace_report_exporter.dart';
import 'package:pocketgallery_phone_pilot/lineage/trace_snapshot.dart';

void main() {
  test('trace snapshot uses the persisted query vector and resolves all facts',
      () async {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    final store = LineageStore(database: db);
    await store.initialize();
    const traceId = 'tr-report';
    const strategyId = 'active.r45-body-hybrid';
    await store.putTrace(LineageTrace(
      traceId: traceId,
      sessionId: 's1',
      turnId: 't1',
      queryText: '真实查询',
      requestedMode: 'auto',
      finalMode: 'knowledge',
      scopeJson: '{"type":"all"}',
      activeStrategyId: strategyId,
      startedAt: DateTime.utc(2026, 8, 31, 7),
      completedAt: DateTime.utc(2026, 8, 31, 7, 0, 2),
      status: TraceStatus.complete,
      failureStage: null,
      failureCode: null,
    ));
    final queryEmbedding = LineageEmbedding.test(
      embeddingId: LineageIds.queryEmbeddingId(traceId),
      sourceKind: 'query',
      sourceId: traceId,
      chunkId: null,
      representation: EmbeddingRepresentation.query,
      vector: const <double>[0.6, 0.8],
      modelIdentity: 'EmbeddingGemma-test',
      taskMode: 'retrieval_query',
    );
    await store.putEmbedding(queryEmbedding);
    await store.appendEvent(TraceEventRecord(
      eventId: LineageIds.eventId(traceId, 1),
      traceId: traceId,
      seq: 1,
      stage: 'embedding',
      kind: 'embedding.query_completed',
      truthKind: TruthKind.real,
      lane: RetrievalLane.active,
      strategyId: strategyId,
      timestampUs: 1,
      durationUs: 400000,
      payloadJson: jsonEncode(<String, Object?>{
        'embeddingId': queryEmbedding.embeddingId,
        'access_token': 'must-never-export',
        'documentText': 'raw-private-document',
      }),
    ));

    final snapshot = await TraceSnapshot.load(store, traceId);

    expect(snapshot.queryEmbedding!.embeddingId, queryEmbedding.embeddingId);
    expect(snapshot.queryEmbedding!.vectorSha256, queryEmbedding.vectorSha256);
    expect(snapshot.events.single.durationUs, 400000);
  });

  test('redacted report is deterministic and excludes raw vectors and secrets',
      () async {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    final store = LineageStore(database: db);
    await store.initialize();
    const traceId = 'tr-redacted';
    await store.putTrace(LineageTrace(
      traceId: traceId,
      sessionId: 'session-private',
      turnId: 'turn-1',
      queryText: '诊断查询',
      requestedMode: 'auto',
      finalMode: 'knowledge',
      scopeJson: '{"type":"all"}',
      activeStrategyId: 'active.r45-body-hybrid',
      startedAt: DateTime.utc(2026, 8, 31, 7),
      completedAt: DateTime.utc(2026, 8, 31, 7, 0, 1),
      status: TraceStatus.complete,
      failureStage: null,
      failureCode: null,
    ));
    await store.putEmbedding(LineageEmbedding.test(
      embeddingId: LineageIds.queryEmbeddingId(traceId),
      sourceKind: 'query',
      sourceId: traceId,
      chunkId: null,
      representation: EmbeddingRepresentation.query,
      vector: const <double>[0.3, 0.4],
      modelIdentity: 'EmbeddingGemma-test',
      taskMode: 'retrieval_query',
    ));
    await store.appendEvent(TraceEventRecord(
      eventId: LineageIds.eventId(traceId, 1),
      traceId: traceId,
      seq: 1,
      stage: 'trace',
      kind: 'trace.started',
      truthKind: TruthKind.real,
      lane: RetrievalLane.active,
      strategyId: 'active.r45-body-hybrid',
      timestampUs: 1,
      durationUs: null,
      payloadJson:
          '{"authorization":"Bearer secret","rawText":"private body","safeCount":3}',
    ));
    final snapshot = await TraceSnapshot.load(store, traceId);

    final first = TraceReportExporter.encodeRedacted(snapshot);
    final second = TraceReportExporter.encodeRedacted(snapshot);
    final text = utf8.decode(first);
    final decoded = jsonDecode(text) as Map<String, dynamic>;

    expect(first, orderedEquals(second));
    expect(decoded['schema'], 'pocketgallery.r46.lineage-report.v1');
    expect(text, contains('active.r45-body-hybrid'));
    expect(text, contains('vectorSha256'));
    expect(text, isNot(contains('vectorF32')));
    expect(text, isNot(contains('must-never-export')));
    expect(text, isNot(contains('Bearer secret')));
    expect(text, isNot(contains('private body')));
    expect(text.toLowerCase(), isNot(contains('authorization')));
  });
}
