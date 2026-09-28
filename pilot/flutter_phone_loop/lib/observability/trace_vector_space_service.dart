import 'dart:math' as math;

import '../lineage/lineage_models.dart';
import '../lineage/lineage_store.dart';
import '../lineage/trace_snapshot.dart';
import '../services/lexical_fts_store.dart';
import 'pca_projector.dart';

class TraceVectorPoint {
  const TraceVectorPoint({
    required this.embeddingId,
    required this.chunkId,
    required this.documentId,
    required this.sourceName,
    required this.locator,
    required this.representation,
    required this.x,
    required this.y,
    required this.z,
    required this.cosineToQuery,
    required this.isQuery,
    required this.lane,
    required this.text,
    required this.candidateId,
    required this.sourceChannels,
    required this.selectedForEvidence,
    required this.selectionReason,
    required this.dropReason,
    required this.ftsRank,
    required this.vectorRank,
    required this.finalRank,
  });

  final String embeddingId;
  final String? chunkId;
  final String? documentId;
  final String sourceName;
  final String locator;
  final EmbeddingRepresentation representation;
  final double x;
  final double y;
  final double z;
  final double cosineToQuery;
  final bool isQuery;
  final RetrievalLane? lane;
  final String text;
  final String? candidateId;
  final String? sourceChannels;
  final bool selectedForEvidence;
  final String? selectionReason;
  final String? dropReason;
  final int? ftsRank;
  final int? vectorRank;
  final int? finalRank;
}

class TraceVectorSpaceSnapshot {
  const TraceVectorSpaceSnapshot({
    required this.queryEmbeddingId,
    required this.queryVectorSha256,
    required this.usedCapturedQuery,
    required this.samplePolicy,
    required this.totalPersistentBodyCount,
    required this.points,
    required this.neighbors,
    required this.explainedVarianceRatios,
    required this.originalDimension,
    required this.effectiveComponentCount,
  });

  final String queryEmbeddingId;
  final String queryVectorSha256;
  final bool usedCapturedQuery;
  final String samplePolicy;
  final int totalPersistentBodyCount;
  final List<TraceVectorPoint> points;
  final List<TraceVectorPoint> neighbors;
  final List<double> explainedVarianceRatios;
  final int originalDimension;
  final int effectiveComponentCount;
}

class TraceVectorSpaceService {
  TraceVectorSpaceService({
    required this.lineageStore,
    required this.lexicalStore,
    PcaProjector? projector,
  }) : projector = projector ?? const PcaProjector(iterations: 48);

  final LineageStore lineageStore;
  final LexicalFtsStore lexicalStore;
  final PcaProjector projector;

  Future<TraceVectorSpaceSnapshot> build(
    TraceSnapshot snapshot, {
    int maxCorpusPoints = 128,
  }) async {
    final query = snapshot.queryEmbedding;
    if (query == null ||
        query.representation != EmbeddingRepresentation.query) {
      throw StateError('Trace has no captured query embedding');
    }
    final limit = maxCorpusPoints < 0 ? 0 : maxCorpusPoints;
    final selected = <String, LineageEmbedding>{};
    final laneByEmbedding = <String, RetrievalLane>{};
    final candidateByEmbedding = <String, CandidateRecord>{};
    final evidenceByCandidate = <String, EvidenceRecord>{
      for (final evidence in snapshot.evidence) evidence.candidateId: evidence,
    };

    Future<void> addCandidate(CandidateRecord candidate) async {
      if (selected.length >= limit) return;
      final embeddingId = candidate.embeddingId;
      if (embeddingId == null || selected.containsKey(embeddingId)) return;
      final embedding = await lineageStore.embeddingById(embeddingId);
      if (embedding == null ||
          embedding.dimension != query.dimension ||
          embedding.modelIdentity != query.modelIdentity) {
        return;
      }
      selected[embeddingId] = embedding;
      laneByEmbedding[embeddingId] = candidate.lane;
      candidateByEmbedding[embeddingId] = candidate;
    }

    final activeCandidates =
        snapshot.candidates
            .where(
              (candidate) =>
                  candidate.lane == RetrievalLane.active &&
                  candidate.strategyId == snapshot.trace.activeStrategyId,
            )
            .toList(growable: false)
          ..sort(_candidateRankCompare);
    for (final candidate in activeCandidates) {
      await addCandidate(candidate);
    }
    final shadowCandidates =
        snapshot.candidates
            .where((candidate) => candidate.lane == RetrievalLane.shadow)
            .toList(growable: false)
          ..sort(_candidateRankCompare);
    for (final candidate in shadowCandidates) {
      await addCandidate(candidate);
    }

    final bodyEmbeddings = await lineageStore.embeddingsForRepresentation(
      EmbeddingRepresentation.body,
    );
    final byDocument = <String, List<LineageEmbedding>>{};
    for (final embedding in bodyEmbeddings) {
      if (embedding.dimension != query.dimension ||
          embedding.modelIdentity != query.modelIdentity ||
          selected.containsKey(embedding.embeddingId)) {
        continue;
      }
      (byDocument[embedding.documentId ?? ''] ??= <LineageEmbedding>[]).add(
        embedding,
      );
    }
    for (final rows in byDocument.values) {
      rows.sort((a, b) => a.embeddingId.compareTo(b.embeddingId));
    }
    final documentIds = byDocument.keys.toList()..sort();
    var offset = 0;
    while (selected.length < limit) {
      var added = false;
      for (final documentId in documentIds) {
        final rows = byDocument[documentId]!;
        if (offset >= rows.length) continue;
        final embedding = rows[offset];
        selected[embedding.embeddingId] = embedding;
        added = true;
        if (selected.length >= limit) break;
      }
      if (!added) break;
      offset++;
    }

    final pcaInput = <PcaInput>[
      for (final embedding in selected.values)
        PcaInput(embedding.embeddingId, embedding.vector),
      PcaInput(query.embeddingId, query.vector),
    ];
    final projection = projector.project(pcaInput, components: 3);
    final coordinates = <String, PcaPoint>{
      for (final point in projection.points) point.id: point,
    };
    final points = <TraceVectorPoint>[];
    for (final embedding in selected.values) {
      final coordinate = coordinates[embedding.embeddingId]!;
      final chunk = embedding.chunkId == null
          ? null
          : await lexicalStore.getChunk(embedding.chunkId!);
      final candidate = candidateByEmbedding[embedding.embeddingId];
      final evidence = candidate == null
          ? null
          : evidenceByCandidate[candidate.candidateId];
      points.add(
        TraceVectorPoint(
          embeddingId: embedding.embeddingId,
          chunkId: embedding.chunkId,
          documentId: embedding.documentId,
          sourceName: chunk?.sourceName ?? '来源未捕获',
          locator: chunk?.locator ?? '',
          representation: embedding.representation,
          x: coordinate.x,
          y: coordinate.y,
          z: coordinate.z,
          cosineToQuery: _cosine(query.vector, embedding.vector),
          isQuery: false,
          lane: laneByEmbedding[embedding.embeddingId],
          text: chunk?.text ?? '',
          candidateId: candidate?.candidateId,
          sourceChannels: candidate?.sourceChannels,
          selectedForEvidence:
              evidence != null || (candidate?.selectedForEvidence ?? false),
          selectionReason: evidence?.selectionReason,
          dropReason: candidate?.dropReason,
          ftsRank: candidate?.ftsRank,
          vectorRank: candidate?.vectorRank,
          finalRank: candidate?.finalRank,
        ),
      );
    }
    final queryCoordinate = coordinates[query.embeddingId]!;
    points.add(
      TraceVectorPoint(
        embeddingId: query.embeddingId,
        chunkId: null,
        documentId: null,
        sourceName: 'Query',
        locator: '',
        representation: EmbeddingRepresentation.query,
        x: queryCoordinate.x,
        y: queryCoordinate.y,
        z: queryCoordinate.z,
        cosineToQuery: 1,
        isQuery: true,
        lane: RetrievalLane.active,
        text: snapshot.trace.queryText,
        candidateId: null,
        sourceChannels: null,
        selectedForEvidence: false,
        selectionReason: null,
        dropReason: null,
        ftsRank: null,
        vectorRank: null,
        finalRank: null,
      ),
    );
    final neighbors = points.where((point) => !point.isQuery).toList()
      ..sort((a, b) => b.cosineToQuery.compareTo(a.cosineToQuery));
    return TraceVectorSpaceSnapshot(
      queryEmbeddingId: query.embeddingId,
      queryVectorSha256: query.vectorSha256,
      usedCapturedQuery: true,
      samplePolicy:
          'ACTIVE hits → SHADOW hits → deterministic document-stratified body fill',
      totalPersistentBodyCount: bodyEmbeddings.length,
      points: List<TraceVectorPoint>.unmodifiable(points),
      neighbors: List<TraceVectorPoint>.unmodifiable(neighbors.take(10)),
      explainedVarianceRatios: projection.explainedVarianceRatios,
      originalDimension: projection.originalDimension,
      effectiveComponentCount: projection.explainedVarianceRatios
          .where((ratio) => ratio.isFinite && ratio > 1e-9)
          .length,
    );
  }

  static int _candidateRankCompare(CandidateRecord a, CandidateRecord b) {
    final rankA =
        a.finalRank ??
        a.rerankRank ??
        a.fusionRank ??
        a.vectorRank ??
        a.ftsRank ??
        1 << 30;
    final rankB =
        b.finalRank ??
        b.rerankRank ??
        b.fusionRank ??
        b.vectorRank ??
        b.ftsRank ??
        1 << 30;
    final rank = rankA.compareTo(rankB);
    return rank != 0 ? rank : a.candidateId.compareTo(b.candidateId);
  }

  double _cosine(List<double> left, List<double> right) {
    if (left.length != right.length || left.isEmpty) return 0;
    var dot = 0.0;
    var leftNorm = 0.0;
    var rightNorm = 0.0;
    for (var index = 0; index < left.length; index++) {
      dot += left[index] * right[index];
      leftNorm += left[index] * left[index];
      rightNorm += right[index] * right[index];
    }
    if (leftNorm == 0 || rightNorm == 0) return 0;
    return (dot / math.sqrt(leftNorm * rightNorm)).clamp(-1.0, 1.0).toDouble();
  }
}
