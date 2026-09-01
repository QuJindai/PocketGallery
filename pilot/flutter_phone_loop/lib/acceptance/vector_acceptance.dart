import '../lineage/lineage_ids.dart';
import '../lineage/lineage_models.dart';
import '../lineage/trace_snapshot.dart';
import '../observability/trace_vector_space_service.dart';
import '../services/knowledge_engine.dart';

class VectorAcceptanceArtifact {
  const VectorAcceptanceArtifact({
    required this.traceId,
    required this.trace,
    required this.vectorSpace,
  });

  final String traceId;
  final TraceSnapshot trace;
  final TraceVectorSpaceSnapshot vectorSpace;
}

class VectorAcceptanceCapture {
  const VectorAcceptanceCapture();

  Future<VectorAcceptanceArtifact> capture(
    KnowledgeEngine engine,
    String traceId,
  ) async {
    final normalizedTraceId = traceId.trim();
    if (normalizedTraceId.isEmpty) {
      throw ArgumentError.value(traceId, 'traceId', 'Must not be empty');
    }
    final trace = await TraceSnapshot.load(
      engine.lineageStore,
      normalizedTraceId,
    );
    final vectorSpace = await TraceVectorSpaceService(
      lineageStore: engine.lineageStore,
      lexicalStore: engine.lexicalStore,
    ).build(trace);
    return VectorAcceptanceArtifact(
      traceId: normalizedTraceId,
      trace: trace,
      vectorSpace: vectorSpace,
    );
  }
}

class VectorTruthResult {
  VectorTruthResult({
    required Iterable<String> reasonCodes,
    required Map<String, Object?> evidence,
  }) : reasonCodes = List<String>.unmodifiable(reasonCodes),
       evidence = Map<String, Object?>.unmodifiable(evidence);

  final List<String> reasonCodes;
  final Map<String, Object?> evidence;

  bool get passed => reasonCodes.isEmpty;
}

class VectorTruthVerifier {
  const VectorTruthVerifier._();

  static VectorTruthResult verify(VectorAcceptanceArtifact artifact) {
    final reasons = <String>{};
    final traceId = artifact.traceId.trim();
    final trace = artifact.trace;
    final space = artifact.vectorSpace;
    final capturedTrace = trace.trace;
    final expectedQueryId = LineageIds.queryEmbeddingId(traceId);
    final queryEmbedding = trace.queryEmbedding;

    if (traceId.isEmpty || capturedTrace.traceId != traceId) {
      reasons.add('TRACE_ID_MISMATCH');
    }
    if (capturedTrace.status != TraceStatus.complete ||
        capturedTrace.activeStrategyId.trim().isEmpty) {
      reasons.add('ACTIVE_TRACE_NOT_COMPLETE');
    }

    final capturedQueryValid =
        queryEmbedding != null &&
        queryEmbedding.embeddingId == expectedQueryId &&
        queryEmbedding.sourceKind == 'query' &&
        queryEmbedding.sourceId == traceId &&
        queryEmbedding.chunkId == null &&
        queryEmbedding.representation == EmbeddingRepresentation.query;
    if (!capturedQueryValid || space.queryEmbeddingId != expectedQueryId) {
      reasons.add('QUERY_EMBEDDING_ID_MISMATCH');
    }
    if (queryEmbedding != null &&
        space.queryVectorSha256 != queryEmbedding.vectorSha256) {
      reasons.add('QUERY_VECTOR_SHA_MISMATCH');
    }
    if (!space.usedCapturedQuery) {
      reasons.add('CAPTURED_QUERY_NOT_USED');
    }

    if (space.originalDimension <= 3) {
      reasons.add('ORIGINAL_DIMENSION_NOT_HIGH');
    }
    if (queryEmbedding != null &&
        space.originalDimension != queryEmbedding.dimension) {
      reasons.add('ORIGINAL_DIMENSION_MISMATCH');
    }
    final ratios = space.explainedVarianceRatios;
    if (space.effectiveComponentCount != 3 ||
        ratios.length != 3 ||
        ratios.any((ratio) => !ratio.isFinite || ratio <= 1e-9)) {
      reasons.add('PCA_THREE_COMPONENTS_UNAVAILABLE');
    }

    final points = space.points;
    final queryPoints = points.where((point) => point.isQuery).toList();
    if (queryPoints.length != 1 ||
        queryPoints.singleOrNull?.embeddingId != expectedQueryId ||
        queryPoints.singleOrNull?.representation !=
            EmbeddingRepresentation.query) {
      reasons.add('QUERY_POINT_IDENTITY_MISMATCH');
    }
    final nonQueryPoints = points.where((point) => !point.isQuery).toList();
    if (nonQueryPoints.isEmpty) {
      reasons.add('NON_QUERY_POINT_MISSING');
    }
    if (nonQueryPoints.every(
      (point) =>
          point.representation != EmbeddingRepresentation.body ||
          (point.chunkId?.trim().isEmpty ?? true) ||
          point.text.trim().isEmpty,
    )) {
      reasons.add('REAL_CHUNK_POINT_MISSING');
    }
    if (<TraceVectorPoint>[...points, ...space.neighbors].any(
      (point) =>
          !point.x.isFinite ||
          !point.y.isFinite ||
          !point.z.isFinite ||
          !point.cosineToQuery.isFinite,
    )) {
      reasons.add('NON_FINITE_COORDINATE');
    }

    final activeCandidates = <String, CandidateRecord>{
      for (final candidate in trace.candidates)
        if (candidate.lane == RetrievalLane.active &&
            candidate.strategyId == capturedTrace.activeStrategyId)
          candidate.candidateId: candidate,
    };
    final evidenceByCandidate = <String, EvidenceRecord>{
      for (final evidence in trace.evidence)
        if (evidence.lane == RetrievalLane.active &&
            evidence.strategyId == capturedTrace.activeStrategyId)
          evidence.candidateId: evidence,
    };
    final candidatePoints = nonQueryPoints
        .where((point) => point.candidateId != null)
        .toList(growable: false);
    if (candidatePoints.isEmpty) {
      reasons.add('CANDIDATE_POINT_MISSING');
    }
    for (final point in candidatePoints) {
      final candidate = activeCandidates[point.candidateId];
      final rankCaptured =
          candidate != null &&
          <int?>[
            candidate.ftsRank,
            candidate.vectorRank,
            candidate.fusionRank,
            candidate.rerankRank,
            candidate.finalRank,
          ].any((rank) => rank != null && rank > 0) &&
          <int?>[
            point.ftsRank,
            point.vectorRank,
            point.finalRank,
          ].any((rank) => rank != null && rank > 0);
      final identityCaptured =
          candidate != null &&
          candidate.embeddingId == point.embeddingId &&
          candidate.chunkId == point.chunkId &&
          candidate.sourceChannels.trim().isNotEmpty &&
          point.sourceChannels?.trim().isNotEmpty == true;
      final evidence = evidenceByCandidate[point.candidateId];
      final explanationCaptured = point.selectedForEvidence
          ? candidate?.selectedForEvidence == true &&
                evidence != null &&
                point.selectionReason?.trim().isNotEmpty == true &&
                point.selectionReason == evidence.selectionReason
          : candidate?.selectedForEvidence == false &&
                point.dropReason?.trim().isNotEmpty == true &&
                point.dropReason == candidate?.dropReason;
      if (!rankCaptured || !identityCaptured || !explanationCaptured) {
        reasons.add('CANDIDATE_EXPLANATION_MISSING');
      }
    }

    return VectorTruthResult(
      reasonCodes: reasons,
      evidence: <String, Object?>{
        'traceId': traceId,
        'queryEmbeddingId': space.queryEmbeddingId,
        'originalDimension': space.originalDimension,
        'effectiveComponentCount': space.effectiveComponentCount,
        'explainedVarianceRatios': ratios,
        'pointCount': points.length,
        'queryPointCount': queryPoints.length,
        'nonQueryPointCount': nonQueryPoints.length,
        'candidatePointCount': candidatePoints.length,
      },
    );
  }
}

extension<T> on List<T> {
  T? get singleOrNull => length == 1 ? single : null;
}
