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
}
