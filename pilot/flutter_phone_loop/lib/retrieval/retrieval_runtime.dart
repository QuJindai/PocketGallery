import '../chat/chat_models.dart';
import '../core/hybrid_ranker.dart';
import '../core/models.dart';
import '../lineage/lineage_ids.dart';
import '../lineage/lineage_models.dart';
import '../lineage/runtime_lineage_recorder.dart';
import '../observability/fts_inspector.dart';
import '../observability/retrieval_trace.dart';
import '../observability/retrieval_trace_recorder.dart';
import '../services/lexical_fts_store.dart';
import 'active_vector_index.dart';
import 'evidence_policy.dart';
import 'query_embedding_runtime.dart';
import 'retrieval_bundle.dart';
import 'retrieval_execution_context.dart';
import 'router_policy.dart';

class RetrievalRuntime {
  RetrievalRuntime({
    required this.lexicalStore,
    required this.queryEmbeddingRuntime,
    required this.activeVectorIndex,
    required this.recorder,
    required this.embedderReady,
    HybridRanker? ranker,
    RouterPolicy? routerPolicy,
    EvidencePolicy? evidencePolicy,
  })  : ranker = ranker ?? const HybridRanker(),
        routerPolicy = routerPolicy ?? const RouterPolicy(),
        evidencePolicy = evidencePolicy ?? const EvidencePolicy();

  final LexicalFtsStore lexicalStore;
  final QueryEmbeddingRuntime queryEmbeddingRuntime;
  final ActiveVectorIndex activeVectorIndex;
  final RuntimeLineageRecorder recorder;
  final bool Function() embedderReady;
  final HybridRanker ranker;
  final RouterPolicy routerPolicy;
  final EvidencePolicy evidencePolicy;

  Future<RetrievalBundle> execute(
    String query, {
    KnowledgeScope scope = const KnowledgeScope.all(),
    int limit = 8,
    required RetrievalExecutionContext execution,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      throw ArgumentError.value(query, 'query', 'Must not be empty');
    }
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive');
    }
    if (execution.strategyId != recorder.strategyId ||
        execution.lane != recorder.lane) {
      throw ArgumentError(
        'Retrieval execution strategy/lane does not match lineage recorder',
      );
    }

    final startedAt = DateTime.now().toUtc();
    final lexicalWatch = Stopwatch()..start();
    final inspection = await lexicalStore.inspect(
      cleanQuery,
      topK: limit * 2,
      scope: scope,
    );
    lexicalWatch.stop();
    final lexical = <RetrievalHit>[
      for (final hit in inspection.hits)
        RetrievalHit(
          chunk: hit.chunk,
          score: hit.affinity,
          channel: 'fts5',
          rank: hit.rank,
        ),
    ];
    await recorder.event(
      traceId: execution.traceId,
      stage: 'fts',
      kind: 'fts.search_completed',
      durationUs: lexicalWatch.elapsedMicroseconds,
      payload: <String, Object?>{
        'normalizedQuery': inspection.normalizedQuery,
        'hitCount': lexical.length,
        'topK': limit * 2,
        'diagnostics': inspection.diagnostics,
      },
    );

    final semanticWatch = Stopwatch()..start();
    CapturedQueryEmbedding? captured;
    var vectorHits = const <VectorSearchHit>[];
    final semantic = <RetrievalHit>[];
    final ready = embedderReady();
    if (ready) {
      final embeddingWatch = Stopwatch()..start();
      captured = await queryEmbeddingRuntime.generateOnce(
        traceId: execution.traceId,
        query: cleanQuery,
      );
      embeddingWatch.stop();
      await recorder.event(
        traceId: execution.traceId,
        stage: 'embedding',
        kind: 'embedding.query_completed',
        durationUs: embeddingWatch.elapsedMicroseconds,
        payload: <String, Object?>{
          'embeddingId': captured.embedding.embeddingId,
          'modelIdentity': captured.embedding.modelIdentity,
          'dimension': captured.embedding.dimension,
          'vectorSha256': captured.embedding.vectorSha256,
          'taskMode': captured.embedding.taskMode,
        },
      );

      final vectorWatch = Stopwatch()..start();
      vectorHits = await activeVectorIndex.searchByEmbedding(
        queryEmbedding: captured.vector,
        topK: limit * 2,
        scope: scope,
      );
      vectorWatch.stop();
      await recorder.event(
        traceId: execution.traceId,
        stage: 'vector',
        kind: 'vector.search_completed',
        durationUs: vectorWatch.elapsedMicroseconds,
        payload: <String, Object?>{
          'queryEmbeddingId': captured.embedding.embeddingId,
          'hitCount': vectorHits.length,
          'topK': limit * 2,
        },
      );

      for (final hit in vectorHits) {
        final chunk = await lexicalStore.getChunk(hit.chunkId);
        if (chunk == null || chunk.documentId != hit.documentId) continue;
        if (!scope.isAll && !scope.documentIds!.contains(chunk.documentId)) {
          continue;
        }
        semantic.add(RetrievalHit(
          chunk: chunk,
          score: hit.similarity,
          channel: 'embedding',
          rank: hit.rank,
        ));
      }
    } else {
      await recorder.event(
        traceId: execution.traceId,
        stage: 'embedding',
        kind: 'embedding.query_skipped',
        payload: const <String, Object?>{'reason': 'embedder_unavailable'},
      );
      await recorder.event(
        traceId: execution.traceId,
        stage: 'vector',
        kind: 'vector.search_skipped',
        payload: const <String, Object?>{'reason': 'embedder_unavailable'},
      );
    }
    semanticWatch.stop();

    final fusionWatch = Stopwatch()..start();
    final hybrid = ranker.fuse(
      query: cleanQuery,
      lexical: lexical,
      semantic: semantic,
      limit: limit,
    );
    fusionWatch.stop();
    await recorder.event(
      traceId: execution.traceId,
      stage: 'fusion',
      kind: 'fusion.completed',
      truthKind: TruthKind.derived,
      durationUs: fusionWatch.elapsedMicroseconds,
      payload: <String, Object?>{
        'algorithm': 'weighted_rrf',
        'lexicalCount': lexical.length,
        'semanticCount': semantic.length,
        'hybridCount': hybrid.length,
        'limit': limit,
      },
    );

    final evidenceWatch = Stopwatch()..start();
    final selection = evidencePolicy.select(hybrid);
    evidenceWatch.stop();
    final autoDecision = routerPolicy.evaluate(
      lexicalHits: lexical,
      semanticHits: semantic,
      hybridHits: hybrid,
      evidenceAvailable: selection.evidence.isNotEmpty,
      requestedMode: 'auto',
    );
    final knowledgeDecision = routerPolicy.evaluate(
      lexicalHits: lexical,
      semanticHits: semantic,
      hybridHits: hybrid,
      evidenceAvailable: selection.evidence.isNotEmpty,
      requestedMode: 'knowledge',
    );
    final requestedDecision = execution.isKnowledgeMode
        ? knowledgeDecision
        : autoDecision;

    final candidateRecords = _candidateRecords(
      execution: execution,
      inspectionHits: inspection.hits,
      vectorHits: vectorHits,
      hybridHits: hybrid,
      selection: selection,
    );
    await recorder.candidates(
      traceId: execution.traceId,
      records: candidateRecords,
    );
    await recorder.routerDecision(RouterDecisionRecord(
      decisionId: LineageIds.routerDecisionId(
        execution.traceId,
        execution.strategyId,
        execution.lane,
      ),
      traceId: execution.traceId,
      strategyId: execution.strategyId,
      lane: execution.lane,
      ftsHitCount: requestedDecision.ftsHitCount,
      top1Cosine: requestedDecision.top1Cosine,
      top2Cosine: requestedDecision.top2Cosine,
      top1Top2Gap: requestedDecision.top1Top2Gap,
      dualChannel: requestedDecision.dualChannel,
      lexicalGatePass: requestedDecision.lexicalGatePass,
      semanticStrengthGatePass:
          requestedDecision.semanticStrengthGatePass,
      semanticGapGatePass: requestedDecision.semanticGapGatePass,
      finalUseKnowledge: requestedDecision.useKnowledge,
      ruleProfile: requestedDecision.ruleProfile,
      decisionReason: requestedDecision.reason,
    ));
    await recorder.evidence(
      traceId: execution.traceId,
      records: <EvidenceRecord>[
        for (var index = 0; index < selection.evidence.length; index++)
          EvidenceRecord(
            evidenceId: LineageIds.evidenceId(
              execution.traceId,
              execution.strategyId,
              selection.evidence[index].chunk.id,
            ),
            traceId: execution.traceId,
            strategyId: execution.strategyId,
            lane: execution.lane,
            anchor: selection.evidence[index].anchor,
            candidateId: LineageIds.candidateId(
              execution.traceId,
              execution.strategyId,
              selection.evidence[index].chunk.id,
            ),
            chunkId: selection.evidence[index].chunk.id,
            selectionRank: index + 1,
            score: selection.evidence[index].score,
            tokenCount: 0,
            selectionReason: 'hybrid_rank_relative_score;tokens_unavailable',
          ),
      ],
    );

    return RetrievalBundle(
      lexicalHits: lexical,
      semanticHits: semantic,
      hybridHits: hybrid,
      evidence: selection.evidence,
      lexicalOnly: !ready,
      autoRelevantOverride: autoDecision.useKnowledge,
      knowledgeRelevantOverride: knowledgeDecision.useKnowledge,
      queryEmbeddingId: captured?.embedding.embeddingId,
      queryEmbeddingVector: captured?.vector,
      traceDraft: RetrievalTraceDraft(
        startedAt: startedAt,
        timings: TraceStageTiming(
          lexicalMs: lexicalWatch.elapsedMilliseconds,
          semanticMs: semanticWatch.elapsedMilliseconds,
          fusionMs: fusionWatch.elapsedMilliseconds,
          evidenceMs: evidenceWatch.elapsedMilliseconds,
        ),
        lexicalHits: RetrievalTraceRecorder.lexical(inspection.hits),
        semanticHits: RetrievalTraceRecorder.semantic(semantic),
        hybridHits: RetrievalTraceRecorder.hybrid(hybrid),
      ),
    );
  }

  List<CandidateRecord> _candidateRecords({
    required RetrievalExecutionContext execution,
    required List<FtsInspectionHit> inspectionHits,
    required List<VectorSearchHit> vectorHits,
    required List<HybridHit> hybridHits,
    required EvidenceSelection selection,
  }) {
    final ftsByChunk = <String, FtsInspectionHit>{
      for (final hit in inspectionHits) hit.chunk.id: hit,
    };
    final vectorByChunk = <String, VectorSearchHit>{
      for (final hit in vectorHits) hit.chunkId: hit,
    };
    final hybridByChunk = <String, HybridHit>{
      for (final hit in hybridHits) hit.chunk.id: hit,
    };
    final fusionRanks = <String, int>{
      for (var index = 0; index < hybridHits.length; index++)
        hybridHits[index].chunk.id: index + 1,
    };
    final selectedIds = selection.evidence
        .map((item) => item.chunk.id)
        .toSet();
    final chunkIds = <String>{
      ...hybridHits.map((hit) => hit.chunk.id),
      ...inspectionHits.map((hit) => hit.chunk.id),
      ...vectorHits.map((hit) => hit.chunkId),
    };

    return <CandidateRecord>[
      for (final chunkId in chunkIds)
        CandidateRecord(
          candidateId: LineageIds.candidateId(
            execution.traceId,
            execution.strategyId,
            chunkId,
          ),
          traceId: execution.traceId,
          strategyId: execution.strategyId,
          lane: execution.lane,
          chunkId: chunkId,
          embeddingId: vectorByChunk[chunkId]?.embeddingId,
          sourceChannels: <String>[
            if (vectorByChunk.containsKey(chunkId)) 'embedding',
            if (ftsByChunk.containsKey(chunkId)) 'fts5',
          ].join(','),
          ftsRank: ftsByChunk[chunkId]?.rank,
          rawBm25: ftsByChunk[chunkId]?.rawBm25,
          vectorRank: vectorByChunk[chunkId]?.rank,
          rawCosine: vectorByChunk[chunkId]?.similarity,
          fusionRank: fusionRanks[chunkId],
          fusionScore: hybridByChunk[chunkId]?.score,
          rerankRank: null,
          rerankScore: null,
          finalRank: fusionRanks[chunkId],
          selectedForEvidence: selectedIds.contains(chunkId),
          dropReason: selectedIds.contains(chunkId)
              ? null
              : selection.dropReasonFor(chunkId) ??
                  (hybridByChunk.containsKey(chunkId)
                      ? 'not_selected'
                      : 'fusion_limit'),
        ),
    ];
  }
}
