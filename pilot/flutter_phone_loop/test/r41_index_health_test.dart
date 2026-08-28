import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:pocketgallery_phone_pilot/core/models.dart';
import 'package:pocketgallery_phone_pilot/observability/index_health_service.dart';
import 'package:pocketgallery_phone_pilot/observability/vector_observation_store.dart';
import 'package:pocketgallery_phone_pilot/services/lexical_fts_store.dart';

void main() {
  test('index health detects zero chunks duplicate SHA and missing vectors', () async {
    final lexicalDb = sqlite3.openInMemory();
    final vectorDb = sqlite3.openInMemory();
    addTearDown(lexicalDb.close);
    addTearDown(vectorDb.close);
    final lexical = LexicalFtsStore(database: lexicalDb);
    final vectors = VectorObservationStore(database: vectorDb);
    await lexical.initialize();
    await vectors.initialize();

    await lexical.replaceDocument(const ImportedDocument(
      documentId: 'd1',
      sourceName: 'a.txt',
      sha256: 'same',
      chunks: [
        PgChunk(
          id: 'c1',
          documentId: 'd1',
          sourceName: 'a.txt',
          locator: '1',
          ordinal: 0,
          text: 'alpha beta gamma',
        ),
        PgChunk(
          id: 'c2',
          documentId: 'd1',
          sourceName: 'a.txt',
          locator: '2',
          ordinal: 1,
          text: 'gamma delta epsilon',
        ),
      ],
    ));
    await lexical.replaceDocument(const ImportedDocument(
      documentId: 'd2',
      sourceName: 'empty.pdf',
      sha256: 'same',
      chunks: [],
    ));
    await vectors.putChunkVector(
      chunkId: 'c1',
      documentId: 'd1',
      vector: const [1, 0, 0],
      modelIdentity: 'embed-v1',
    );

    final service = IndexHealthService(
      lexicalStore: lexical,
      vectorStore: vectors,
      activeModelIdentity: () => 'embed-v1',
    );
    final health = await service.snapshot(includeFileSizes: false);
    expect(health.documentCount, 2);
    expect(health.chunkCount, 2);
    expect(health.ftsIndexedCount, 2);
    expect(health.vectorIndexedCount, 1);
    expect(health.missingVectorCount, 1);
    expect(health.zeroChunkDocuments, 1);
    expect(health.duplicateShaGroups, 1);
    expect(health.staleVectorCount, 0);

    final chunks = await service.inspectDocument('d1');
    expect(chunks, hasLength(2));
    expect(chunks.first.vectorReady, isTrue);
    expect(chunks.last.vectorReady, isFalse);
    expect(chunks.last.overlapChars, greaterThanOrEqualTo(0));
  });
}
