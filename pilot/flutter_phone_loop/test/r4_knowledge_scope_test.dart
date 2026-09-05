import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:pocketgallery_phone_pilot/chat/chat_models.dart';
import 'package:pocketgallery_phone_pilot/core/models.dart';
import 'package:pocketgallery_phone_pilot/services/lexical_fts_store.dart';

void main() {
  test('FTS5 scope only returns requested documents', () async {
    final db = sqlite3.openInMemory();
    final store = LexicalFtsStore(database: db);
    await store.initialize();
    await store.replaceDocument(const ImportedDocument(
      documentId: 'a', sourceName: 'a.txt', sha256: 'a',
      chunks: [PgChunk(id: 'a1', documentId: 'a', sourceName: 'a.txt', locator: 'text', ordinal: 0, text: 'vehicle model calibration result')],
    ));
    await store.replaceDocument(const ImportedDocument(
      documentId: 'b', sourceName: 'b.txt', sha256: 'b',
      chunks: [PgChunk(id: 'b1', documentId: 'b', sourceName: 'b.txt', locator: 'text', ordinal: 0, text: 'vehicle model network test')],
    ));
    final hits = await store.search('vehicle model',
      scope: KnowledgeScope.documents({'b'}));
    expect(hits, isNotEmpty);
    expect(hits.every((h) => h.chunk.documentId == 'b'), isTrue);
    db.close();
  });

  test('zero chunk imports remain visible in metadata', () async {
    final db = sqlite3.openInMemory();
    final store = LexicalFtsStore(database: db);
    await store.initialize();
    await store.replaceDocument(const ImportedDocument(
      documentId: 'scan', sourceName: 'scan.pdf', sha256: 'scan', chunks: []));
    final docs = await store.listDocuments();
    expect(docs.single.documentId, 'scan');
    expect(docs.single.chunkCount, 0);
    expect(docs.single.textAvailable, isFalse);
    db.close();
  });
}
