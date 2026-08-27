import 'dart:convert';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../chat/chat_models.dart';
import '../core/models.dart';
import 'lexical_fts_store.dart';

class SemanticStore {
  SemanticStore(this.lexicalStore);
  final LexicalFtsStore lexicalStore;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    final dir = await getApplicationDocumentsDirectory();
    await FlutterGemma.rag.initialize(p.join(dir.path, 'pocketgallery_vectors.db'));
    _initialized = true;
  }

  /// flutter_gemma keeps two embedding states: an active persisted model spec
  /// and the materialized runtime singleton. `hasActiveEmbedder()` only proves
  /// the former, while RAG auto-embedding requires the latter. Materialize (or
  /// reuse) the runtime immediately before every vector operation so an app
  /// restart/runtime eviction cannot leave a false READY state.
  Future<void> _ensureEmbeddingRuntime() async {
    if (!FlutterGemma.hasActiveEmbedder()) {
      throw StateError(
        'EmbeddingGemma model identity is not active. Prepare the embedding model first.',
      );
    }
    await FlutterGemma.getActiveEmbedder();
  }

  Future<void> removeIds(Iterable<String> ids) async {
    await initialize();
    for (final id in ids) {
      await FlutterGemma.rag.removeDocument(id: id);
    }
  }

  Future<void> addChunks(Iterable<PgChunk> chunks) async {
    await initialize();
    await _ensureEmbeddingRuntime();
    for (final c in chunks) {
      await FlutterGemma.rag.addDocument(
        id: c.id,
        content: c.text,
        metadata: jsonEncode({
          'documentId': c.documentId,
          'sourceName': c.sourceName,
          'locator': c.locator,
          'ordinal': c.ordinal,
        }),
      );
    }
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
      out.add(RetrievalHit(
        chunk: c,
        score: rows[i].similarity.clamp(0.0, 1.0).toDouble(),
        channel: 'embedding',
        rank: out.length + 1,
      ));
      if (out.length >= topK) break;
    }
    return out;
  }

  Future<void> clear() async {
    await initialize();
    await FlutterGemma.rag.clear();
  }
}
