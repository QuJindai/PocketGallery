import '../core/models.dart';
import '../observability/retrieval_trace.dart';

class RetrievalBundle {
  const RetrievalBundle({
    required this.lexicalHits,
    required this.semanticHits,
    required this.hybridHits,
    required this.evidence,
    required this.lexicalOnly,
    this.autoRelevantOverride,
    this.knowledgeRelevantOverride,
    this.queryEmbeddingId,
    this.queryEmbeddingVector,
    this.traceDraft,
  });

  static const semanticOnlyAutoStrongThreshold = 0.62;
  static const semanticOnlyAutoFloor = 0.52;
  static const semanticOnlyAutoGap = 0.035;
  static const semanticOnlyKnowledgeStrongThreshold = 0.58;
  static const semanticOnlyKnowledgeFloor = 0.50;
  static const semanticOnlyKnowledgeGap = 0.025;

  final List<RetrievalHit> lexicalHits;
  final List<RetrievalHit> semanticHits;
  final List<HybridHit> hybridHits;
  final List<EvidenceItem> evidence;
  final bool lexicalOnly;
  final bool? autoRelevantOverride;
  final bool? knowledgeRelevantOverride;

  /// Identity and the exact in-memory vector used by the ACTIVE vector index.
  /// Both stay null for lexical-only retrieval.
  final String? queryEmbeddingId;
  final List<double>? queryEmbeddingVector;
  final RetrievalTraceDraft? traceDraft;

  double? get topSemanticScore =>
      semanticHits.isEmpty ? null : semanticHits.first.score;

  double get semanticTopGap {
    if (semanticHits.length < 2) return 0;
    return semanticHits.first.score - semanticHits[1].score;
  }

  bool get relevantForAuto {
    final override = autoRelevantOverride;
    if (override != null) return override;
    if (evidence.isEmpty || hybridHits.isEmpty) return false;

    if (hybridHits.first.channels.length > 1) return true;
    if (lexicalHits.isNotEmpty) return true;

    final top = topSemanticScore ?? 0;
    return top >= semanticOnlyAutoStrongThreshold ||
        (top >= semanticOnlyAutoFloor && semanticTopGap >= semanticOnlyAutoGap);
  }

  bool get relevantForKnowledge {
    final override = knowledgeRelevantOverride;
    if (override != null) return override;
    if (evidence.isEmpty || hybridHits.isEmpty) return false;
    if (hybridHits.first.channels.length > 1) return true;
    if (lexicalHits.isNotEmpty) return true;
    final top = topSemanticScore ?? 0;
    return top >= semanticOnlyKnowledgeStrongThreshold ||
        (top >= semanticOnlyKnowledgeFloor &&
            semanticTopGap >= semanticOnlyKnowledgeGap);
  }
}
