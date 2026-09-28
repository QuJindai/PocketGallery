import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:pocketgallery_phone_pilot/chat/chat_models.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_store.dart';
import 'package:pocketgallery_phone_pilot/retrieval/active_vector_index.dart';
import 'package:pocketgallery_phone_pilot/retrieval/query_embedding_runtime.dart';

class RecordingEmbeddingGenerator implements EmbeddingGenerator {
  RecordingEmbeddingGenerator(this.nextQueryVector);

  final List<double> nextQueryVector;
  int queryCalls = 0;
  int documentCalls = 0;

  @override
  Future<List<double>> generateQuery(String text) async {
    queryCalls++;
    return nextQueryVector;
  }

  @override
  Future<List<double>> generateDocument(String text) async {
    documentCalls++;
    return const [0.9, 0.1, 0.0];
  }
}

class RecordingQueryIndex implements ActiveVectorIndex {
  List<double>? lastQueryEmbedding;

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
    lastQueryEmbedding = queryEmbedding;
    return const [];
  }

  @override
  Future<VectorIndexProbe> probe() async => const VectorIndexProbe(
    initialized: true,
    databasePath: 'memory://query-identity',
    backendId: 'recording-query-index',
    searchVerified: true,
  );

  @override
  Future<void> close() async {}
}

void main() {
  test(
    'one captured query vector is persisted and passed unchanged to search',
    () async {
      final db = sqlite3.openInMemory();
      addTearDown(db.close);
      final store = LineageStore(database: db);
      final generator = RecordingEmbeddingGenerator(<double>[0.1, 0.2, 0.3]);
      final runtime = QueryEmbeddingRuntime(
        generator: generator,
        store: store,
        modelIdentity: 'EmbeddingGemma-test',
      );
      final index = RecordingQueryIndex();

      final captured = await runtime.generateOnce(
        traceId: 'tr-1',
        query: '端侧模型如何测试',
      );
      await index.searchByEmbedding(
        queryEmbedding: captured.vector,
        topK: 5,
        scope: const KnowledgeScope.all(),
      );
      final replay = await runtime.generateOnce(
        traceId: 'tr-1',
        query: '端侧模型如何测试',
      );

      expect(generator.queryCalls, 1);
      expect(generator.documentCalls, 0);
      expect(identical(index.lastQueryEmbedding, captured.vector), isTrue);
      expect(replay.embedding.embeddingId, captured.embedding.embeddingId);
      final persisted = await store.embeddingById(
        captured.embedding.embeddingId,
      );
      expect(persisted, isNotNull);
      expect(persisted!.vectorSha256, captured.embedding.vectorSha256);
      expect(persisted.taskMode, 'retrieval_query');
      expect(persisted.chunkId, isNull);
    },
  );
}
