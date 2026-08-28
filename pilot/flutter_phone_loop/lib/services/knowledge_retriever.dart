import 'package:flutter_gemma/flutter_gemma.dart';

import '../chat/chat_models.dart';
import '../core/evidence.dart';
import '../core/hybrid_ranker.dart';
import '../core/models.dart';
import '../observability/retrieval_trace.dart';
import '../observability/retrieval_trace_recorder.dart';
import 'lexical_fts_store.dart';
import 'semantic_store.dart';

class RetrievalBundle {
  const RetrievalBundle({
    required this.lexicalHits,
    required this.semanticHits,
    required this.hybridHits,
    required this.evidence,
    required this.lexicalOnly,
    this.autoRelevantOverride,
    this.traceDraft,
  });

  final List<RetrievalHit> lexicalHits;
  final List<RetrievalHit> semanticHits;
  final List<HybridHit> hybridHits;
  final List<EvidenceItem> evidence;
  final bool lexicalOnly;
  final bool? autoRelevantOverride;
  final RetrievalTraceDraft? traceDraft;

  bool get relevantForAuto {
    final override = autoRelevantOverride;
    if (override != null) return override;
    if (evidence.isEmpty || hybridHits.isEmpty) return false;
    final top = hybridHits.first;
    return top.channels.length > 1 || top.score >= 0.03;
  }
}

abstract class KnowledgeRetrievalGateway {
  Future<RetrievalBundle> retrieve(
    String query, {
    KnowledgeScope scope = const KnowledgeScope.all(),
    int limit = 8,
  });
}

class KnowledgeRetriever implements KnowledgeRetrievalGateway {
  KnowledgeRetriever({
    required this.lexicalStore,
    required this.semanticStore,
    HybridRanker? ranker,
    EvidencePackBuilder? evidenceBuilder,
  })  : ranker = ranker ?? const HybridRanker(),
        evidenceBuilder = evidenceBuilder ?? const EvidencePackBuilder();

  final LexicalFtsStore lexicalStore;
  final SemanticStore semanticStore;
  final HybridRanker ranker;
  final EvidencePackBuilder evidenceBuilder;

  @override
  Future<RetrievalBundle> retrieve(
    String query, {
    KnowledgeScope scope = const KnowledgeScope.all(),
    int limit = 8,
  }) async {
    final startedAt = DateTime.now().toUtc();

    if (_isCorpusSummaryIntent(query)) {
      final fusionWatch = Stopwatch()..start();
      final coverage = await _buildCorpusCoverage(scope, limit);
      fusionWatch.stop();
      final evidenceWatch = Stopwatch()..start();
      final evidence = evidenceBuilder.build(coverage);
      evidenceWatch.stop();
      return RetrievalBundle(
        lexicalHits: const <RetrievalHit>[],
        semanticHits: const <RetrievalHit>[],
        hybridHits: coverage,
        evidence: evidence,
        lexicalOnly: !FlutterGemma.hasActiveEmbedder(),
        autoRelevantOverride: evidence.isNotEmpty,
        traceDraft: RetrievalTraceDraft(
          startedAt: startedAt,
          timings: TraceStageTiming(
            fusionMs: fusionWatch.elapsedMilliseconds,
            evidenceMs: evidenceWatch.elapsedMilliseconds,
          ),
          lexicalHits: const [],
          semanticHits: const [],
          hybridHits: RetrievalTraceRecorder.hybrid(coverage),
        ),
      );
    }

    final lexicalWatch = Stopwatch()..start();
    final lexicalInspection = await lexicalStore.inspect(
      query,
      topK: limit * 2,
      scope: scope,
    );
    lexicalWatch.stop();
    final lexical = [
      for (final hit in lexicalInspection.hits)
        RetrievalHit(
          chunk: hit.chunk,
          score: hit.affinity,
          channel: 'fts5',
          rank: hit.rank,
        ),
    ];

    final embedderReady = FlutterGemma.hasActiveEmbedder();
    final semanticWatch = Stopwatch()..start();
    final semantic = embedderReady
        ? await semanticStore.search(
            query,
            topK: limit * 2,
            scope: scope,
          )
        : const <RetrievalHit>[];
    semanticWatch.stop();

    final fusionWatch = Stopwatch()..start();
    final hybrid = ranker.fuse(
      query: query,
      lexical: lexical,
      semantic: semantic,
      limit: limit,
    );
    fusionWatch.stop();

    final evidenceWatch = Stopwatch()..start();
    final evidence = evidenceBuilder.build(hybrid);
    evidenceWatch.stop();

    final baseDraft = RetrievalTraceDraft(
      startedAt: startedAt,
      timings: TraceStageTiming(
        lexicalMs: lexicalWatch.elapsedMilliseconds,
        semanticMs: semanticWatch.elapsedMilliseconds,
        fusionMs: fusionWatch.elapsedMilliseconds,
        evidenceMs: evidenceWatch.elapsedMilliseconds,
      ),
      lexicalHits: RetrievalTraceRecorder.lexical(lexicalInspection.hits),
      semanticHits: RetrievalTraceRecorder.semantic(semantic),
      hybridHits: RetrievalTraceRecorder.hybrid(hybrid),
    );

    if (!scope.isAll) {
      if (evidence.isNotEmpty) {
        return RetrievalBundle(
          lexicalHits: lexical,
          semanticHits: semantic,
          hybridHits: hybrid,
          evidence: evidence,
          lexicalOnly: !embedderReady,
          autoRelevantOverride: true,
          traceDraft: baseDraft,
        );
      }
      final fallbackWatch = Stopwatch()..start();
      final coverage = await _buildCorpusCoverage(scope, limit);
      fallbackWatch.stop();
      final fallbackEvidenceWatch = Stopwatch()..start();
      final coverageEvidence = evidenceBuilder.build(coverage);
      fallbackEvidenceWatch.stop();
      return RetrievalBundle(
        lexicalHits: lexical,
        semanticHits: semantic,
        hybridHits: coverage,
        evidence: coverageEvidence,
        lexicalOnly: !embedderReady,
        autoRelevantOverride: coverageEvidence.isNotEmpty,
        traceDraft: RetrievalTraceDraft(
          startedAt: startedAt,
          timings: baseDraft.timings.copyWith(
            fusionMs: baseDraft.timings.fusionMs +
                fallbackWatch.elapsedMilliseconds,
            evidenceMs: baseDraft.timings.evidenceMs +
                fallbackEvidenceWatch.elapsedMilliseconds,
          ),
          lexicalHits: baseDraft.lexicalHits,
          semanticHits: baseDraft.semanticHits,
          hybridHits: RetrievalTraceRecorder.hybrid(coverage),
        ),
      );
    }

    return RetrievalBundle(
      lexicalHits: lexical,
      semanticHits: semantic,
      hybridHits: hybrid,
      evidence: evidence,
      lexicalOnly: !embedderReady,
      traceDraft: baseDraft,
    );
  }

  bool _isCorpusSummaryIntent(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return false;
    final summary = RegExp(
      r'(总结|概括|概览|梳理|综述|summari[sz]e|summary|overview)',
      caseSensitive: false,
    ).hasMatch(q);
    final corpus = RegExp(
      r'(知识库|全部文档|所有文档|这些文档|本地资料|全部资料|整个资料|文档库|knowledge\s*base|all\s+documents|documents|corpus)',
      caseSensitive: false,
    ).hasMatch(q);
    return summary && corpus;
  }

  Future<List<HybridHit>> _buildCorpusCoverage(
    KnowledgeScope scope,
    int limit,
  ) async {
    if (limit <= 0) return const <HybridHit>[];
    final allowed = scope.documentIds;
    final chunks = (await lexicalStore.allChunks())
        .where((chunk) => scope.isAll || allowed!.contains(chunk.documentId))
        .toList();
    if (chunks.isEmpty) return const <HybridHit>[];

    final byDocument = <String, List<PgChunk>>{};
    for (final chunk in chunks) {
      byDocument.putIfAbsent(chunk.documentId, () => <PgChunk>[]).add(chunk);
    }
    final documentIds = byDocument.keys.toList()..sort();
    for (final documentId in documentIds) {
      byDocument[documentId]!.sort((a, b) => a.ordinal.compareTo(b.ordinal));
    }

    const fractions = <double>[0, 0.5, 1, 0.25, 0.75, 0.125, 0.875];
    final selected = <PgChunk>[];
    final seenIds = <String>{};
    for (final fraction in fractions) {
      for (final documentId in documentIds) {
        final docChunks = byDocument[documentId]!;
        final index = ((docChunks.length - 1) * fraction).round();
        final chunk = docChunks[index];
        if (seenIds.add(chunk.id)) selected.add(chunk);
        if (selected.length >= limit) break;
      }
      if (selected.length >= limit) break;
    }

    if (selected.length < limit) {
      for (final documentId in documentIds) {
        for (final chunk in byDocument[documentId]!) {
          if (seenIds.add(chunk.id)) selected.add(chunk);
          if (selected.length >= limit) break;
        }
        if (selected.length >= limit) break;
      }
    }

    return [
      for (var i = 0; i < selected.length; i++)
        HybridHit(
          chunk: selected[i],
          score: 1.0 / (i + 1),
          channels: const {'corpus'},
          lexicalRank: null,
          semanticRank: null,
        ),
    ];
  }
}
