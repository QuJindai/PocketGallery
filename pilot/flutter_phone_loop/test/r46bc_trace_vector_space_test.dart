import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:pocketgallery_phone_pilot/core/models.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_ids.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_models.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_store.dart';
import 'package:pocketgallery_phone_pilot/lineage/trace_snapshot.dart';
import 'package:pocketgallery_phone_pilot/observability/trace_vector_space_service.dart';
import 'package:pocketgallery_phone_pilot/services/lexical_fts_store.dart';

void main() {
  test('trace vector sample uses captured query then active and shadow hits',
      () async {
    final lineageDb = sqlite3.openInMemory();
    final lexicalDb = sqlite3.openInMemory();
    addTearDown(lineageDb.close);
    addTearDown(lexicalDb.close);
    final store = LineageStore(database: lineageDb);
    final lexical = LexicalFtsStore(database: lexicalDb);
    await store.initialize();
    const traceId = 'tr-vector-sample';
    const activeStrategy = 'active.r45-body-hybrid';
    const shadowStrategy = 'shadow.heading-body-multivector';
    await store.putTrace(LineageTrace(
      traceId: traceId,
      sessionId: 's1',
      turnId: 't1',
      queryText: 'sample query',
      requestedMode: 'auto',
      finalMode: 'knowledge',
      scopeJson: '{"type":"all"}',
      activeStrategyId: activeStrategy,
      startedAt: DateTime.utc(2026, 8, 31),
      completedAt: DateTime.utc(2026, 8, 31, 0, 0, 1),
      status: TraceStatus.complete,
      failureStage: null,
      failureCode: null,
    ));
    await store.putEmbedding(LineageEmbedding.test(
      embeddingId: LineageIds.queryEmbeddingId(traceId),
      sourceKind: 'query',
      sourceId: traceId,
      chunkId: null,
      representation: EmbeddingRepresentation.query,
      vector: const <double>[1, 0],
      modelIdentity: 'EmbeddingGemma-test',
      taskMode: 'retrieval_query',
    ));
    final chunks = <PgChunk>[
      const PgChunk(
        id: 'c-active',
        documentId: 'd1',
        sourceName: 'd1.md',
        locator: 's1',
        ordinal: 0,
        text: 'active candidate',
      ),
      const PgChunk(
        id: 'c-shadow',
        documentId: 'd2',
        sourceName: 'd2.md',
        locator: 's1',
        ordinal: 0,
        text: 'shadow candidate',
      ),
      const PgChunk(
        id: 'c-fill-a',
        documentId: 'd1',
        sourceName: 'd1.md',
        locator: 's2',
        ordinal: 1,
        text: 'fill a',
      ),
      const PgChunk(
        id: 'c-fill-b',
        documentId: 'd3',
        sourceName: 'd3.md',
        locator: 's1',
        ordinal: 0,
        text: 'fill b',
      ),
      const PgChunk(
        id: 'c-stale',
        documentId: 'd-stale',
        sourceName: 'stale.md',
        locator: 's1',
        ordinal: 0,
        text: 'same dimension but stale model',
      ),
    ];
    for (final documentId in chunks.map((chunk) => chunk.documentId).toSet()) {
      final documentChunks = chunks
          .where((chunk) => chunk.documentId == documentId)
          .toList(growable: false);
      await lexical.replaceDocument(ImportedDocument(
        documentId: documentId,
        sourceName: documentChunks.first.sourceName,
        sha256: 'sha-$documentId',
        chunks: documentChunks,
      ));
    }
    for (final chunk in chunks) {
      await store.putEmbedding(LineageEmbedding.test(
        embeddingId: 'emb-${chunk.id}',
        sourceKind: 'chunk',
        sourceId: chunk.id,
        documentId: chunk.documentId,
        chunkId: chunk.id,
        representation: chunk.id == 'c-shadow'
            ? EmbeddingRepresentation.heading
            : EmbeddingRepresentation.body,
        vector: <double>[
          chunk.id == 'c-active' ? 1 : 0.5,
          chunk.id == 'c-active' ? 0 : 0.5,
        ],
        modelIdentity: chunk.id == 'c-stale'
            ? 'EmbeddingGemma-stale'
            : 'EmbeddingGemma-test',
        taskMode: 'retrieval_document',
      ));
    }
    await store.putCandidate(CandidateRecord(
      candidateId: LineageIds.candidateId(
        traceId,
        activeStrategy,
        'c-active',
      ),
      traceId: traceId,
      strategyId: activeStrategy,
      lane: RetrievalLane.active,
      chunkId: 'c-active',
      embeddingId: 'emb-c-active',
      sourceChannels: 'vector',
      ftsRank: null,
      rawBm25: null,
      vectorRank: 1,
      rawCosine: 1,
      fusionRank: 1,
      fusionScore: 0.04,
      rerankRank: null,
      rerankScore: null,
      finalRank: 1,
      selectedForEvidence: true,
      dropReason: null,
    ));
    await store.putCandidate(CandidateRecord(
      candidateId: LineageIds.candidateId(
        traceId,
        shadowStrategy,
        'c-shadow',
      ),
      traceId: traceId,
      strategyId: shadowStrategy,
      lane: RetrievalLane.shadow,
      chunkId: 'c-shadow',
      embeddingId: 'emb-c-shadow',
      sourceChannels: 'heading',
      ftsRank: null,
      rawBm25: null,
      vectorRank: 1,
      rawCosine: 0.7,
      fusionRank: 1,
      fusionScore: 0.03,
      rerankRank: null,
      rerankScore: null,
      finalRank: 1,
      selectedForEvidence: false,
      dropReason: null,
    ));

    final snapshot = await TraceSnapshot.load(store, traceId);
    final result = await TraceVectorSpaceService(
      lineageStore: store,
      lexicalStore: lexical,
    ).build(snapshot, maxCorpusPoints: 10);

    expect(result.queryEmbeddingId, LineageIds.queryEmbeddingId(traceId));
    expect(
      result.queryVectorSha256,
      snapshot.queryEmbedding!.vectorSha256,
    );
    expect(result.usedCapturedQuery, isTrue);
    expect(
      result.points
          .where((point) => !point.isQuery)
          .map((point) => point.embeddingId)
          .take(2),
      orderedEquals(<String>['emb-c-active', 'emb-c-shadow']),
    );
    expect(result.points.where((point) => !point.isQuery), hasLength(4));
    expect(
      result.points.map((point) => point.embeddingId),
      isNot(contains('emb-c-stale')),
    );
    expect(result.samplePolicy, contains('ACTIVE hits'));
    expect(result.samplePolicy, contains('SHADOW hits'));
  });
}
