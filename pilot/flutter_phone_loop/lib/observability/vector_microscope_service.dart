import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import '../chat/chat_models.dart';
import '../core/models.dart';
import '../services/lexical_fts_store.dart';
import '../services/semantic_store.dart';
import 'pca_projector.dart';
import 'vector_observation_store.dart';

class VectorNeighbor {
  const VectorNeighbor({
    required this.chunk,
    required this.cosine,
    required this.norm,
  });

  final PgChunk chunk;
  final double cosine;
  final double norm;
}

class VectorMapPoint {
  const VectorMapPoint({
    required this.id,
    required this.documentId,
    required this.sourceName,
    required this.locator,
    required this.x,
    required this.y,
    required this.z,
    required this.cosineToQuery,
    required this.isQuery,
  });

  final String id;
  final String documentId;
  final String sourceName;
  final String locator;
  final double x;
  final double y;
  final double z;
  final double? cosineToQuery;
  final bool isQuery;
}

class VectorMicroscopeSnapshot {
  const VectorMicroscopeSnapshot({
    required this.query,
    required this.modelIdentity,
    required this.dimension,
    required this.queryNorm,
    required this.queryFingerprint,
    required this.points,
    required this.neighbors,
    required this.explainedVarianceRatios,
  });

  final String query;
  final String modelIdentity;
  final int dimension;
  final double queryNorm;
  final String queryFingerprint;
  final List<VectorMapPoint> points;
  final List<VectorNeighbor> neighbors;
  final List<double> explainedVarianceRatios;
}

class VectorMicroscopeService {
  VectorMicroscopeService({
    required this.semanticStore,
    required this.lexicalStore,
    PcaProjector? projector,
  }) : projector = projector ?? const PcaProjector(iterations: 48);

  final SemanticStore semanticStore;
  final LexicalFtsStore lexicalStore;
  final PcaProjector projector;

  Future<VectorMicroscopeSnapshot> build(
    String query, {
    KnowledgeScope scope = const KnowledgeScope.all(),
    Iterable<String> preferredChunkIds = const [],
    int maxPoints = 250,
  }) async {
    final queryVector = await semanticStore.observeQueryVector(query);
    final queryNorm = _norm(queryVector);
    final fingerprint = sha256
        .convert(VectorObservationStore.encodeFloat32(queryVector))
        .toString();

    final observations = scope.isAll
        ? await semanticStore.observationStore.listAll(limit: maxPoints)
        : await semanticStore.observationStore.listForDocuments(
            scope.documentIds ?? const <String>{},
          );

    final byId = <String, VectorObservation>{
      for (final observation in observations.take(maxPoints))
        observation.chunkId: observation,
    };
    for (final id in preferredChunkIds) {
      if (byId.length >= maxPoints && byId.containsKey(id)) continue;
      final observation = await semanticStore.observationStore.getChunkVector(
        id,
      );
      if (observation != null) byId[id] = observation;
    }

    final selected = byId.values.toList()
      ..sort((a, b) {
        final doc = a.documentId.compareTo(b.documentId);
        return doc != 0 ? doc : a.chunkId.compareTo(b.chunkId);
      });
    if (selected.length > maxPoints) {
      selected.removeRange(maxPoints, selected.length);
    }

    final pcaInput = <PcaInput>[
      for (final observation in selected)
        PcaInput(observation.chunkId, observation.vector),
      PcaInput('__query__', queryVector),
    ];
    final projection = projector.project(pcaInput, components: 3);
    final coords = {for (final point in projection.points) point.id: point};

    final neighborRows =
        <({VectorObservation observation, PgChunk chunk, double cosine})>[];
    final points = <VectorMapPoint>[];
    for (final observation in selected) {
      final chunk = await lexicalStore.getChunk(observation.chunkId);
      if (chunk == null) continue;
      final cosine = _cosine(
        queryVector,
        queryNorm,
        observation.vector,
        observation.norm,
      );
      neighborRows.add((
        observation: observation,
        chunk: chunk,
        cosine: cosine,
      ));
      final point = coords[observation.chunkId]!;
      points.add(
        VectorMapPoint(
          id: observation.chunkId,
          documentId: observation.documentId,
          sourceName: chunk.sourceName,
          locator: chunk.locator,
          x: point.x,
          y: point.y,
          z: point.z,
          cosineToQuery: cosine,
          isQuery: false,
        ),
      );
    }
    neighborRows.sort((a, b) => b.cosine.compareTo(a.cosine));

    final q = coords['__query__'];
    if (q != null) {
      points.add(
        VectorMapPoint(
          id: '__query__',
          documentId: '',
          sourceName: 'Query',
          locator: '',
          x: q.x,
          y: q.y,
          z: q.z,
          cosineToQuery: 1,
          isQuery: true,
        ),
      );
    }

    return VectorMicroscopeSnapshot(
      query: query,
      modelIdentity: selected.isEmpty
          ? SemanticStore.embeddingModelIdentity
          : selected.first.modelIdentity,
      dimension: queryVector.length,
      queryNorm: queryNorm,
      queryFingerprint: 'sha256:$fingerprint',
      points: points,
      neighbors: [
        for (final row in neighborRows.take(10))
          VectorNeighbor(
            chunk: row.chunk,
            cosine: row.cosine,
            norm: row.observation.norm,
          ),
      ],
      explainedVarianceRatios: projection.explainedVarianceRatios,
    );
  }

  double _cosine(
    List<double> query,
    double queryNorm,
    List<double> vector,
    double vectorNorm,
  ) {
    if (query.length != vector.length || queryNorm == 0 || vectorNorm == 0) {
      return 0;
    }
    var dot = 0.0;
    for (var i = 0; i < query.length; i++) {
      dot += query[i] * vector[i];
    }
    return (dot / (queryNorm * vectorNorm)).clamp(-1.0, 1.0).toDouble();
  }

  double _norm(List<double> vector) {
    var sum = 0.0;
    for (final value in vector) {
      sum += value * value;
    }
    return math.sqrt(sum);
  }
}
