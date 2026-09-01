import '../lineage/lineage_models.dart';

enum ExperimentCandidatePolicy {
  bodyHybrid,
  headingBodyMultivector,
  sentenceParentChild,
}

enum ExperimentFusionPolicy { weightedRrf }

enum ExperimentRerankPolicy { none, featuresV1 }

enum ExperimentEvidencePolicy { conservative, dynamicV1 }

enum ParentChildPolicy { none, headingToChunk, sentenceToChunk }

class RetrievalStrategyDescriptor {
  const RetrievalStrategyDescriptor({
    required this.id,
    required this.label,
    required this.lane,
    required this.representations,
    required this.candidatePolicy,
    required this.fusionPolicy,
    required this.rerankPolicy,
    required this.evidencePolicy,
    required this.parentChildPolicy,
    required this.onDemand,
    this.maxSentenceRepresentationsPerChunk = 0,
  });

  final String id;
  final String label;
  final RetrievalLane lane;
  final Set<EmbeddingRepresentation> representations;
  final ExperimentCandidatePolicy candidatePolicy;
  final ExperimentFusionPolicy fusionPolicy;
  final ExperimentRerankPolicy rerankPolicy;
  final ExperimentEvidencePolicy evidencePolicy;
  final ParentChildPolicy parentChildPolicy;
  final bool onDemand;
  final int maxSentenceRepresentationsPerChunk;
}

abstract final class RetrievalStrategies {
  static const activeControl = RetrievalStrategyDescriptor(
    id: 'active.r45-body-hybrid',
    label: 'ACTIVE · R4.5 body hybrid',
    lane: RetrievalLane.active,
    representations: <EmbeddingRepresentation>{EmbeddingRepresentation.body},
    candidatePolicy: ExperimentCandidatePolicy.bodyHybrid,
    fusionPolicy: ExperimentFusionPolicy.weightedRrf,
    rerankPolicy: ExperimentRerankPolicy.none,
    evidencePolicy: ExperimentEvidencePolicy.conservative,
    parentChildPolicy: ParentChildPolicy.none,
    onDemand: false,
  );

  static const headingBodyMultivector = RetrievalStrategyDescriptor(
    id: 'shadow.heading-body-multivector',
    label: 'SHADOW · Heading + body multi-vector',
    lane: RetrievalLane.shadow,
    representations: <EmbeddingRepresentation>{
      EmbeddingRepresentation.body,
      EmbeddingRepresentation.heading,
    },
    candidatePolicy: ExperimentCandidatePolicy.headingBodyMultivector,
    fusionPolicy: ExperimentFusionPolicy.weightedRrf,
    rerankPolicy: ExperimentRerankPolicy.none,
    evidencePolicy: ExperimentEvidencePolicy.conservative,
    parentChildPolicy: ParentChildPolicy.headingToChunk,
    onDemand: true,
  );

  static const sentenceParentChild = RetrievalStrategyDescriptor(
    id: 'shadow.sentence-parent-child',
    label: 'SHADOW · Sentence parent-child',
    lane: RetrievalLane.shadow,
    representations: <EmbeddingRepresentation>{
      EmbeddingRepresentation.sentence,
    },
    candidatePolicy: ExperimentCandidatePolicy.sentenceParentChild,
    fusionPolicy: ExperimentFusionPolicy.weightedRrf,
    rerankPolicy: ExperimentRerankPolicy.none,
    evidencePolicy: ExperimentEvidencePolicy.conservative,
    parentChildPolicy: ParentChildPolicy.sentenceToChunk,
    onDemand: true,
    maxSentenceRepresentationsPerChunk: 4,
  );

  static const featureReranker = RetrievalStrategyDescriptor(
    id: 'rerank.features-v1',
    label: 'SHADOW · Explainable feature reranker',
    lane: RetrievalLane.shadow,
    representations: <EmbeddingRepresentation>{EmbeddingRepresentation.body},
    candidatePolicy: ExperimentCandidatePolicy.bodyHybrid,
    fusionPolicy: ExperimentFusionPolicy.weightedRrf,
    rerankPolicy: ExperimentRerankPolicy.featuresV1,
    evidencePolicy: ExperimentEvidencePolicy.conservative,
    parentChildPolicy: ParentChildPolicy.none,
    onDemand: true,
  );

  static const parentChild = RetrievalStrategyDescriptor(
    id: 'parent-child-v1',
    label: 'SHADOW · Parent-child',
    lane: RetrievalLane.shadow,
    representations: <EmbeddingRepresentation>{
      EmbeddingRepresentation.heading,
      EmbeddingRepresentation.sentence,
    },
    candidatePolicy: ExperimentCandidatePolicy.sentenceParentChild,
    fusionPolicy: ExperimentFusionPolicy.weightedRrf,
    rerankPolicy: ExperimentRerankPolicy.none,
    evidencePolicy: ExperimentEvidencePolicy.conservative,
    parentChildPolicy: ParentChildPolicy.sentenceToChunk,
    onDemand: true,
    maxSentenceRepresentationsPerChunk: 4,
  );

  static const dynamicEvidence = RetrievalStrategyDescriptor(
    id: 'evidence.dynamic-v1',
    label: 'SHADOW · Dynamic Evidence',
    lane: RetrievalLane.shadow,
    representations: <EmbeddingRepresentation>{EmbeddingRepresentation.body},
    candidatePolicy: ExperimentCandidatePolicy.bodyHybrid,
    fusionPolicy: ExperimentFusionPolicy.weightedRrf,
    rerankPolicy: ExperimentRerankPolicy.none,
    evidencePolicy: ExperimentEvidencePolicy.dynamicV1,
    parentChildPolicy: ParentChildPolicy.none,
    onDemand: true,
  );

  static const all = <RetrievalStrategyDescriptor>[
    activeControl,
    headingBodyMultivector,
    sentenceParentChild,
    featureReranker,
    parentChild,
    dynamicEvidence,
  ];

  static RetrievalStrategyDescriptor byId(String id) {
    for (final strategy in all) {
      if (strategy.id == id) return strategy;
    }
    throw ArgumentError.value(id, 'id', 'Unknown retrieval strategy');
  }
}
