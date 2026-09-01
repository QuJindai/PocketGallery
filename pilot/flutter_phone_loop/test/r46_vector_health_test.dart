import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:pocketgallery_phone_pilot/chat/chat_models.dart';
import 'package:pocketgallery_phone_pilot/core/models.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_ids.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_models.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_store.dart';
import 'package:pocketgallery_phone_pilot/lineage/runtime_lineage_recorder.dart';
import 'package:pocketgallery_phone_pilot/lineage/vector_index_health_service.dart';
import 'package:pocketgallery_phone_pilot/retrieval/active_vector_index.dart';
import 'package:pocketgallery_phone_pilot/services/lexical_fts_store.dart';

class _ProbeIndex implements ActiveVectorIndex {
  bool searchSucceeds = false;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> add(VectorIndexRecord record) async {}

  @override
  Future<void> remove(String embeddingId) async {}

  @override
  Future<List<VectorSearchHit>> searchByEmbedding({
    required List<double> queryEmbedding,
    required int topK,
    required KnowledgeScope scope,
  }) async {
    if (!searchSucceeds) return const <VectorSearchHit>[];
    return <VectorSearchHit>[
      VectorSearchHit(
        embeddingId: LineageIds.bodyEmbeddingId('c1'),
        chunkId: 'c1',
        documentId: 'd1',
        similarity: 1,
        rank: 1,
      ),
    ];
  }

  @override
  Future<VectorIndexProbe> probe() async => const VectorIndexProbe(
    initialized: true,
    databasePath: 'memory://health',
    backendId: 'probe-index',
    searchVerified: false,
  );

  @override
  Future<void> close() async {}
}

void main() {
  test(
    'ACTIVE health requires persisted body vectors, commit and real search',
    () async {
      final lexicalDb = sqlite3.openInMemory();
      final lineageDb = sqlite3.openInMemory();
      addTearDown(lexicalDb.close);
      addTearDown(lineageDb.close);
      final lexical = LexicalFtsStore(database: lexicalDb);
      await lexical.replaceDocument(
        const ImportedDocument(
          documentId: 'd1',
          sourceName: 'doc.md',
          sha256: 'sha-d1',
          chunks: <PgChunk>[
            PgChunk(
              id: 'c1',
              documentId: 'd1',
              sourceName: 'doc.md',
              locator: 's1',
              ordinal: 0,
              text: 'health probe content',
            ),
          ],
        ),
      );
      final lineage = LineageStore(database: lineageDb);
      final index = _ProbeIndex();
      var activeModel = 'model-v1';
      final service = VectorIndexHealthService(
        lexicalStore: lexical,
        lineageStore: lineage,
        activeVectorIndex: index,
        activeModelIdentity: () => activeModel,
      );
      final bodyId = LineageIds.bodyEmbeddingId('c1');

      final missing = await service.snapshot();
      expect(missing.required, 1);
      expect(missing.generated, 0);
      expect(missing.persisted, 0);
      expect(missing.pending, 1);
      expect(missing.ready, isFalse);

      await lineage.putEmbedding(
        LineageEmbedding.test(
          embeddingId: bodyId,
          sourceKind: 'chunk',
          sourceId: 'c1',
          documentId: 'd1',
          chunkId: 'c1',
          representation: EmbeddingRepresentation.body,
          vector: const <double>[1, 0],
          modelIdentity: 'model-v1',
          taskMode: 'retrieval_document',
        ),
      );
      final persistedOnly = await service.snapshot();
      expect(persistedOnly.generated, 1);
      expect(persistedOnly.persisted, 1);
      expect(persistedOnly.indexed, 0);
      expect(persistedOnly.pending, 1);
      expect(persistedOnly.ready, isFalse);

      await lineage.putVectorIndexEntry(
        VectorIndexEntryRecord(
          indexEntryId: LineageIds.vectorIndexEntryId(
            bodyId,
            'probe-index',
            RuntimeLineageRecorder.activeStrategyId,
            RetrievalLane.active,
          ),
          embeddingId: bodyId,
          backendId: 'probe-index',
          strategyId: RuntimeLineageRecorder.activeStrategyId,
          lane: RetrievalLane.active,
          commitStatus: VectorCommitStatus.pending,
          committedAt: null,
          failureCode: null,
          failureDetail: null,
        ),
      );
      expect((await service.snapshot()).ready, isFalse);

      await lineage.putVectorIndexEntry(
        VectorIndexEntryRecord(
          indexEntryId: LineageIds.vectorIndexEntryId(
            bodyId,
            'probe-index',
            RuntimeLineageRecorder.activeStrategyId,
            RetrievalLane.active,
          ),
          embeddingId: bodyId,
          backendId: 'probe-index',
          strategyId: RuntimeLineageRecorder.activeStrategyId,
          lane: RetrievalLane.active,
          commitStatus: VectorCommitStatus.committed,
          committedAt: DateTime.utc(2026, 8, 29),
          failureCode: null,
          failureDetail: null,
        ),
      );
      final unverified = await service.snapshot();
      expect(unverified.indexed, 1);
      expect(unverified.searchVerified, isFalse);
      expect(unverified.ready, isFalse);

      index.searchSucceeds = true;
      activeModel = 'model-v2';
      final stale = await service.snapshot();
      expect(stale.staleModel, 1);
      expect(stale.ready, isFalse);

      activeModel = 'model-v1';
      final healthy = await service.snapshot();
      expect(healthy.searchVerified, isTrue);
      expect(healthy.pending, 0);
      expect(healthy.failed, 0);
      expect(healthy.ready, isTrue);

      final headingId = LineageIds.embeddingId(
        sourceKind: 'chunk',
        sourceId: 'c1',
        representation: EmbeddingRepresentation.heading,
      );
      await lineage.putEmbedding(
        LineageEmbedding.test(
          embeddingId: headingId,
          sourceKind: 'chunk',
          sourceId: 'c1',
          documentId: 'd1',
          chunkId: 'c1',
          representation: EmbeddingRepresentation.heading,
          vector: const <double>[0, 1],
          modelIdentity: 'model-v1',
          taskMode: 'retrieval_document',
        ),
      );
      await lineage.putVectorIndexEntry(
        VectorIndexEntryRecord(
          indexEntryId: LineageIds.vectorIndexEntryId(
            headingId,
            'probe-index',
            'shadow.heading',
            RetrievalLane.shadow,
          ),
          embeddingId: headingId,
          backendId: 'probe-index',
          strategyId: 'shadow.heading',
          lane: RetrievalLane.shadow,
          commitStatus: VectorCommitStatus.failed,
          committedAt: null,
          failureCode: 'SHADOW_FAILED',
          failureDetail: null,
        ),
      );
      expect(
        (await service.snapshot()).ready,
        isTrue,
        reason: 'SHADOW representations never gate ACTIVE readiness',
      );
    },
  );

  test(
    'Chunk Explorer separates legacy observations from R4.6 ACTIVE health',
    () async {
      final source = await File(
        'lib/ui/microscope/chunk_explorer_page.dart',
      ).readAsString();
      expect(source, contains('Legacy observation'));
      expect(source, contains('R4.6 ACTIVE Vector'));
      expect(source, contains('Generated'));
      expect(source, contains('Persisted'));
      expect(source, contains('Search Verified'));
    },
  );
}
