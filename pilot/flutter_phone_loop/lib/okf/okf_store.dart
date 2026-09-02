import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'okf_models.dart';

class OkfStore {
  OkfStore({Database? database})
    : _db = database,
      _ownsDatabase = database == null;

  Database? _db;
  final bool _ownsDatabase;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    if (_db == null) {
      final dir = await getApplicationDocumentsDirectory();
      _db = sqlite3.open(p.join(dir.path, 'pocketgallery_lineage.db'));
    }
    final db = _db!;
    db.execute('PRAGMA foreign_keys=ON;');
    db.execute('PRAGMA journal_mode=WAL;');
    db.execute('''
      CREATE TABLE IF NOT EXISTS pg_okf_documents (
        document_id TEXT PRIMARY KEY,
        source_name TEXT NOT NULL,
        okf_type TEXT NOT NULL,
        title TEXT,
        trust_tier TEXT NOT NULL,
        freshness TEXT NOT NULL,
        verified_json TEXT NOT NULL,
        generated_json TEXT NOT NULL,
        sources_json TEXT NOT NULL,
        status TEXT,
        stale_after TEXT,
        superseded_by TEXT,
        frontmatter_json TEXT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS pg_okf_links (
        edge_id TEXT PRIMARY KEY,
        document_id TEXT NOT NULL,
        label TEXT NOT NULL,
        target TEXT NOT NULL,
        is_relative_bundle_link INTEGER NOT NULL,
        FOREIGN KEY(document_id) REFERENCES pg_okf_documents(document_id)
          ON DELETE CASCADE
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS pg_okf_candidate_signals (
        signal_id TEXT PRIMARY KEY,
        trace_id TEXT NOT NULL,
        strategy_id TEXT NOT NULL,
        candidate_id TEXT NOT NULL,
        chunk_id TEXT NOT NULL,
        document_id TEXT NOT NULL,
        base_score REAL NOT NULL,
        trust_adjustment REAL NOT NULL,
        freshness_adjustment REAL NOT NULL,
        link_adjustment REAL NOT NULL,
        final_score REAL NOT NULL,
        reason TEXT NOT NULL,
        UNIQUE(trace_id, strategy_id, candidate_id)
      );
    ''');
    _initialized = true;
  }

  Future<void> replaceDocument(
    String documentId,
    OkfParseResult? result,
  ) async {
    await initialize();
    final db = _db!;
    db.execute('BEGIN IMMEDIATE;');
    try {
      db.execute('DELETE FROM pg_okf_links WHERE document_id = ?', [documentId]);
      db.execute('DELETE FROM pg_okf_documents WHERE document_id = ?', [
        documentId,
      ]);
      if (result != null) {
        final document = result.document;
        if (document.documentId != documentId) {
          throw StateError(
            'OKF document identity mismatch: ${document.documentId} != $documentId',
          );
        }
        db.execute(
          '''
          INSERT INTO pg_okf_documents (
            document_id, source_name, okf_type, title, trust_tier, freshness,
            verified_json, generated_json, sources_json, status, stale_after,
            superseded_by, frontmatter_json
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
          <Object?>[
            document.documentId,
            document.sourceName,
            document.type,
            document.title,
            document.trustTier.name,
            document.freshness.name,
            jsonEncode(document.verifiedActors),
            jsonEncode(document.generatedActors),
            jsonEncode(document.sources.map((source) => source.toJson()).toList()),
            document.status,
            document.staleAfter?.toUtc().toIso8601String(),
            document.supersededBy,
            jsonEncode(document.frontmatter),
          ],
        );
        for (var index = 0; index < result.links.length; index++) {
          final link = result.links[index];
          db.execute(
            '''
            INSERT INTO pg_okf_links (
              edge_id, document_id, label, target, is_relative_bundle_link
            ) VALUES (?, ?, ?, ?, ?)
          ''',
            <Object?>[
              _edgeId(documentId, index, link.label, link.target),
              documentId,
              link.label,
              link.target,
              link.isRelativeBundleLink ? 1 : 0,
            ],
          );
        }
      }
      db.execute('COMMIT;');
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  Future<OkfDocument?> documentById(String documentId) async {
    await initialize();
    final rows = _db!.select(
      'SELECT * FROM pg_okf_documents WHERE document_id = ? LIMIT 1',
      [documentId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final sourcesRaw = jsonDecode(row['sources_json'] as String) as List;
    return OkfDocument(
      documentId: row['document_id'] as String,
      sourceName: row['source_name'] as String,
      type: row['okf_type'] as String,
      title: row['title'] as String?,
      trustTier: OkfTrustTier.values.byName(row['trust_tier'] as String),
      freshness: OkfFreshness.values.byName(row['freshness'] as String),
      verifiedActors: _decodeStrings(row['verified_json'] as String),
      generatedActors: _decodeStrings(row['generated_json'] as String),
      sources: sourcesRaw
          .map(
            (value) => OkfSource.fromJson(
              Map<String, Object?>.from(value as Map),
            ),
          )
          .toList(growable: false),
      status: row['status'] as String?,
      staleAfter: _date(row['stale_after']),
      supersededBy: row['superseded_by'] as String?,
      frontmatter: Map<String, Object?>.from(
        jsonDecode(row['frontmatter_json'] as String) as Map,
      ),
    );
  }

  Future<List<OkfLink>> linksForDocument(String documentId) async {
    await initialize();
    return _db!
        .select(
          '''
          SELECT document_id, label, target, is_relative_bundle_link
          FROM pg_okf_links
          WHERE document_id = ? ORDER BY edge_id
        ''',
          [documentId],
        )
        .map(
          (row) => OkfLink(
            documentId: row['document_id'] as String,
            label: row['label'] as String,
            target: row['target'] as String,
            isRelativeBundleLink: (row['is_relative_bundle_link'] as int) == 1,
          ),
        )
        .toList(growable: false);
  }

  Future<List<OkfDocument>> documentsByIds(Iterable<String> documentIds) async {
    final result = <OkfDocument>[];
    for (final id in documentIds.toSet()) {
      final document = await documentById(id);
      if (document != null) result.add(document);
    }
    return result;
  }

  Future<void> replaceCandidateSignals({
    required String traceId,
    required String strategyId,
    required List<OkfCandidateSignal> signals,
  }) async {
    await initialize();
    final db = _db!;
    db.execute('BEGIN IMMEDIATE;');
    try {
      db.execute(
        'DELETE FROM pg_okf_candidate_signals WHERE trace_id = ? AND strategy_id = ?',
        [traceId, strategyId],
      );
      for (final signal in signals) {
        db.execute(
          '''
          INSERT INTO pg_okf_candidate_signals (
            signal_id, trace_id, strategy_id, candidate_id, chunk_id,
            document_id, base_score, trust_adjustment,
            freshness_adjustment, link_adjustment, final_score, reason
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
          <Object?>[
            _signalId(signal.traceId, signal.strategyId, signal.candidateId),
            signal.traceId,
            signal.strategyId,
            signal.candidateId,
            signal.chunkId,
            signal.documentId,
            signal.baseScore,
            signal.trustAdjustment,
            signal.freshnessAdjustment,
            signal.linkAdjustment,
            signal.finalScore,
            signal.reason,
          ],
        );
      }
      db.execute('COMMIT;');
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  Future<List<OkfCandidateSignal>> candidateSignals({
    required String traceId,
    required String strategyId,
  }) async {
    await initialize();
    return _db!
        .select(
          '''
          SELECT * FROM pg_okf_candidate_signals
          WHERE trace_id = ? AND strategy_id = ?
          ORDER BY final_score DESC, candidate_id
        ''',
          [traceId, strategyId],
        )
        .map(
          (row) => OkfCandidateSignal(
            traceId: row['trace_id'] as String,
            strategyId: row['strategy_id'] as String,
            candidateId: row['candidate_id'] as String,
            chunkId: row['chunk_id'] as String,
            documentId: row['document_id'] as String,
            baseScore: (row['base_score'] as num).toDouble(),
            trustAdjustment: (row['trust_adjustment'] as num).toDouble(),
            freshnessAdjustment: (row['freshness_adjustment'] as num).toDouble(),
            linkAdjustment: (row['link_adjustment'] as num).toDouble(),
            finalScore: (row['final_score'] as num).toDouble(),
            reason: row['reason'] as String,
          ),
        )
        .toList(growable: false);
  }

  Future<void> close() async {
    if (_ownsDatabase) _db?.close();
    _db = null;
    _initialized = false;
  }

  String _edgeId(String documentId, int index, String label, String target) =>
      sha256
          .convert(utf8.encode('$documentId|$index|$label|$target'))
          .toString()
          .substring(0, 24);

  String _signalId(String traceId, String strategyId, String candidateId) =>
      sha256
          .convert(utf8.encode('$traceId|$strategyId|$candidateId'))
          .toString()
          .substring(0, 24);

  List<String> _decodeStrings(String encoded) => (jsonDecode(encoded) as List)
      .map((value) => value.toString())
      .toList(growable: false);

  DateTime? _date(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toUtc();
  }
}
