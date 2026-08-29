import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_ids.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_models.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_store.dart';

void main() {
  test('chunk and embedding identities are distinct and one chunk can own many embeddings', () async {
    final db = sqlite3.openInMemory();
    final store = LineageStore(database: db);
    await store.initialize();

    const chunkId = 'doc:7';
    final bodyId = LineageIds.embeddingId(
      sourceKind: 'chunk',
      sourceId: chunkId,
      representation: EmbeddingRepresentation.body,
    );
    final headingId = LineageIds.embeddingId(
      sourceKind: 'chunk',
      sourceId: chunkId,
      representation: EmbeddingRepresentation.heading,
    );
    expect(bodyId, isNot(chunkId));
    expect(headingId, isNot(chunkId));
    expect(bodyId, isNot(headingId));

    await store.putEmbedding(LineageEmbedding.test(
      embeddingId: bodyId,
      sourceKind: 'chunk',
      sourceId: chunkId,
      chunkId: chunkId,
      representation: EmbeddingRepresentation.body,
      vector: const [1.0, 0.0],
      modelIdentity: 'EmbeddingGemma-test',
      taskMode: 'retrieval_document',
    ));
    await store.putEmbedding(LineageEmbedding.test(
      embeddingId: headingId,
      sourceKind: 'chunk',
      sourceId: chunkId,
      chunkId: chunkId,
      representation: EmbeddingRepresentation.heading,
      vector: const [0.0, 1.0],
      modelIdentity: 'EmbeddingGemma-test',
      taskMode: 'retrieval_document',
    ));
    expect(await store.embeddingsForChunk(chunkId), hasLength(2));
    db.close();
  });

  test('query embedding is first class without a chunk identity', () async {
    final db = sqlite3.openInMemory();
    final store = LineageStore(database: db);
    await store.initialize();
    final id = LineageIds.queryEmbeddingId('trace-1');
    await store.putEmbedding(LineageEmbedding.test(
      embeddingId: id,
      sourceKind: 'query',
      sourceId: 'trace-1',
      chunkId: null,
      representation: EmbeddingRepresentation.query,
      vector: const [0.2, 0.8],
      modelIdentity: 'EmbeddingGemma-test',
      taskMode: 'retrieval_query',
    ));
    final row = await store.embeddingById(id);
    expect(row!.chunkId, isNull);
    expect(row.representation, EmbeddingRepresentation.query);
    expect(row.vector, hasLength(2));
    db.close();
  });

  test('lineage schema contains resumable build state and strategy scoped decisions', () async {
    final db = sqlite3.openInMemory();
    final store = LineageStore(database: db);
    await store.initialize();
    final tables = db
        .select("SELECT name FROM sqlite_master WHERE type='table'")
        .map((r) => r['name'] as String)
        .toSet();
    expect(tables, containsAll(<String>{
      'pg_lineage_documents',
      'pg_lineage_sections',
      'pg_lineage_chunks',
      'pg_embeddings',
      'pg_vector_index_entries',
      'pg_traces',
      'pg_trace_events',
      'pg_candidates',
      'pg_router_decisions',
      'pg_evidence',
      'pg_prompt_budgets',
      'pg_generation_stats',
      'pg_citations',
      'pg_experiment_runs',
      'pg_build_jobs',
    }));
    final routerSql = db
        .select("SELECT sql FROM sqlite_master WHERE name='pg_router_decisions'")
        .single['sql'] as String;
    expect(routerSql, contains('strategy_id'));
    expect(routerSql, contains('lane'));
    expect(BuildState.values.map((x) => x.name), containsAll(<String>[
      'prepared',
      'lexicalCommitted',
      'lineageCommitted',
      'vectorCommitted',
      'ready',
    ]));
    db.close();
  });

  test('runtime first-class records round-trip without collapsing identities', () async {
    final db = sqlite3.openInMemory();
    final store = LineageStore(database: db);
    await store.initialize();
    final started = DateTime.utc(2026, 8, 29, 9, 20);
    const traceId = 'tr-roundtrip';
    const strategy = 'active.r45-body-hybrid';

    await store.putTrace(LineageTrace(
      traceId: traceId,
      sessionId: 'session-1',
      turnId: 'turn-1',
      queryText: '端侧模型如何测试',
      requestedMode: 'auto',
      finalMode: 'knowledge',
      scopeJson: '{"type":"all"}',
      activeStrategyId: strategy,
      startedAt: started,
      completedAt: null,
      status: TraceStatus.running,
      failureStage: null,
      failureCode: null,
    ));
    expect((await store.traceById(traceId))!.queryText, '端侧模型如何测试');

    final event = TraceEventRecord(
      eventId: LineageIds.eventId(traceId, 1),
      traceId: traceId,
      seq: 1,
      stage: 'trace',
      kind: 'trace.started',
      truthKind: TruthKind.real,
      lane: RetrievalLane.active,
      strategyId: strategy,
      timestampUs: 123456,
      durationUs: null,
      payloadJson: '{"source":"runtime"}',
    );
    await store.appendEvent(event);
    expect((await store.eventsForTrace(traceId)).single.kind, 'trace.started');

    final candidate = CandidateRecord(
      candidateId: LineageIds.candidateId(traceId, strategy, 'chunk-1'),
      traceId: traceId,
      strategyId: strategy,
      lane: RetrievalLane.active,
      chunkId: 'chunk-1',
      embeddingId: 'emb-1',
      sourceChannels: 'fts5+vector',
      ftsRank: 2,
      rawBm25: -3.2,
      vectorRank: 1,
      rawCosine: 0.81,
      fusionRank: 1,
      fusionScore: 0.04,
      rerankRank: null,
      rerankScore: null,
      finalRank: 1,
      selectedForEvidence: true,
      dropReason: null,
    );
    await store.putCandidate(candidate);
    expect((await store.candidatesForTrace(traceId)).single.embeddingId, 'emb-1');

    await store.putRouterDecision(const RouterDecisionRecord(
      decisionId: 'router-1',
      traceId: traceId,
      strategyId: strategy,
      lane: RetrievalLane.active,
      ftsHitCount: 3,
      top1Cosine: 0.81,
      top2Cosine: 0.62,
      top1Top2Gap: 0.19,
      dualChannel: true,
      lexicalGatePass: true,
      semanticStrengthGatePass: true,
      semanticGapGatePass: true,
      finalUseKnowledge: true,
      ruleProfile: 'r45-auto',
      decisionReason: 'dual channel winner',
    ));
    expect(
      (await store.routerDecisionForTrace(traceId, strategy, RetrievalLane.active))!
          .finalUseKnowledge,
      isTrue,
    );

    final evidenceId = LineageIds.evidenceId(traceId, strategy, 'chunk-1');
    await store.putEvidence(EvidenceRecord(
      evidenceId: evidenceId,
      traceId: traceId,
      strategyId: strategy,
      lane: RetrievalLane.active,
      anchor: 'E1',
      candidateId: candidate.candidateId,
      chunkId: 'chunk-1',
      selectionRank: 1,
      score: 0.04,
      tokenCount: 120,
      selectionReason: 'top conservative evidence',
    ));
    expect((await store.evidenceForTrace(traceId)).single.anchor, 'E1');

    await store.putPromptBudget(const PromptBudgetRecord(
      traceId: traceId,
      strategyId: strategy,
      lane: RetrievalLane.active,
      modelContextLimit: 8192,
      systemTokens: 600,
      historyTokens: 900,
      evidenceTokens: 120,
      queryTokens: 30,
      outputReserveTokens: 700,
      totalPrefillTokens: 1650,
      remainingTokens: 5842,
      trimmedHistoryMessages: 1,
      trimmedEvidenceItems: 0,
      trimDetailJson: '{"history":1}',
    ));
    expect((await store.promptBudgetForTrace(traceId))!.remainingTokens, 5842);

    await store.putGenerationStats(const GenerationStatsRecord(
      traceId: traceId,
      strategyId: strategy,
      lane: RetrievalLane.active,
      ttftMs: null,
      generationMs: 1500,
      outputTokens: null,
      decodeTokensPerSecond: null,
      backend: 'LiteRT',
      nativeSessionRebuilt: true,
      sessionResetReason: 'fresh turn',
    ));
    expect((await store.generationStatsForTrace(traceId))!.generationMs, 1500);

    await store.putCitation(CitationRecord(
      citationId: 'cit-1',
      traceId: traceId,
      anchor: 'E1',
      evidenceId: evidenceId,
      chunkId: 'chunk-1',
      documentId: 'doc-1',
      sectionId: null,
      pageNo: null,
      citationStatus: 'resolved',
    ));
    expect((await store.citationsForTrace(traceId)).single.documentId, 'doc-1');

    final jobId = LineageIds.buildJobId('doc-1', strategy);
    await store.putBuildJob(BuildJobRecord(
      jobId: jobId,
      jobType: 'active-migration',
      strategyId: strategy,
      documentId: 'doc-1',
      status: BuildJobStatus.running,
      totalItems: 10,
      completedItems: 4,
      checkpointJson: '{"state":"lineage_committed"}',
      currentSource: 'doc.txt',
      failureCode: null,
      failureDetail: null,
      createdAt: started,
      updatedAt: started,
    ));
    expect((await store.buildJobById(jobId))!.completedItems, 4);

    expect((await store.latestTraces(limit: 5)).single.traceId, traceId);
    db.close();
  });

  test('trace events are immutable by sequence and retention keeps persistent chunk vectors', () async {
    final db = sqlite3.openInMemory();
    final store = LineageStore(database: db);
    await store.initialize();
    const strategy = 'active.r45-body-hybrid';

    Future<void> addCompleteTrace(String id, int minute) async {
      final time = DateTime.utc(2026, 8, 29, 9, minute);
      await store.putTrace(LineageTrace(
        traceId: id,
        sessionId: 's',
        turnId: id,
        queryText: id,
        requestedMode: 'auto',
        finalMode: 'knowledge',
        scopeJson: '{"type":"all"}',
        activeStrategyId: strategy,
        startedAt: time,
        completedAt: time,
        status: TraceStatus.complete,
        failureStage: null,
        failureCode: null,
      ));
      await store.putEmbedding(LineageEmbedding.test(
        embeddingId: LineageIds.queryEmbeddingId(id),
        sourceKind: 'query',
        sourceId: id,
        chunkId: null,
        representation: EmbeddingRepresentation.query,
        vector: const [0.3, 0.7],
        modelIdentity: 'EmbeddingGemma-test',
        taskMode: 'retrieval_query',
      ));
    }

    await addCompleteTrace('tr-old', 1);
    await addCompleteTrace('tr-new', 2);
    await store.putEmbedding(LineageEmbedding.test(
      embeddingId: LineageIds.bodyEmbeddingId('chunk-persistent'),
      sourceKind: 'chunk',
      sourceId: 'chunk-persistent',
      chunkId: 'chunk-persistent',
      representation: EmbeddingRepresentation.body,
      vector: const [1.0, 0.2],
      modelIdentity: 'EmbeddingGemma-test',
      taskMode: 'retrieval_document',
    ));

    final first = TraceEventRecord(
      eventId: LineageIds.eventId('tr-new', 1),
      traceId: 'tr-new',
      seq: 1,
      stage: 'trace',
      kind: 'trace.started',
      truthKind: TruthKind.real,
      lane: RetrievalLane.active,
      strategyId: strategy,
      timestampUs: 1,
      durationUs: null,
      payloadJson: '{}',
    );
    await store.appendEvent(first);
    expect(() => store.appendEvent(first), throwsA(anything));

    await store.pruneCompletedTraces(keep: 1);
    expect(await store.traceById('tr-old'), isNull);
    expect(await store.traceById('tr-new'), isNotNull);
    expect(await store.embeddingById(LineageIds.queryEmbeddingId('tr-old')), isNull);
    expect(
      await store.embeddingById(LineageIds.bodyEmbeddingId('chunk-persistent')),
      isNotNull,
    );
    db.close();
  });
}
