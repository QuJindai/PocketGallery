import 'package:flutter_gemma/flutter_gemma.dart';

import '../lineage/lineage_ids.dart';
import '../lineage/lineage_models.dart';
import '../lineage/lineage_store.dart';

abstract interface class EmbeddingGenerator {
  Future<List<double>> generateQuery(String text);

  Future<List<double>> generateDocument(String text);
}

class FlutterGemmaEmbeddingGenerator implements EmbeddingGenerator {
  const FlutterGemmaEmbeddingGenerator();

  @override
  Future<List<double>> generateQuery(String text) async {
    final embedder = await FlutterGemma.getActiveEmbedder();
    return embedder.generateEmbedding(
      text,
      taskType: TaskType.retrievalQuery,
    );
  }

  @override
  Future<List<double>> generateDocument(String text) async {
    final embedder = await FlutterGemma.getActiveEmbedder();
    return embedder.generateEmbedding(
      text,
      taskType: TaskType.retrievalDocument,
    );
  }
}

class CapturedQueryEmbedding {
  const CapturedQueryEmbedding({
    required this.embedding,
    required this.vector,
  });

  final LineageEmbedding embedding;
  final List<double> vector;
}

class QueryEmbeddingRuntime {
  QueryEmbeddingRuntime({
    required this.generator,
    required this.store,
    this.modelIdentity = 'EmbeddingGemma-300M_seq256_mixed-precision',
  });

  final EmbeddingGenerator generator;
  final LineageStore store;
  final String modelIdentity;

  Future<CapturedQueryEmbedding> generateOnce({
    required String traceId,
    required String query,
  }) async {
    if (traceId.trim().isEmpty) {
      throw ArgumentError.value(traceId, 'traceId', 'Must not be empty');
    }
    if (query.trim().isEmpty) {
      throw ArgumentError.value(query, 'query', 'Must not be empty');
    }

    final embeddingId = LineageIds.queryEmbeddingId(traceId);
    final persisted = await store.embeddingById(embeddingId);
    if (persisted != null) {
      return CapturedQueryEmbedding(
        embedding: persisted,
        vector: persisted.vector,
      );
    }

    final watch = Stopwatch()..start();
    final vector = await generator.generateQuery(query);
    watch.stop();
    final embedding = LineageEmbedding.fromVector(
      embeddingId: embeddingId,
      sourceKind: 'query',
      sourceId: traceId,
      documentId: null,
      chunkId: null,
      representation: EmbeddingRepresentation.query,
      spanStart: null,
      spanEnd: null,
      vector: vector,
      modelIdentity: modelIdentity,
      taskMode: 'retrieval_query',
      generationMs: watch.elapsedMilliseconds,
      generatedAt: DateTime.now().toUtc(),
    );
    await store.putEmbedding(embedding);
    return CapturedQueryEmbedding(
      embedding: embedding,
      vector: vector,
    );
  }
}
