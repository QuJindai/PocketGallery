import 'dart:convert';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

  Future<void> removeIds(Iterable<String> ids) async {
    await initialize();
    for (final id in ids) {
      await FlutterGemma.rag.removeDocument(id: id);
    }
  }

  Future<void> addChunks(Iterable<PgChunk> chunks) async {
    await initialize();
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

  Future<List<RetrievalHit>> search(String query, {int topK = 12}) async {
    await initialize();
    final rows = await FlutterGemma.rag.searchSimilar(
      query: query,
      topK: topK,
      threshold: 0.0,
    );
    final out = <RetrievalHit>[];
    for (var i = 0; i < rows.length; i++) {
      final c = await lexicalStore.getChunk(rows[i].id);
      if (c == null) continue;
      out.add(RetrievalHit(
        chunk: c,
        score: rows[i].similarity.clamp(0.0, 1.0).toDouble(),
        channel: 'embedding',
        rank: i + 1,
      ));
    }
    return out;
  }

  Future<void> clear() async {
    await initialize();
    await FlutterGemma.rag.clear();
  }
}
