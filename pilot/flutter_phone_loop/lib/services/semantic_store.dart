import 'dart:convert';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../chat/chat_models.dart';
import '../core/models.dart';
import '../observability/vector_observation_store.dart';
import 'lexical_fts_store.dart';

class SemanticStore {
  SemanticStore(this.lexicalStore, {VectorObservationStore? observationStore})
    : observationStore = observationStore ?? VectorObservationStore();

  static const embeddingModelIdentity =
      'EmbeddingGemma-300M_seq256_mixed-precision';

  final LexicalFtsStore lexicalStore;
  final VectorObservationStore observationStore;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    final dir = await getApplicationDocumentsDirectory();
    await FlutterGemma.rag.initialize(
      p.join(dir.path, 'pocketgallery_vectors.db'),
    );
    await observationStore.initialize();
    _initialized = true;
  }

  Future<EmbeddingModel> _ensureEmbeddingRuntime() async {
    if (!FlutterGemma.hasActiveEmbedder()) {
      throw StateError(
        'EmbeddingGemma model identity is not active. Prepare the embedding model first.',
      );
    }
    return FlutterGemma.getActiveEmbedder();
  }

  Future<void> removeIds(Iterable<String> ids) async {
    await initialize();
    final materialized = ids.toList(growable: false);
    for (final id in materialized) {
      await FlutterGemma.rag.removeDocument(id: id);
    }
    await observationStore.removeChunkIds(materialized);
  }

  Future<void> addChunks(
    Iterable<PgChunk> chunks, {
    void Function(int completed, int total, PgChunk current)? onProgress,
  }) async {
    await initialize();
    final embedder = await _ensureEmbeddingRuntime();
    final materialized = chunks.toList(growable: false);

    for (var i = 0; i < materialized.length; i++) {
      final c = materialized[i];
      final embedding = await embedder.generateEmbedding(
        c.text,
        taskType: TaskType.retrievalDocument,
      );
      await observationStore.putChunkVector(
        chunkId: c.id,
        documentId: c.documentId,
        vector: embedding,
        modelIdentity: embeddingModelIdentity,
      );
      await FlutterGemma.rag.addDocumentWithEmbedding(
        id: c.id,
        content: c.text,
        embedding: embedding,
        metadata: jsonEncode({
          'documentId': c.documentId,
          'sourceName': c.sourceName,
          'locator': c.locator,
          'ordinal': c.ordinal,
        }),
      );
      // Emit only after both durable observation and RAG writes succeed. If a
      // later chunk fails or the app is killed, already completed chunks stay
      // checkpointed and the next repair run will skip them.
      onProgress?.call(i + 1, materialized.length, c);
    }
  }

  Future<List<double>> observeQueryVector(String query) async {
    await initialize();
    final embedder = await _ensureEmbeddingRuntime();
    return embedder.generateEmbedding(query);
  }

  Future<List<RetrievalHit>> search(
    String query, {
    int topK = 12,
    KnowledgeScope scope = const KnowledgeScope.all(),
  }) async {
    await initialize();
    final ids = scope.documentIds;
    if (!scope.isAll && (ids == null || ids.isEmpty)) return const [];
    await _ensureEmbeddingRuntime();

    final candidateK = scope.isAll ? topK : (topK * 8).clamp(topK, 96).toInt();
    final rows = await FlutterGemma.rag.searchSimilar(
      query: query,
      topK: candidateK,
      threshold: 0.0,
    );
    final out = <RetrievalHit>[];
    for (var i = 0; i < rows.length; i++) {
      final c = await lexicalStore.getChunk(rows[i].id);
      if (c == null) continue;
      if (!scope.isAll && !scope.documentIds!.contains(c.documentId)) continue;
      out.add(
        RetrievalHit(
          chunk: c,
          score: rows[i].similarity.clamp(0.0, 1.0).toDouble(),
          channel: 'embedding',
          rank: out.length + 1,
        ),
      );
      if (out.length >= topK) break;
    }
    return out;
  }

  Future<void> clear() async {
    await initialize();
    await FlutterGemma.rag.clear();
    await observationStore.clear();
  }
}
