import 'dart:convert';

import '../chat/chat_models.dart';
import '../core/hybrid_ranker.dart';
import '../core/models.dart';
import '../lineage/lineage_ids.dart';
import '../lineage/lineage_models.dart';
import '../lineage/lineage_store.dart';
import '../retrieval/evidence_policy.dart';
import '../retrieval/router_policy.dart';
import '../services/lexical_fts_store.dart';
import 'dynamic_evidence_policy.dart';
import 'feature_reranker.dart';
import 'representation_builder.dart';
import 'retrieval_strategy.dart';

class RetrievalExperimentEngine {
  RetrievalExperimentEngine({
    required this.store,
    required this.lexicalStore,
    required this.representationBuilder,
    this.featureReranker = const FeatureReranker(),
    this.dynamicEvidencePolicy = const DynamicEvidencePolicy(),
    this.ranker = const HybridRanker(),
    this.routerPolicy = const RouterPolicy(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final LineageStore store;
  final LexicalFtsStore lexicalStore;
  final RepresentationBuilder representationBuilder;
  final FeatureReranker featureReranker;
  final DynamicEvidencePolicy dynamicEvidencePolicy;
  final HybridRanker ranker;
  final RouterPolicy routerPolicy;
  final DateTime Function() _clock;

  Future<ExperimentRunRecord> run({
    required String traceId,
    required String strategyId,
    int tokenReserve = 700,
    int limit = 8,
  }) async {
    if (limit <= 0) throw ArgumentError.value(limit, 'limit');
    if (tokenReserve <= 0) {
      throw ArgumentError.value(tokenReserve, 'tokenReserve');
    }
    final strategy = RetrievalStrategies.byId(strategyId);
    if (strategy.lane != RetrievalLane.shadow || !strategy.onDemand) {
      throw ArgumentError('Only on-demand SHADOW strategies can run here');
    }
    final trace = await store.traceById(traceId);
    if (trace == null) throw StateError('Unknown trace: $traceId');
    final startedAt = _clock().toUtc();
    var run = ExperimentRunRecord(
      experimentRunId: LineageIds.experimentRunId(
        traceId,
        strategyId,
        startedAt.microsecondsSinceEpoch,
      ),
      traceId: traceId,
      strategyId: strategyId,
      lane: RetrievalLane.shadow,
      status: ExperimentRunStatus.running,
      startedAt: startedAt,
      completedAt: null,
      completedItems: 0,
      totalItems: 0,
      metricJson: null,
      failureCode: null,
    );
    await store.putExperimentRun(run);

    try {
      if (trace.status != TraceStatus.complete) {
        throw StateError('Trace must be complete before SHADOW execution');
      }
      final queryEmbedding = await store.embeddingById(
        LineageIds.queryEmbeddingId(traceId),
      );
      if (queryEmbedding == null ||
          queryEmbedding.representation != EmbeddingRepresentation.query) {
        throw StateError('Captured query embedding is required');
      }
      if (queryEmbedding.modelIdentity !=
          representationBuilder.modelIdentity) {
        throw StateError(
          'model identity mismatch: captured query uses '
          '${queryEmbedding.modelIdentity}, experiment uses '
          '${representationBuilder.modelIdentity}',
        );
      }
      final scope = KnowledgeScope.fromJson(trace.scopeJson);
      final allChunks = await lexicalStore.allChunks();
      final chunks = allChunks
          .where(
            (chunk) =>
                scope.isAll || scope.documentIds!.contains(chunk.documentId),
          )
          .toList(growable: false);
      final build = await representationBuilder.build(
        strategy: strategy,
        chunks: chunks,
      );
      run = run.copyWith(
        completedItems: build.completedItems,
        totalItems: build.totalItems,
      );
      await store.putExperimentRun(run);

      final activeBefore = await store.candidatesForTrace(
        traceId,
        strategyId: trace.activeStrategyId,
        lane: RetrievalLane.active,
      );
      final activeEvidenceBefore = await store.evidenceForTrace(
        traceId,
        strategyId: trace.activeStrategyId,
        lane: RetrievalLane.active,
      );
      await store.clearStrategyOutputs(
        traceId: traceId,
        strategyId: strategyId,
        lane: RetrievalLane.shadow,
      );

      final inspection = await lexicalStore.inspect(
        trace.queryText,
        topK: limit * 2,
        scope: scope,
      );
      final lexical = <RetrievalHit>[
        for (final hit in inspection.hits)
          RetrievalHit(
            chunk: hit.chunk,
            score: hit.affinity,
            channel: 'fts5',
            rank: hit.rank,
          ),
      ];
      final vectorHits = await _vectorParents(
        strategy: strategy,
        chunks: chunks,
        queryEmbedding: queryEmbedding,
        topK: limit * 2,
      );
      final semantic = <RetrievalHit>[
        for (final hit in vectorHits)
          RetrievalHit(
            chunk: hit.chunk,
            score: hit.cosine,
            channel: 'embedding',
            rank: hit.rank,
          ),
      ];
      final fused = ranker.fuse(
        query: trace.queryText,
        lexical: lexical,
        semantic: semantic,
        limit: limit * 2,
      );
      final fusionRank = <String, int>{
        for (var index = 0; index < fused.length; index++)
          fused[index].chunk.id: index + 1,
      };
      final fusedByChunk = <String, HybridHit>{
        for (final hit in fused) hit.chunk.id: hit,
      };
      final vectorByChunk = <String, _VectorParentHit>{
        for (final hit in vectorHits) hit.chunk.id: hit,
      };
      final lexicalByChunk = {
        for (final hit in inspection.hits) hit.chunk.id: hit,
      };

      var finalHits = fused;
      final rerankByChunk = <String, FeatureRerankResult>{};
      if (strategy.rerankPolicy == ExperimentRerankPolicy.featuresV1) {
        final seenDocuments = <String>{};
        final inputs = <FeatureRerankInput>[];
        for (var index = 0; index < fused.length; index++) {
          final hit = fused[index];
          final lineageChunk = await store.lineageChunkById(hit.chunk.id);
          final section = lineageChunk?.sectionId == null
              ? null
              : await store.lineageSectionById(lineageChunk!.sectionId!);
          inputs.add(FeatureRerankInput(
            candidateId: LineageIds.candidateId(
              traceId,
              strategyId,
              hit.chunk.id,
            ),
            chunkId: hit.chunk.id,
            documentId: hit.chunk.documentId,
            baseRank: index + 1,
            features: featureReranker.extract(
              query: trace.queryText,
              chunkText: hit.chunk.text,
              heading: section?.heading,
              lexicalAffinity: lexicalByChunk[hit.chunk.id]?.affinity ?? 0,
              cosine: vectorByChunk[hit.chunk.id]?.cosine ?? 0,
              dualChannel: hit.channels.length > 1,
              sourceIsNew: seenDocuments.add(hit.chunk.documentId),
            ),
          ));
        }
        final reranked = featureReranker.rerank(inputs);
        rerankByChunk.addEntries(
          reranked.map((result) => MapEntry(result.input.chunkId, result)),
        );
        finalHits = <HybridHit>[
          for (final result in reranked)
            _withScore(
              fusedByChunk[result.input.chunkId]!,
              result.scored.score,
            ),
        ];
        for (final result in reranked) {
          await store.putRerankFeature(RerankFeatureRecord(
            featureId: LineageIds.rerankFeatureId(
              traceId,
              strategyId,
              result.input.chunkId,
            ),
            traceId: traceId,
            strategyId: strategyId,
            lane: RetrievalLane.shadow,
            candidateId: result.input.candidateId,
            chunkId: result.input.chunkId,
            normalizedLexicalAffinity:
                result.input.features.normalizedLexicalAffinity,
            cosine: result.input.features.cosine,
            dualChannelAgreement:
                result.input.features.dualChannelAgreement,
            queryWindowCoverage:
                result.input.features.queryWindowCoverage,
            headingMatch: result.input.features.headingMatch,
            exactTermMatch: result.input.features.exactTermMatch,
            sourceDiversity: result.input.features.sourceDiversity,
            rerankScore: result.scored.score,
            contributionJson: jsonEncode(result.scored.contributions),
          ));
        }
      }

      final selection = await _selectEvidence(
        strategy: strategy,
        hits: finalHits,
        tokenReserve: tokenReserve,
      );
      final selectedIds = selection.selected.map((item) => item.chunk.id).toSet();
      final finalRank = <String, int>{
        for (var index = 0; index < finalHits.length; index++)
          finalHits[index].chunk.id: index + 1,
      };
      final chunkIds = <String>{
        ...inspection.hits.map((hit) => hit.chunk.id),
        ...vectorHits.map((hit) => hit.chunk.id),
        ...fused.map((hit) => hit.chunk.id),
      };
      for (final chunkId in chunkIds) {
        final vector = vectorByChunk[chunkId];
        final lexicalHit = lexicalByChunk[chunkId];
        final fusedHit = fusedByChunk[chunkId];
        final reranked = rerankByChunk[chunkId];
        final selected = selectedIds.contains(chunkId);
        await store.putCandidate(CandidateRecord(
          candidateId: LineageIds.candidateId(traceId, strategyId, chunkId),
          traceId: traceId,
          strategyId: strategyId,
          lane: RetrievalLane.shadow,
          chunkId: chunkId,
          embeddingId: vector?.embedding.embeddingId,
          sourceChannels: <String>[
            if (lexicalHit != null) 'fts5',
            if (vector != null) 'embedding:${vector.embedding.representation.name}',
            if (vector != null &&
                vector.embedding.representation != EmbeddingRepresentation.body)
              'parent-child',
          ].join(','),
          ftsRank: lexicalHit?.rank,
          rawBm25: lexicalHit?.rawBm25,
          vectorRank: vector?.rank,
          rawCosine: vector?.cosine,
          fusionRank: fusionRank[chunkId],
          fusionScore: fusedHit?.score,
          rerankRank: reranked?.rank,
          rerankScore: reranked?.scored.score,
          finalRank: finalRank[chunkId],
          selectedForEvidence: selected,
          dropReason: selected
              ? null
              : selection.dropReasons[chunkId] ??
                  (fusedHit == null ? 'fusion_limit' : 'not_selected'),
        ));
      }
      for (var index = 0; index < selection.selected.length; index++) {
        final item = selection.selected[index];
        await store.putEvidence(EvidenceRecord(
          evidenceId: LineageIds.evidenceId(
            traceId,
            strategyId,
            item.chunk.id,
          ),
          traceId: traceId,
          strategyId: strategyId,
          lane: RetrievalLane.shadow,
          anchor: null,
          candidateId: LineageIds.candidateId(
            traceId,
            strategyId,
            item.chunk.id,
          ),
          chunkId: item.chunk.id,
          selectionRank: index + 1,
          score: item.score,
          tokenCount: await _tokenCount(item.chunk),
          selectionReason: strategy.evidencePolicy ==
                  ExperimentEvidencePolicy.dynamicV1
              ? 'dynamic_token_budget;source_diversity'
              : 'shadow_conservative_rank',
        ));
      }

      final decision = routerPolicy.evaluate(
        lexicalHits: lexical,
        semanticHits: semantic,
        hybridHits: finalHits,
        evidenceAvailable: selection.selected.isNotEmpty,
        requestedMode: trace.requestedMode,
      );
      await store.putRouterDecision(RouterDecisionRecord(
        decisionId: LineageIds.routerDecisionId(
          traceId,
          strategyId,
          RetrievalLane.shadow,
        ),
        traceId: traceId,
        strategyId: strategyId,
        lane: RetrievalLane.shadow,
        ftsHitCount: decision.ftsHitCount,
        top1Cosine: decision.top1Cosine,
        top2Cosine: decision.top2Cosine,
        top1Top2Gap: decision.top1Top2Gap,
        dualChannel: decision.dualChannel,
        lexicalGatePass: decision.lexicalGatePass,
        semanticStrengthGatePass: decision.semanticStrengthGatePass,
        semanticGapGatePass: decision.semanticGapGatePass,
        finalUseKnowledge: decision.useKnowledge,
        ruleProfile: decision.ruleProfile,
        decisionReason: decision.reason,
      ));

      final shadowIds = chunkIds.toSet();
      final activeIds = activeBefore.map((item) => item.chunkId).toSet();
      final activeEvidenceAfter = await store.evidenceForTrace(
        traceId,
        strategyId: trace.activeStrategyId,
        lane: RetrievalLane.active,
      );
      if (activeEvidenceAfter.length != activeEvidenceBefore.length) {
        throw StateError('SHADOW isolation violation: ACTIVE Evidence changed');
      }
      run = run.copyWith(
        status: ExperimentRunStatus.complete,
        completedAt: _clock().toUtc(),
        completedItems: build.completedItems,
        totalItems: build.totalItems,
        metricJson: jsonEncode(<String, Object>{
          'queryEmbeddingId': queryEmbedding.embeddingId,
          'candidateCount': chunkIds.length,
          'evidenceCount': selection.selected.length,
          'addedCandidateIds': (shadowIds.difference(activeIds).toList()..sort()),
          'removedCandidateIds': (activeIds.difference(shadowIds).toList()..sort()),
          'generatedRepresentations': build.generatedItems,
          'reusedRepresentations': build.reusedItems,
        }),
      );
      await store.putExperimentRun(run);
      return run;
    } catch (error) {
      run = run.copyWith(
        status: ExperimentRunStatus.failed,
        completedAt: _clock().toUtc(),
        failureCode: 'SHADOW_EXECUTION_FAILED',
        failureDetail: error.toString(),
      );
      await store.putExperimentRun(run);
      return run;
    }
  }

  Future<List<_VectorParentHit>> _vectorParents({
    required RetrievalStrategyDescriptor strategy,
    required List<PgChunk> chunks,
    required LineageEmbedding queryEmbedding,
    required int topK,
  }) async {
    final allowedChunks = <String, PgChunk>{
      for (final chunk in chunks) chunk.id: chunk,
    };
    final bestByChunk = <String, _VectorParentHit>{};
    for (final representation in strategy.representations) {
      final embeddings = await store.embeddingsForRepresentation(representation);
      for (final embedding in embeddings) {
        final chunkId = embedding.chunkId;
        if (chunkId == null || !allowedChunks.containsKey(chunkId)) continue;
        if (embedding.dimension != queryEmbedding.dimension) continue;
        if (embedding.modelIdentity != queryEmbedding.modelIdentity) continue;
        final similarity = _cosine(queryEmbedding, embedding);
        final hit = _VectorParentHit(
          embedding: embedding,
          chunk: allowedChunks[chunkId]!,
          cosine: similarity,
          rank: 0,
        );
        final current = bestByChunk[chunkId];
        if (current == null ||
            similarity > current.cosine ||
            (similarity == current.cosine &&
                embedding.embeddingId.compareTo(current.embedding.embeddingId) <
                    0)) {
          bestByChunk[chunkId] = hit;
        }
      }
    }
    final sorted = bestByChunk.values.toList()
      ..sort((left, right) {
        final scoreOrder = right.cosine.compareTo(left.cosine);
        if (scoreOrder != 0) return scoreOrder;
        return left.chunk.id.compareTo(right.chunk.id);
      });
    return <_VectorParentHit>[
      for (var index = 0; index < sorted.length && index < topK; index++)
        sorted[index].withRank(index + 1),
    ];
  }

  double _cosine(LineageEmbedding query, LineageEmbedding document) {
    final left = query.vector;
    final right = document.vector;
    var dot = 0.0;
    for (var index = 0; index < left.length; index++) {
      dot += left[index] * right[index];
    }
    return (dot / (query.norm * document.norm)).clamp(-1.0, 1.0).toDouble();
  }

  Future<_ExperimentEvidenceSelection> _selectEvidence({
    required RetrievalStrategyDescriptor strategy,
    required List<HybridHit> hits,
    required int tokenReserve,
  }) async {
    if (strategy.evidencePolicy == ExperimentEvidencePolicy.dynamicV1) {
      final candidates = <DynamicEvidenceCandidate>[];
      for (final hit in hits) {
        candidates.add(DynamicEvidenceCandidate(
          candidateId: hit.chunk.id,
          chunkId: hit.chunk.id,
          documentId: hit.chunk.documentId,
          ordinal: hit.chunk.ordinal,
          score: hit.score,
          tokenCount: await _tokenCount(hit.chunk),
        ));
      }
      final dynamic = dynamicEvidencePolicy.select(
        candidates,
        tokenReserve: tokenReserve,
      );
      final byId = <String, HybridHit>{
        for (final hit in hits) hit.chunk.id: hit,
      };
      return _ExperimentEvidenceSelection(
        selected: <HybridHit>[
          for (final item in dynamic.selected) byId[item.chunkId]!,
        ],
        dropReasons: dynamic.dropReasons,
      );
    }
    final selected = const EvidencePolicy(maxEvidence: 3).select(
      hits,
      maxItems: 3,
      maxTotalChars: tokenReserve * 3,
    );
    return _ExperimentEvidenceSelection(
      selected: <HybridHit>[
        for (final evidence in selected.evidence)
          hits.firstWhere((hit) => hit.chunk.id == evidence.chunk.id),
      ],
      dropReasons: selected.dropReasons,
    );
  }

  Future<int> _tokenCount(PgChunk chunk) async {
    final lineage = await store.lineageChunkById(chunk.id);
    return lineage?.tokenCount ?? ((chunk.text.length + 2) ~/ 3);
  }

  HybridHit _withScore(HybridHit hit, double score) => HybridHit(
        chunk: hit.chunk,
        score: score,
        channels: hit.channels,
        lexicalRank: hit.lexicalRank,
        semanticRank: hit.semanticRank,
        lexicalContribution: hit.lexicalContribution,
        semanticContribution: hit.semanticContribution,
        dualChannelContribution: hit.dualChannelContribution,
        exactTermContribution: hit.exactTermContribution,
      );
}

class _VectorParentHit {
  const _VectorParentHit({
    required this.embedding,
    required this.chunk,
    required this.cosine,
    required this.rank,
  });

  final LineageEmbedding embedding;
  final PgChunk chunk;
  final double cosine;
  final int rank;

  _VectorParentHit withRank(int value) => _VectorParentHit(
        embedding: embedding,
        chunk: chunk,
        cosine: cosine,
        rank: value,
      );
}

class _ExperimentEvidenceSelection {
  const _ExperimentEvidenceSelection({
    required this.selected,
    required this.dropReasons,
  });

  final List<HybridHit> selected;
  final Map<String, String> dropReasons;
}
