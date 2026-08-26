import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../core/models.dart';

class LexicalFtsStore {
  Database? _db;

  Future<void> initialize() async {
    if (_db != null) return;
    final dir = await getApplicationDocumentsDirectory();
    final dbFile = File(p.join(dir.path, 'pocketgallery_fts5.db'));
    _db = sqlite3.open(dbFile.path);
    _db!.execute('PRAGMA journal_mode=WAL;');
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS pg_chunks (
        id TEXT PRIMARY KEY,
        document_id TEXT NOT NULL,
        source_name TEXT NOT NULL,
        locator TEXT NOT NULL,
        ordinal INTEGER NOT NULL,
        content TEXT NOT NULL
      );
    ''');
    _db!.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS pg_chunks_fts USING fts5(
        id UNINDEXED,
        document_id UNINDEXED,
        source_name UNINDEXED,
        locator UNINDEXED,
        ordinal UNINDEXED,
        content,
        tokenize='trigram'
      );
    ''');
  }

  Future<List<String>> chunkIdsForDocument(String documentId) async {
    await initialize();
    return _db!
        .select('SELECT id FROM pg_chunks WHERE document_id = ?', [documentId])
        .map((r) => r['id'] as String)
        .toList();
  }

  Future<List<PgChunk>> allChunks() async {
    await initialize();
    final rows = _db!.select('''
      SELECT id, document_id, source_name, locator, ordinal, content
      FROM pg_chunks
      ORDER BY document_id, ordinal
    ''');
    return rows.map(_rowToChunk).toList();
  }

  Future<void> replaceDocument(ImportedDocument doc) async {
    await initialize();
    final db = _db!;
    db.execute('BEGIN IMMEDIATE;');
    try {
      final old = db.select(
        'SELECT id FROM pg_chunks WHERE document_id = ?',
        [doc.documentId],
      );
      for (final row in old) {
        db.execute('DELETE FROM pg_chunks_fts WHERE id = ?', [row['id']]);
      }
      db.execute('DELETE FROM pg_chunks WHERE document_id = ?', [doc.documentId]);

      final insertPlain = db.prepare('''
        INSERT OR REPLACE INTO pg_chunks
        (id, document_id, source_name, locator, ordinal, content)
        VALUES (?, ?, ?, ?, ?, ?)
      ''');
      final insertFts = db.prepare('''
        INSERT INTO pg_chunks_fts
        (id, document_id, source_name, locator, ordinal, content)
        VALUES (?, ?, ?, ?, ?, ?)
      ''');
      try {
        for (final c in doc.chunks) {
          final args = [
            c.id, c.documentId, c.sourceName, c.locator, c.ordinal, c.text,
          ];
          insertPlain.execute(args);
          insertFts.execute(args);
        }
      } finally {
        insertPlain.close();
        insertFts.close();
      }
      db.execute('COMMIT;');
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  Future<PgChunk?> getChunk(String id) async {
    await initialize();
    final rows = _db!.select(
      '''SELECT id, document_id, source_name, locator, ordinal, content
         FROM pg_chunks WHERE id = ? LIMIT 1''',
      [id],
    );
    if (rows.isEmpty) return null;
    return _rowToChunk(rows.first);
  }

  Future<List<RetrievalHit>> search(String query, {int topK = 12}) async {
    await initialize();
    final ftsQuery = _buildFtsQuery(query);
    if (ftsQuery.isEmpty) return const [];
    ResultSet rows;
    try {
      rows = _db!.select('''
        SELECT id, document_id, source_name, locator, ordinal, content,
               bm25(pg_chunks_fts) AS bm
        FROM pg_chunks_fts
        WHERE pg_chunks_fts MATCH ?
        ORDER BY bm
        LIMIT ?
      ''', [ftsQuery, topK]);
    } catch (_) {
      final quoted = '"${query.replaceAll('"', '""')}"';
      rows = _db!.select('''
        SELECT id, document_id, source_name, locator, ordinal, content,
               bm25(pg_chunks_fts) AS bm
        FROM pg_chunks_fts
        WHERE pg_chunks_fts MATCH ?
        ORDER BY bm
        LIMIT ?
      ''', [quoted, topK]);
    }

    return [
      for (var i = 0; i < rows.length; i++)
        RetrievalHit(
          chunk: _rowToChunk(rows[i]),
          score: _bm25Affinity((rows[i]['bm'] as num).toDouble()),
          channel: 'fts5',
          rank: i + 1,
        )
    ];
  }

  PgChunk _rowToChunk(Row row) => PgChunk(
        id: row['id'] as String,
        documentId: row['document_id'] as String,
        sourceName: row['source_name'] as String,
        locator: row['locator'] as String,
        ordinal: (row['ordinal'] as num).toInt(),
        text: row['content'] as String,
      );

  double _bm25Affinity(double bm) => 1.0 / (1.0 + bm.abs());

  String _buildFtsQuery(String query) {
    final q = query.trim().replaceAll('"', '""');
    if (q.isEmpty) return '';
    final parts = q
        .split(RegExp(r'[\s，。；、,.;:：!?！？()\[\]{}]+'))
        .where((x) => x.trim().length >= 3)
        .take(10)
        .map((x) => '"$x"')
        .toList();
    if (parts.length >= 2) return parts.join(' OR ');
    return '"$q"';
  }

  Future<void> clear() async {
    await initialize();
    _db!.execute('DELETE FROM pg_chunks;');
    _db!.execute('DELETE FROM pg_chunks_fts;');
  }

  void dispose() {
    _db?.close();
    _db = null;
  }
}
