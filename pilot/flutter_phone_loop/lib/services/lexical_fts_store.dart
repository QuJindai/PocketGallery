import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../chat/chat_models.dart';
import '../core/models.dart';
import '../observability/fts_inspector.dart';

class LexicalFtsStore {
  LexicalFtsStore({Database? database})
      : _db = database,
        _ownsDatabase = database == null;

  Database? _db;
  final bool _ownsDatabase;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    if (_db == null) {
      final dir = await getApplicationDocumentsDirectory();
      final dbFile = File(p.join(dir.path, 'pocketgallery_fts5.db'));
      _db = sqlite3.open(dbFile.path);
    }
    final db = _db!;
    db.execute('PRAGMA journal_mode=WAL;');
    db.execute('''
      CREATE TABLE IF NOT EXISTS pg_chunks (
        id TEXT PRIMARY KEY,
        document_id TEXT NOT NULL,
        source_name TEXT NOT NULL,
        locator TEXT NOT NULL,
        ordinal INTEGER NOT NULL,
        content TEXT NOT NULL
      );
    ''');
    db.execute('''
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
    db.execute('''
      CREATE TABLE IF NOT EXISTS pg_documents (
        document_id TEXT PRIMARY KEY,
        source_name TEXT NOT NULL,
        sha256 TEXT NOT NULL DEFAULT '',
        chunk_count INTEGER NOT NULL DEFAULT 0
      );
    ''');
    db.execute('''
      INSERT OR IGNORE INTO pg_documents(document_id, source_name, chunk_count)
      SELECT document_id, MIN(source_name), COUNT(*)
      FROM pg_chunks
      GROUP BY document_id;
    ''');
    _initialized = true;
  }

  Future<List<String>> chunkIdsForDocument(String documentId) async {
    await initialize();
    return _db!
        .select('SELECT id FROM pg_chunks WHERE document_id = ?', [documentId])
        .map((r) => r['id'] as String)
        .toList();
  }

  Future<List<PgChunk>> chunksForDocument(String documentId) async {
    await initialize();
    final rows = _db!.select('''
      SELECT id, document_id, source_name, locator, ordinal, content
      FROM pg_chunks WHERE document_id = ? ORDER BY ordinal
    ''', [documentId]);
    return rows.map(_rowToChunk).toList();
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

  Future<List<KnowledgeDocument>> listDocuments() async {
    await initialize();
    final rows = _db!.select('''
      SELECT document_id, source_name, sha256, chunk_count
      FROM pg_documents ORDER BY source_name COLLATE NOCASE, document_id
    ''');
    return rows
        .map((row) => KnowledgeDocument(
              documentId: row['document_id'] as String,
              sourceName: row['source_name'] as String,
              sha256: row['sha256'] as String,
              chunkCount: (row['chunk_count'] as num).toInt(),
            ))
        .toList();
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
            c.id,
            c.documentId,
            c.sourceName,
            c.locator,
            c.ordinal,
            c.text,
          ];
          insertPlain.execute(args);
          insertFts.execute(args);
        }
      } finally {
        insertPlain.close();
        insertFts.close();
      }

      db.execute('''
        INSERT OR REPLACE INTO pg_documents
        (document_id, source_name, sha256, chunk_count)
        VALUES (?, ?, ?, ?)
      ''', [doc.documentId, doc.sourceName, doc.sha256, doc.chunks.length]);
      db.execute('COMMIT;');
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  Future<void> removeDocument(String documentId) async {
    await initialize();
    final db = _db!;
    db.execute('BEGIN IMMEDIATE;');
    try {
      final ids = db.select(
        'SELECT id FROM pg_chunks WHERE document_id = ?',
        [documentId],
      );
      for (final row in ids) {
        db.execute('DELETE FROM pg_chunks_fts WHERE id = ?', [row['id']]);
      }
      db.execute('DELETE FROM pg_chunks WHERE document_id = ?', [documentId]);
      db.execute('DELETE FROM pg_documents WHERE document_id = ?', [documentId]);
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

  Future<FtsInspectionResult> inspect(
    String query, {
    int topK = 12,
    KnowledgeScope scope = const KnowledgeScope.all(),
  }) async {
    await initialize();
    final ids = scope.documentIds?.toList() ?? const <String>[];
    if (!scope.isAll && ids.isEmpty) {
      return FtsInspectionResult(
        query: query,
        normalizedQuery: '',
        hits: const [],
        diagnostics: 'empty document scope',
      );
    }

    final shortCjkTerms = _shortCjkTerms(query);
    if (shortCjkTerms.isNotEmpty && _onlyShortCjkTerms(query)) {
      return _inspectShortCjk(
        query,
        shortCjkTerms,
        ids: ids,
        scope: scope,
        topK: topK,
      );
    }

    final cjkWindows = _cjkTrigramWindows(query);
    final ftsQuery = _buildFtsQuery(query);
    if (ftsQuery.isEmpty) {
      return FtsInspectionResult(
        query: query,
        normalizedQuery: '',
        hits: const [],
        diagnostics: 'empty normalized FTS query',
      );
    }

    final scopeSql = scope.isAll
        ? ''
        : ' AND document_id IN (${List.filled(ids.length, '?').join(',')}) ';
    final args = <Object?>[ftsQuery, ...ids, topK];
    ResultSet rows;
    try {
      rows = _db!.select('''
        SELECT id, document_id, source_name, locator, ordinal, content,
               bm25(pg_chunks_fts) AS bm,
               snippet(pg_chunks_fts, 5, '<mark>', '</mark>', '…', 28) AS snip
        FROM pg_chunks_fts
        WHERE pg_chunks_fts MATCH ? $scopeSql
        ORDER BY bm
        LIMIT ?
      ''', args);
    } catch (_) {
      final quoted = '"${query.replaceAll('"', '""')}"';
      rows = _db!.select('''
        SELECT id, document_id, source_name, locator, ordinal, content,
               bm25(pg_chunks_fts) AS bm,
               content AS snip
        FROM pg_chunks_fts
        WHERE pg_chunks_fts MATCH ? $scopeSql
        ORDER BY bm
        LIMIT ?
      ''', <Object?>[quoted, ...ids, topK]);
    }

    final terms = cjkWindows.isNotEmpty ? cjkWindows : _queryTerms(query);
    return FtsInspectionResult(
      query: query,
      normalizedQuery: ftsQuery,
      diagnostics: cjkWindows.isNotEmpty
          ? 'FTS5 CJK trigram-window OR + SQLite bm25(); REAL bm25, DERIVED affinity'
          : 'FTS5 trigram + SQLite bm25(); REAL bm25, DERIVED affinity',
      hits: [
        for (var i = 0; i < rows.length; i++)
          FtsInspectionHit(
            chunk: _rowToChunk(rows[i]),
            rank: i + 1,
            rawBm25: (rows[i]['bm'] as num).toDouble(),
            affinity: _bm25Affinity((rows[i]['bm'] as num).toDouble()),
            snippet: rows[i]['snip'] as String,
            matchedTerms: terms
                .where((term) =>
                    (rows[i]['content'] as String).toLowerCase().contains(term))
                .toList(growable: false),
            matchMode:
                cjkWindows.isNotEmpty ? 'cjk-trigram-window' : 'fts5-trigram',
          ),
      ],
    );
  }

  Future<FtsInspectionResult> _inspectShortCjk(
    String query,
    List<String> terms, {
    required List<String> ids,
    required KnowledgeScope scope,
    required int topK,
  }) async {
    final likeSql = terms.map((_) => 'content LIKE ?').join(' OR ');
    final scopeSql = scope.isAll
        ? ''
        : ' AND document_id IN (${List.filled(ids.length, '?').join(',')}) ';
    final patterns = terms.map((e) => '%$e%').toList();
    final rows = _db!.select('''
      SELECT id, document_id, source_name, locator, ordinal, content
      FROM pg_chunks
      WHERE ($likeSql) $scopeSql
      ORDER BY document_id, ordinal
      LIMIT ?
    ''', <Object?>[...patterns, ...ids, topK]);

    return FtsInspectionResult(
      query: query,
      normalizedQuery: terms.join(' OR '),
      diagnostics:
          '2-char CJK fallback: FTS5 trigram indexes substrings >=3 chars, so exact LIKE is used and raw BM25 is unavailable',
      hits: [
        for (var i = 0; i < rows.length; i++)
          FtsInspectionHit(
            chunk: _rowToChunk(rows[i]),
            rank: i + 1,
            rawBm25: null,
            affinity: 1.0 / (i + 1),
            snippet: _highlightShortTerms(rows[i]['content'] as String, terms),
            matchedTerms: terms,
            matchMode: 'cjk-short-exact',
          ),
      ],
    );
  }

  Future<List<RetrievalHit>> search(
    String query, {
    int topK = 12,
    KnowledgeScope scope = const KnowledgeScope.all(),
  }) async {
    final result = await inspect(query, topK: topK, scope: scope);
    return [
      for (final hit in result.hits)
        RetrievalHit(
          chunk: hit.chunk,
          score: hit.affinity,
          channel: 'fts5',
          rank: hit.rank,
        ),
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
    final q = query.trim();
    if (q.isEmpty) return '';

    // SQLite FTS5's trigram tokenizer can index Chinese well, but a single
    // quoted continuous Chinese question is still interpreted as one phrase.
    // That made "端侧模型如何测试" miss text such as "端侧模型性能测试方法".
    // Build overlapping 3-character windows so BM25 can rank partial lexical
    // agreement while Embedding remains responsible for semantic similarity.
    final cjkWindows = _cjkTrigramWindows(q);
    final nonCjk = q
        .replaceAll(RegExp(r'[\u3400-\u9fff]+'), ' ')
        .split(RegExp(r'[\s，。；、,.;:：!?！？()\[\]{}]+'))
        .map((x) => x.trim().toLowerCase())
        .where((x) => x.length >= 3)
        .take(8);

    final terms = <String>{...cjkWindows, ...nonCjk}.take(16).toList();
    if (terms.isNotEmpty) {
      return terms
          .map((x) => '"${x.replaceAll('"', '""')}"')
          .join(' OR ');
    }

    final escaped = q.replaceAll('"', '""');
    return '"$escaped"';
  }

  List<String> _cjkTrigramWindows(String query) {
    final out = <String>[];
    final seen = <String>{};
    for (final match in RegExp(r'[\u3400-\u9fff]{3,}').allMatches(query)) {
      final run = match.group(0)!;
      for (var i = 0; i <= run.length - 3; i++) {
        final window = run.substring(i, i + 3);
        if (seen.add(window)) out.add(window);
        if (out.length >= 12) return out;
      }
    }
    return out;
  }

  List<String> _queryTerms(String query) => query
      .toLowerCase()
      .split(RegExp(r'[\s，。；、,.;:：!?！？()\[\]{}]+'))
      .where((x) => x.trim().isNotEmpty)
      .take(12)
      .toList(growable: false);

  List<String> _shortCjkTerms(String query) => _queryTerms(query)
      .where((term) => RegExp(r'^[\u3400-\u9fff]{2}$').hasMatch(term))
      .toList(growable: false);

  bool _onlyShortCjkTerms(String query) {
    final terms = _queryTerms(query);
    return terms.isNotEmpty &&
        terms.every((term) => RegExp(r'^[\u3400-\u9fff]{2}$').hasMatch(term));
  }

  String _highlightShortTerms(String text, List<String> terms) {
    var out = text;
    for (final term in terms) {
      out = out.replaceAll(term, '<mark>$term</mark>');
    }
    return out.length <= 220 ? out : '${out.substring(0, 220)}…';
  }

  Future<void> clear() async {
    await initialize();
    _db!.execute('DELETE FROM pg_chunks;');
    _db!.execute('DELETE FROM pg_chunks_fts;');
    _db!.execute('DELETE FROM pg_documents;');
  }

  void dispose() {
    if (_ownsDatabase) _db?.close();
    _db = null;
    _initialized = false;
  }
}
