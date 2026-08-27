import 'package:flutter_gemma/flutter_gemma.dart';

import '../chat/chat_models.dart';
import '../core/evidence.dart';
import '../core/hybrid_ranker.dart';
import '../core/models.dart';
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
  });

  final List<RetrievalHit> lexicalHits;
  final List<RetrievalHit> semanticHits;
  final List<HybridHit> hybridHits;
  final List<EvidenceItem> evidence;
  final bool lexicalOnly;
  final bool? autoRelevantOverride;

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
    // A corpus/document summary is not a keyword-search problem. In lexical-only
    // mode a query such as "总结知识库" cannot match English source text, even
    // though the documents are present. Build deterministic cross-document
    // coverage evidence from existing chunks so Gemma can summarize the local
    // corpus before EmbeddingGemma is available as well as after it is ready.
    if (_isCorpusSummaryIntent(query)) {
      final coverage = await _buildCorpusCoverage(scope, limit);
      final evidence = evidenceBuilder.build(coverage);
      return RetrievalBundle(
        lexicalHits: const <RetrievalHit>[],
        semanticHits: const <RetrievalHit>[],
        hybridHits: coverage,
        evidence: evidence,
        lexicalOnly: !FlutterGemma.hasActiveEmbedder(),
        autoRelevantOverride: evidence.isNotEmpty,
      );
    }

    final lexical = await lexicalStore.search(
      query,
      topK: limit * 2,
      scope: scope,
    );
    final embedderReady = FlutterGemma.hasActiveEmbedder();
    final semantic = embedderReady
        ? await semanticStore.search(
            query,
            topK: limit * 2,
            scope: scope,
          )
        : const <RetrievalHit>[];
    final hybrid = ranker.fuse(
      query: query,
      lexical: lexical,
      semantic: semantic,
      limit: limit,
    );
    final evidence = evidenceBuilder.build(hybrid);
    return RetrievalBundle(
      lexicalHits: lexical,
      semanticHits: semantic,
      hybridHits: hybrid,
      evidence: evidence,
      lexicalOnly: !embedderReady,
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

    // Round-robin across documents, and within each document sample beginning,
    // middle, end, then quarter points. This avoids a long first document
    // monopolizing the evidence budget and gives "summarize knowledge base" a
    // useful corpus-wide view even without vector retrieval.
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

    // Very small documents can exhaust the fraction schedule. Fill any
    // remaining slots deterministically from still-unselected chunks.
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
