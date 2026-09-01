import 'package:flutter_test/flutter_test.dart';
import 'package:pocketgallery_phone_pilot/acceptance/vector_acceptance.dart';
import 'package:pocketgallery_phone_pilot/core/models.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_ids.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_models.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_store.dart';
import 'package:pocketgallery_phone_pilot/observability/trace_vector_space_service.dart';
import 'package:pocketgallery_phone_pilot/services/knowledge_engine.dart';
import 'package:pocketgallery_phone_pilot/services/lexical_fts_store.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('real four-dimensional trace produces truthful three-dimensional evidence', () async {
    final artifact = await _seedArtifact();

    final result = VectorTruthVerifier.verify(artifact);

    expect(result.passed, isTrue);
    expect(result.reasonCodes, isEmpty);
    expect(artifact.vectorSpace.originalDimension, 4);
    expect(artifact.vectorSpace.effectiveComponentCount, 3);
    expect(artifact.vectorSpace.points.where((point) => point.isQuery), hasLength(1));
    expect(
      artifact.vectorSpace.points.where((point) => !point.isQuery),
      hasLength(3),
    );
  });

  test('truth verifier rejects synthetic, flat, incomplete, or non-finite evidence', () async {
    final valid = await _seedArtifact();
    final query = valid.vectorSpace.points.singleWhere((point) => point.isQuery);
    final candidate = valid.vectorSpace.points.firstWhere(
      (point) => !point.isQuery,
    );
    final cases = <String, VectorAcceptanceArtifact>{
      'ORIGINAL_DIMENSION_NOT_HIGH': _withSpace(
        valid,
        originalDimension: 3,
      ),
      'PCA_THREE_COMPONENTS_UNAVAILABLE': _withSpace(
        valid,
        effectiveComponentCount: 2,
        explainedVarianceRatios: const <double>[0.7, 0.3],
      ),
      'CAPTURED_QUERY_NOT_USED': _withSpace(
        valid,
        usedCapturedQuery: false,
      ),
      'NON_FINITE_COORDINATE': _withSpace(
        valid,
        points: <TraceVectorPoint>[
          _point(candidate, x: double.nan),
          ...valid.vectorSpace.points.where(
            (point) => point.embeddingId != candidate.embeddingId,
          ),
        ],
      ),
      'QUERY_EMBEDDING_ID_MISMATCH': _withSpace(
        valid,
        queryEmbeddingId: 'not-the-captured-query',
      ),
      'NON_QUERY_POINT_MISSING': _withSpace(
        valid,
        points: <TraceVectorPoint>[query],
        neighbors: const <TraceVectorPoint>[],
      ),
      'CANDIDATE_EXPLANATION_MISSING': _withSpace(
        valid,
        points: <TraceVectorPoint>[
          _point(
            candidate,
            selectedForEvidence: true,
            selectionReason: null,
            dropReason: null,
          ),
          ...valid.vectorSpace.points.where(
            (point) => point.embeddingId != candidate.embeddingId,
          ),
        ],
      ),
    };

    for (final entry in cases.entries) {
      expect(
        VectorTruthVerifier.verify(entry.value).reasonCodes,
        contains(entry.key),
        reason: entry.key,
      );
    }
  });
}

Future<VectorAcceptanceArtifact> _seedArtifact() async {
  final lineageDatabase = sqlite3.openInMemory();
  final lexicalDatabase = sqlite3.openInMemory();
  addTearDown(lineageDatabase.close);
  addTearDown(lexicalDatabase.close);
  final lineage = LineageStore(database: lineageDatabase);
  final lexical = LexicalFtsStore(database: lexicalDatabase);
  await lineage.initialize();
  const traceId = 'trace-r50-vector-truth';
  const strategyId = 'active.r50-vector-truth';

  await lineage.putTrace(
    LineageTrace(
      traceId: traceId,
      sessionId: 'session-r50',
      turnId: 'turn-r50',
      queryText: 'four dimensional captured query',
      requestedMode: 'knowledge',
      finalMode: 'knowledge',
      scopeJson: '{"type":"all"}',
      activeStrategyId: strategyId,
      startedAt: DateTime.utc(2026, 9, 1),
      completedAt: DateTime.utc(2026, 9, 1, 0, 0, 1),
      status: TraceStatus.complete,
      failureStage: null,
      failureCode: null,
    ),
  );
  await lineage.putEmbedding(
    LineageEmbedding.test(
      embeddingId: LineageIds.queryEmbeddingId(traceId),
      sourceKind: 'query',
      sourceId: traceId,
      chunkId: null,
      representation: EmbeddingRepresentation.query,
      vector: const <double>[1, 0, 0, 0],
      modelIdentity: 'EmbeddingGemma-r50-test',
      taskMode: 'retrieval_query',
    ),
  );

  const chunks = <PgChunk>[
    PgChunk(
      id: 'chunk-r50-1',
      documentId: 'document-r50-1',
      sourceName: 'one.md',
      locator: 'section 1',
      ordinal: 0,
      text: 'first captured candidate',
    ),
    PgChunk(
      id: 'chunk-r50-2',
      documentId: 'document-r50-2',
      sourceName: 'two.md',
      locator: 'section 2',
      ordinal: 0,
      text: 'second captured candidate',
    ),
    PgChunk(
      id: 'chunk-r50-3',
      documentId: 'document-r50-3',
      sourceName: 'three.md',
      locator: 'section 3',
      ordinal: 0,
      text: 'third captured candidate',
    ),
  ];
  const vectors = <List<double>>[
    <double>[0.8, 0.2, 0, 0],
    <double>[0, 0.7, 0.3, 0],
    <double>[0, 0, 0.6, 0.4],
  ];
  for (var index = 0; index < chunks.length; index += 1) {
    final chunk = chunks[index];
    await lexical.replaceDocument(
      ImportedDocument(
        documentId: chunk.documentId,
        sourceName: chunk.sourceName,
        sha256: 'sha-${chunk.documentId}',
        chunks: <PgChunk>[chunk],
      ),
    );
    final embeddingId = 'embedding-r50-${index + 1}';
    await lineage.putEmbedding(
      LineageEmbedding.test(
        embeddingId: embeddingId,
        sourceKind: 'chunk',
        sourceId: chunk.id,
        documentId: chunk.documentId,
        chunkId: chunk.id,
        representation: EmbeddingRepresentation.body,
        vector: vectors[index],
        modelIdentity: 'EmbeddingGemma-r50-test',
        taskMode: 'retrieval_document',
      ),
    );
    final candidateId = LineageIds.candidateId(
      traceId,
      strategyId,
      chunk.id,
    );
    await lineage.putCandidate(
      CandidateRecord(
        candidateId: candidateId,
        traceId: traceId,
        strategyId: strategyId,
        lane: RetrievalLane.active,
        chunkId: chunk.id,
        embeddingId: embeddingId,
        sourceChannels: 'vector',
        ftsRank: null,
        rawBm25: null,
        vectorRank: index + 1,
        rawCosine: 0.9 - index * 0.1,
        fusionRank: index + 1,
        fusionScore: 0.04 - index * 0.005,
        rerankRank: null,
        rerankScore: null,
        finalRank: index + 1,
        selectedForEvidence: index == 0,
        dropReason: index == 0 ? null : 'max_evidence',
      ),
    );
    if (index == 0) {
      await lineage.putEvidence(
        EvidenceRecord(
          evidenceId: LineageIds.evidenceId(
            traceId,
            strategyId,
            chunk.id,
          ),
          traceId: traceId,
          strategyId: strategyId,
          lane: RetrievalLane.active,
          anchor: 'E1',
          candidateId: candidateId,
          chunkId: chunk.id,
          selectionRank: 1,
          score: 0.04,
          tokenCount: 12,
          selectionReason: 'direct_support',
        ),
      );
    }
  }

  final engine = KnowledgeEngine(
    lexicalStore: lexical,
    lineageStore: lineage,
  );
  return const VectorAcceptanceCapture().capture(engine, traceId);
}

VectorAcceptanceArtifact _withSpace(
  VectorAcceptanceArtifact source, {
  String? queryEmbeddingId,
  bool? usedCapturedQuery,
  List<TraceVectorPoint>? points,
  List<TraceVectorPoint>? neighbors,
  List<double>? explainedVarianceRatios,
  int? originalDimension,
  int? effectiveComponentCount,
}) {
  final space = source.vectorSpace;
  return VectorAcceptanceArtifact(
    traceId: source.traceId,
    trace: source.trace,
    vectorSpace: TraceVectorSpaceSnapshot(
      queryEmbeddingId: queryEmbeddingId ?? space.queryEmbeddingId,
      queryVectorSha256: space.queryVectorSha256,
      usedCapturedQuery: usedCapturedQuery ?? space.usedCapturedQuery,
      samplePolicy: space.samplePolicy,
      totalPersistentBodyCount: space.totalPersistentBodyCount,
      points: points ?? space.points,
      neighbors: neighbors ?? space.neighbors,
      explainedVarianceRatios:
          explainedVarianceRatios ?? space.explainedVarianceRatios,
      originalDimension: originalDimension ?? space.originalDimension,
      effectiveComponentCount:
          effectiveComponentCount ?? space.effectiveComponentCount,
    ),
  );
}

TraceVectorPoint _point(
  TraceVectorPoint source, {
  double? x,
  bool? selectedForEvidence,
  String? selectionReason,
  String? dropReason,
}) {
  return TraceVectorPoint(
    embeddingId: source.embeddingId,
    chunkId: source.chunkId,
    documentId: source.documentId,
    sourceName: source.sourceName,
    locator: source.locator,
    representation: source.representation,
    x: x ?? source.x,
    y: source.y,
    z: source.z,
    cosineToQuery: source.cosineToQuery,
    isQuery: source.isQuery,
    lane: source.lane,
    text: source.text,
    candidateId: source.candidateId,
    sourceChannels: source.sourceChannels,
    selectedForEvidence:
        selectedForEvidence ?? source.selectedForEvidence,
    selectionReason: selectionReason,
    dropReason: dropReason,
    ftsRank: source.ftsRank,
    vectorRank: source.vectorRank,
    finalRank: source.finalRank,
  );
}
