import 'dart:convert';

import '../core/models.dart';
import '../experiments/representation_builder.dart';
import '../experiments/retrieval_experiment_engine.dart';
import '../experiments/retrieval_strategy.dart';
import '../lineage/lineage_ids.dart';
import '../lineage/lineage_models.dart';
import '../lineage/lineage_store.dart';
import '../retrieval/evidence_policy.dart';
import '../services/lexical_fts_store.dart';
import 'okf_models.dart';
import 'okf_signal_policy.dart';
import 'okf_store.dart';

class OkfAwareRetrievalExperimentEngine extends RetrievalExperimentEngine {
  OkfAwareRetrievalExperimentEngine({
    required LineageStore store,
    required LexicalFtsStore lexicalStore,
    required RepresentationBuilder representationBuilder,
    required this.okfStore,
    this.signalPolicy = const OkfSignalPolicy(),
    DateTime Function()? now,
  }) : super(
         store: store,
         lexicalStore: lexicalStore,
         representationBuilder: representationBuilder,
         clock: now,
       );

  final OkfStore okfStore;
  final OkfSignalPolicy signalPolicy;

  @override
  Future<ExperimentRunRecord> run({
    required String traceId,
    required String strategyId,
    int tokenReserve = 700,
    int limit = 8,
  }) async {
    if (strategyId != RetrievalStrategies.okfV02Structured.id) {
      return super.run(
        traceId: traceId,
        strategyId: strategyId,
        tokenReserve: tokenReserve,
        limit: limit,
      );
    }

    final trace = await store.traceById(traceId);
    if (trace == null) throw StateError('Unknown trace: $traceId');
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

    final baseRun = await super.run(
      traceId: traceId,
      strategyId: strategyId,
      tokenReserve: tokenReserve,
      limit: limit,
    );
    if (baseRun.status != ExperimentRunStatus.complete) return baseRun;

    final baseCandidates = await store.candidatesForTrace(
      traceId,
      strategyId: strategyId,
      lane: RetrievalLane.shadow,
    );
    final router = await store.routerDecisionForTrace(
      traceId,
      strategyId,
      RetrievalLane.shadow,
    );
    final scored = <_ScoredCandidate>[];
    final signals = <OkfCandidateSignal>[];
    var verifiedCount = 0;
    var staleCount = 0;
    final okfDocumentIds = <String>{};

    for (final candidate in baseCandidates) {
      final chunk = await lexicalStore.getChunk(candidate.chunkId);
      if (chunk == null) continue;
      final document = await okfStore.documentById(chunk.documentId);
      final links = document == null
          ? const <OkfLink>[]
          : await okfStore.linksForDocument(chunk.documentId);
      final relativeLinks = links
          .where((item) => item.isRelativeBundleLink)
          .length;
      final baseScore = candidate.rerankScore ?? candidate.fusionScore ?? 0.0;
      final signal = signalPolicy.score(
        baseScore: baseScore,
        document: document,
        relativeLinkCount: relativeLinks,
      );
      if (document != null) {
        okfDocumentIds.add(document.documentId);
        if (document.trustTier == OkfTrustTier.verified) verifiedCount++;
        if (document.freshness == OkfFreshness.stale ||
            document.freshness == OkfFreshness.deprecated) {
          staleCount++;
        }
      }
      final record = OkfCandidateSignal(
        traceId: traceId,
        strategyId: strategyId,
        candidateId: candidate.candidateId,
        chunkId: candidate.chunkId,
        documentId: chunk.documentId,
        baseScore: baseScore,
        trustAdjustment: signal.trustAdjustment,
        freshnessAdjustment: signal.freshnessAdjustment,
        linkAdjustment: signal.linkAdjustment,
        finalScore: signal.finalScore,
        reason: signal.reason,
      );
      signals.add(record);
      scored.add(
        _ScoredCandidate(
          candidate: candidate,
          chunk: chunk,
          signal: record,
        ),
      );
    }

    scored.sort((left, right) {
      final scoreOrder = right.signal.finalScore.compareTo(
        left.signal.finalScore,
      );
      if (scoreOrder != 0) return scoreOrder;
      return left.candidate.candidateId.compareTo(right.candidate.candidateId);
    });

    final rankedHits = <HybridHit>[
      for (final item in scored)
        HybridHit(
          chunk: item.chunk,
          score: item.signal.finalScore,
          channels: <String>{
            ...item.candidate.sourceChannels
                .split(',')
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty),
            if (await okfStore.documentById(item.chunk.documentId) != null)
              'okf-v0.2',
          },
          lexicalRank: item.candidate.ftsRank,
          semanticRank: item.candidate.vectorRank,
        ),
    ];
    final selection = const EvidencePolicy(maxEvidence: 3).select(
      rankedHits,
      maxItems: 3,
      maxTotalChars: tokenReserve * 3,
    );
    final selectedIds = selection.evidence
        .map((item) => item.chunk.id)
        .toSet();

    await store.clearStrategyOutputs(
      traceId: traceId,
      strategyId: strategyId,
      lane: RetrievalLane.shadow,
    );
    for (var index = 0; index < scored.length; index++) {
      final item = scored[index];
      final selected = selectedIds.contains(item.chunk.id);
      await store.putCandidate(
        CandidateRecord(
          candidateId: item.candidate.candidateId,
          traceId: traceId,
          strategyId: strategyId,
          lane: RetrievalLane.shadow,
          chunkId: item.candidate.chunkId,
          embeddingId: item.candidate.embeddingId,
          sourceChannels: _appendOkfChannel(
            item.candidate.sourceChannels,
            item.signal.documentId,
            okfDocumentIds,
          ),
          ftsRank: item.candidate.ftsRank,
          rawBm25: item.candidate.rawBm25,
          vectorRank: item.candidate.vectorRank,
          rawCosine: item.candidate.rawCosine,
          fusionRank: item.candidate.fusionRank,
          fusionScore: item.candidate.fusionScore,
          rerankRank: index + 1,
          rerankScore: item.signal.finalScore,
          finalRank: index + 1,
          selectedForEvidence: selected,
          dropReason: selected
              ? null
              : selection.dropReasons[item.chunk.id] ?? 'okf_not_selected',
        ),
      );
    }
    for (var index = 0; index < selection.evidence.length; index++) {
      final evidence = selection.evidence[index];
      final lineageChunk = await store.lineageChunkById(evidence.chunk.id);
      final signal = signals.firstWhere(
        (item) => item.chunkId == evidence.chunk.id,
      );
      await store.putEvidence(
        EvidenceRecord(
          evidenceId: LineageIds.evidenceId(
            traceId,
            strategyId,
            evidence.chunk.id,
          ),
          traceId: traceId,
          strategyId: strategyId,
          lane: RetrievalLane.shadow,
          anchor: null,
          candidateId: LineageIds.candidateId(
            traceId,
            strategyId,
            evidence.chunk.id,
          ),
          chunkId: evidence.chunk.id,
          selectionRank: index + 1,
          score: evidence.score,
          tokenCount:
              lineageChunk?.tokenCount ?? ((evidence.chunk.text.length + 2) ~/ 3),
          selectionReason: 'okf_v02_structured; ${signal.reason}',
        ),
      );
    }
    if (router != null) {
      await store.putRouterDecision(
        RouterDecisionRecord(
          decisionId: router.decisionId,
          traceId: router.traceId,
          strategyId: router.strategyId,
          lane: router.lane,
          ftsHitCount: router.ftsHitCount,
          top1Cosine: router.top1Cosine,
          top2Cosine: router.top2Cosine,
          top1Top2Gap: router.top1Top2Gap,
          dualChannel: router.dualChannel,
          lexicalGatePass: router.lexicalGatePass,
          semanticStrengthGatePass: router.semanticStrengthGatePass,
          semanticGapGatePass: router.semanticGapGatePass,
          finalUseKnowledge: selection.evidence.isNotEmpty,
          ruleProfile: '${router.ruleProfile}+okf-v0.2',
          decisionReason:
              '${router.decisionReason}; bounded OKF trust/freshness/link rerank applied',
        ),
      );
    }
    await okfStore.replaceCandidateSignals(
      traceId: traceId,
      strategyId: strategyId,
      signals: signals,
    );

    final activeAfter = await store.candidatesForTrace(
      traceId,
      strategyId: trace.activeStrategyId,
      lane: RetrievalLane.active,
    );
    final activeEvidenceAfter = await store.evidenceForTrace(
      traceId,
      strategyId: trace.activeStrategyId,
      lane: RetrievalLane.active,
    );
    if (_candidateFingerprint(activeBefore) !=
            _candidateFingerprint(activeAfter) ||
        _evidenceFingerprint(activeEvidenceBefore) !=
            _evidenceFingerprint(activeEvidenceAfter)) {
      throw StateError('OKF SHADOW isolation violation: ACTIVE rows changed');
    }

    final metrics = <String, Object?>{};
    if (baseRun.metricJson != null) {
      final decoded = jsonDecode(baseRun.metricJson!);
      if (decoded is Map) {
        metrics.addAll(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    }
    metrics.addAll(<String, Object?>{
      'okfCandidateCount': scored.length,
      'okfDocumentCount': okfDocumentIds.length,
      'verifiedCandidateCount': verifiedCount,
      'staleOrDeprecatedCandidateCount': staleCount,
      'okfScorePolicy': 'bounded-v1',
    });
    final updated = baseRun.copyWith(metricJson: jsonEncode(metrics));
    await store.putExperimentRun(updated);
    return updated;
  }

  String _appendOkfChannel(
    String existing,
    String documentId,
    Set<String> okfDocumentIds,
  ) {
    if (!okfDocumentIds.contains(documentId)) return existing;
    final channels = existing
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    channels.add('okf-v0.2');
    return channels.join(',');
  }

  String _candidateFingerprint(List<CandidateRecord> values) => jsonEncode([
    for (final value in values)
      <Object?>[
        value.candidateId,
        value.chunkId,
        value.embeddingId,
        value.sourceChannels,
        value.ftsRank,
        value.rawBm25,
        value.vectorRank,
        value.rawCosine,
        value.fusionRank,
        value.fusionScore,
        value.rerankRank,
        value.rerankScore,
        value.finalRank,
        value.selectedForEvidence,
        value.dropReason,
      ],
  ]);

  String _evidenceFingerprint(List<EvidenceRecord> values) => jsonEncode([
    for (final value in values)
      <Object?>[
        value.evidenceId,
        value.anchor,
        value.candidateId,
        value.chunkId,
        value.selectionRank,
        value.score,
        value.tokenCount,
        value.selectionReason,
      ],
  ]);
}

class _ScoredCandidate {
  const _ScoredCandidate({
    required this.candidate,
    required this.chunk,
    required this.signal,
  });

  final CandidateRecord candidate;
  final PgChunk chunk;
  final OkfCandidateSignal signal;
}
