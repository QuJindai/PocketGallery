import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:pocketgallery_phone_pilot/observability/vector_observation_store.dart';

void main() {
  test('vector observations round-trip Float32 values and metadata', () async {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    final store = VectorObservationStore(database: db);
    await store.initialize();

    await store.putChunkVector(
      chunkId: 'c1',
      documentId: 'd1',
      vector: const [0.25, -0.5, 1.0, 0.125],
      modelIdentity: 'EmbeddingGemma-300M',
      updatedAt: DateTime.utc(2026, 8, 28),
    );

    final row = await store.getChunkVector('c1');
    expect(row, isNotNull);
    expect(row!.dimension, 4);
    expect(row.vector[0], closeTo(0.25, 1e-6));
    expect(row.vector[1], closeTo(-0.5, 1e-6));
    expect(row.norm, closeTo(1.152443, 1e-5));
    expect(row.modelIdentity, 'EmbeddingGemma-300M');
    expect(await store.count(), 1);
    expect((await store.listForDocuments({'d1'})).single.chunkId, 'c1');
  });

  test(
    'semantic index writes one explicit vector to observation and RAG paths',
    () async {
      final source = await File('lib/services/semantic_store.dart')
          .readAsString();
      expect(source, contains('FlutterGemma.getActiveEmbedder()'));
      expect(source, contains('TaskType.retrievalDocument'));
      expect(source, contains('putChunkVector'));
      expect(source, contains('addDocumentWithEmbedding'));
      expect(source, isNot(contains('FlutterGemma.rag.addDocument(')));
    },
  );
}
