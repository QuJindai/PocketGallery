import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../chat/chat_models.dart';
import '../core/hybrid_ranker.dart';
import '../core/models.dart';
import '../services/lexical_fts_store.dart';
import '../services/semantic_store.dart';

enum RetrievalStrategy { ftsOnly, embeddingOnly, hybrid, alternateHybrid }

class RetrievalBenchmarkCase {
  const RetrievalBenchmarkCase({
    required this.id,
    required this.question,
    required this.expectedDocumentIds,
    required this.expectedSourceNames,
    required this.tags,
    this.expectedChunkIds = const <String>{},
    this.expectedUseKnowledge,
  });

  final String id;
  final String question;
  final Set<String> expectedDocumentIds;
  final Set<String> expectedSourceNames;
  final Set<String> expectedChunkIds;
  final bool? expectedUseKnowledge;
  final Set<String> tags;

  bool isRelevant(BenchmarkHit hit) =>
      expectedChunkIds.contains(hit.chunkId) ||
      expectedDocumentIds.contains(hit.documentId) ||
      expectedSourceNames.contains(hit.sourceName);

  factory RetrievalBenchmarkCase.fromJson(Map<String, dynamic> json) =>
      RetrievalBenchmarkCase(
        id: json['id'] as String,
        question: json['question'] as String,
        expectedDocumentIds:
            (json['expectedDocumentIds'] as List<dynamic>? ?? const [])
                .whereType<String>()
                .toSet(),
        expectedSourceNames:
            (json['expectedSourceNames'] as List<dynamic>? ?? const [])
                .whereType<String>()
                .toSet(),
        expectedChunkIds:
            (json['expectedChunkIds'] as List<dynamic>? ?? const [])
                .whereType<String>()
                .toSet(),
        expectedUseKnowledge: json['expectedUseKnowledge'] as bool?,
        tags: (json['tags'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toSet(),
      );
}

class BenchmarkHit {
  const BenchmarkHit({
    required this.chunkId,
    required this.documentId,
    required this.sourceName,
  });

  final String chunkId;
  final String documentId;
  final String sourceName;
}

class BenchmarkCaseResult {
  const BenchmarkCaseResult({
    required this.caseId,
    required this.strategy,
    required this.hits,
    this.routerUseKnowledge,
    this.citedChunkIds,
    this.failureCode,
  });

  final String caseId;
  final RetrievalStrategy strategy;
  final List<BenchmarkHit> hits;
  final bool? routerUseKnowledge;
  final Set<String>? citedChunkIds;
  final String? failureCode;
}

class RetrievalBenchmarkDataset {
  const RetrievalBenchmarkDataset(this.name, this.cases);
  final String name;
  final List<RetrievalBenchmarkCase> cases;

  static Future<RetrievalBenchmarkDataset> loadAsset(
    String assetPath,
  ) async {
    final raw = await rootBundle.loadString(assetPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return RetrievalBenchmarkDataset(
      json['name'] as String? ?? assetPath,
      (json['cases'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(RetrievalBenchmarkCase.fromJson)
          .toList(growable: false),
    );
  }
}

class RetrievalBenchmarkRunner {
  RetrievalBenchmarkRunner({
    required this.lexicalStore,
    required this.semanticStore,
    HybridRanker? currentHybrid,
    HybridRanker? alternateHybrid,
  })  : currentHybrid = currentHybrid ?? const HybridRanker(),
        alternateHybrid = alternateHybrid ??
            const HybridRanker(
              lexicalWeight: 1.15,
              semanticWeight: 1.0,
              dualChannelBonus: 0.02,
            );

  final LexicalFtsStore lexicalStore;
  final SemanticStore semanticStore;
  final HybridRanker currentHybrid;
  final HybridRanker alternateHybrid;

  Future<BenchmarkCaseResult> runCase(
    RetrievalBenchmarkCase benchmark,
    RetrievalStrategy strategy, {
    KnowledgeScope scope = const KnowledgeScope.all(),
    int topK = 5,
  }) async {
    List<HybridHit> ranked;
    switch (strategy) {
      case RetrievalStrategy.ftsOnly:
        final hits = await lexicalStore.search(
          benchmark.question,
          topK: topK,
          scope: scope,
        );
        return BenchmarkCaseResult(
          caseId: benchmark.id,
          strategy: strategy,
          hits: _fromRetrieval(hits),
        );
      case RetrievalStrategy.embeddingOnly:
        final hits = FlutterGemma.hasActiveEmbedder()
            ? await semanticStore.search(
                benchmark.question,
                topK: topK,
                scope: scope,
              )
            : const <RetrievalHit>[];
        return BenchmarkCaseResult(
          caseId: benchmark.id,
          strategy: strategy,
          hits: _fromRetrieval(hits),
        );
      case RetrievalStrategy.hybrid:
      case RetrievalStrategy.alternateHybrid:
        final lexical = await lexicalStore.search(
          benchmark.question,
          topK: topK * 2,
          scope: scope,
        );
        final semantic = FlutterGemma.hasActiveEmbedder()
            ? await semanticStore.search(
                benchmark.question,
                topK: topK * 2,
                scope: scope,
              )
            : const <RetrievalHit>[];
        ranked = (strategy == RetrievalStrategy.hybrid
                ? currentHybrid
                : alternateHybrid)
            .fuse(
          query: benchmark.question,
          lexical: lexical,
          semantic: semantic,
          limit: topK,
        );
        return BenchmarkCaseResult(
          caseId: benchmark.id,
          strategy: strategy,
          hits: [
            for (final hit in ranked)
              BenchmarkHit(
                chunkId: hit.chunk.id,
                documentId: hit.chunk.documentId,
                sourceName: hit.chunk.sourceName,
              ),
          ],
        );
    }
  }

  Future<List<BenchmarkCaseResult>> runDataset(
    RetrievalBenchmarkDataset dataset,
    RetrievalStrategy strategy, {
    KnowledgeScope scope = const KnowledgeScope.all(),
    int topK = 5,
  }) async {
    final out = <BenchmarkCaseResult>[];
    for (final benchmark in dataset.cases) {
      out.add(await runCase(
        benchmark,
        strategy,
        scope: scope,
        topK: topK,
      ));
    }
    return out;
  }

  List<BenchmarkHit> _fromRetrieval(List<RetrievalHit> hits) => [
        for (final hit in hits)
          BenchmarkHit(
            chunkId: hit.chunk.id,
            documentId: hit.chunk.documentId,
            sourceName: hit.chunk.sourceName,
          ),
      ];
}
