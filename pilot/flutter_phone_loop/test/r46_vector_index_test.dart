import 'package:flutter_test/flutter_test.dart';

import 'package:pocketgallery_phone_pilot/chat/chat_models.dart';
import 'package:pocketgallery_phone_pilot/retrieval/active_vector_index.dart';
import 'package:pocketgallery_phone_pilot/retrieval/sqlite_active_vector_index.dart';

class RecordingVectorBackend implements ActiveVectorBackend {
  bool initialized = false;
  String? initializedPath;
  String? lastAddedId;
  List<double>? lastAddedEmbedding;
  List<double>? lastQueryEmbedding;
  int? lastTopK;
  List<BackendVectorHit> nextHits = const [];
  final removed = <String>[];

  @override
  bool get isInitialized => initialized;

  @override
  Future<void> initialize(String databasePath) async {
    initialized = true;
    initializedPath = databasePath;
  }

  @override
  Future<void> add({
    required String id,
    required String content,
    required List<double> embedding,
    required String metadataJson,
  }) async {
    lastAddedId = id;
    lastAddedEmbedding = embedding;
  }

  @override
  Future<void> remove(String id) async {
    removed.add(id);
  }

  @override
  Future<List<BackendVectorHit>> search({
    required List<double> queryEmbedding,
    required int topK,
  }) async {
    lastQueryEmbedding = queryEmbedding;
    lastTopK = topK;
    return nextHits.take(topK).toList(growable: false);
  }

  @override
  Future<void> close() async {
    initialized = false;
  }
}

void main() {
  test(
    'explicit vector adapter indexes by embedding id and searches the supplied query vector',
    () async {
      final backend = RecordingVectorBackend();
      final index = SqliteActiveVectorIndex.forTest(backend);
      await index.initialize();

      const documentVector = [1.0, 0.0];
      const query = [0.25, 0.75];
      await index.add(
        const VectorIndexRecord(
          embeddingId: 'emb-body-1',
          chunkId: 'chunk-1',
          documentId: 'doc-1',
          content: '端侧模型性能测试',
          embedding: documentVector,
          modelIdentity: 'EmbeddingGemma-test',
        ),
      );
      backend.nextHits = const [
        BackendVectorHit(
          id: 'emb-body-1',
          similarity: 0.81,
          metadataJson:
              '{"chunkId":"chunk-1","documentId":"doc-1","modelIdentity":"EmbeddingGemma-test"}',
        ),
      ];

      final hits = await index.searchByEmbedding(
        queryEmbedding: query,
        topK: 5,
        scope: const KnowledgeScope.all(),
      );

      expect(backend.lastAddedId, 'emb-body-1');
      expect(backend.lastAddedId, isNot('chunk-1'));
      expect(identical(backend.lastAddedEmbedding, documentVector), isTrue);
      expect(identical(backend.lastQueryEmbedding, query), isTrue);
      expect(hits.single.embeddingId, 'emb-body-1');
      expect(hits.single.chunkId, 'chunk-1');
      expect(hits.single.documentId, 'doc-1');
      expect(hits.single.similarity, 0.81);
      expect(hits.single.rank, 1);
    },
  );

  test(
    'document scope is enforced after deterministic overfetch without changing the query vector',
    () async {
      final backend = RecordingVectorBackend();
      final index = SqliteActiveVectorIndex.forTest(backend);
      await index.initialize();
      const query = [0.4, 0.6];
      backend.nextHits = const [
        BackendVectorHit(
          id: 'emb-other',
          similarity: 0.95,
          metadataJson:
              '{"chunkId":"c-other","documentId":"doc-other","modelIdentity":"m"}',
        ),
        BackendVectorHit(
          id: 'emb-wanted',
          similarity: 0.88,
          metadataJson:
              '{"chunkId":"c-wanted","documentId":"doc-wanted","modelIdentity":"m"}',
        ),
      ];

      final hits = await index.searchByEmbedding(
        queryEmbedding: query,
        topK: 1,
        scope: KnowledgeScope.documents({'doc-wanted'}),
      );

      expect(identical(backend.lastQueryEmbedding, query), isTrue);
      expect(backend.lastTopK, greaterThan(1));
      expect(hits, hasLength(1));
      expect(hits.single.embeddingId, 'emb-wanted');
      expect(hits.single.rank, 1);
    },
  );

  test(
    'probe exposes initialization truth and R4.6 database identity without pretending search verification',
    () async {
      final backend = RecordingVectorBackend();
      final index = SqliteActiveVectorIndex.forTest(
        backend,
        databasePath: '/tmp/pocketgallery_vectors_v46.db',
      );
      final before = await index.probe();
      expect(before.initialized, isFalse);
      expect(before.searchVerified, isFalse);

      await index.initialize();
      final after = await index.probe();
      expect(after.initialized, isTrue);
      expect(after.databasePath, endsWith('pocketgallery_vectors_v46.db'));
      expect(
        after.searchVerified,
        isFalse,
        reason:
            'Task 2 must not fabricate the later Search Verified health gate',
      );
    },
  );
}
