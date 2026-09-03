import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'retrieval_trace.dart';

class RetrievalTraceStore {
  RetrievalTraceStore({Database? database})
      : _db = database,
        _ownsDatabase = database == null;

  Database? _db;
  final bool _ownsDatabase;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    if (_db == null) {
      final dir = await getApplicationDocumentsDirectory();
      _db = sqlite3.open(p.join(dir.path, 'pocketgallery_observability.db'));
    }
    _db!.execute('PRAGMA journal_mode=WAL;');
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS pg_retrieval_traces (
        trace_id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        started_at TEXT NOT NULL,
        completed_at TEXT NOT NULL,
        payload_json TEXT NOT NULL
      );
    ''');
    _db!.execute('''
      CREATE INDEX IF NOT EXISTS pg_retrieval_traces_session_time
      ON pg_retrieval_traces(session_id, completed_at DESC);
    ''');
    _initialized = true;
  }

  Future<void> save(RetrievalTrace trace) async {
    await initialize();
    final bounded = trace.bounded();
    _db!.execute('''
      INSERT OR REPLACE INTO pg_retrieval_traces
      (trace_id, session_id, started_at, completed_at, payload_json)
      VALUES (?, ?, ?, ?, ?)
    ''', [
      bounded.traceId,
      bounded.sessionId,
      bounded.startedAt.toUtc().toIso8601String(),
      bounded.completedAt.toUtc().toIso8601String(),
      jsonEncode(bounded.toJson()),
    ]);
  }

  Future<RetrievalTrace?> get(String traceId) async {
    await initialize();
    final rows = _db!.select(
      'SELECT payload_json FROM pg_retrieval_traces WHERE trace_id = ? LIMIT 1',
      [traceId],
    );
    if (rows.isEmpty) return null;
    return _decode(rows.first['payload_json'] as String);
  }

  Future<RetrievalTrace?> latestForSession(String sessionId) async {
    await initialize();
    final rows = _db!.select('''
      SELECT payload_json
      FROM pg_retrieval_traces
      WHERE session_id = ?
      ORDER BY completed_at DESC, trace_id DESC
      LIMIT 1
    ''', [sessionId]);
    if (rows.isEmpty) return null;
    return _decode(rows.first['payload_json'] as String);
  }

  Future<List<RetrievalTrace>> recent({int limit = 50}) async {
    await initialize();
    final boundedLimit = limit.clamp(1, 200).toInt();
    final rows = _db!.select('''
      SELECT payload_json
      FROM pg_retrieval_traces
      ORDER BY completed_at DESC, trace_id DESC
      LIMIT ?
    ''', [boundedLimit]);
    return rows
        .map((row) => _decode(row['payload_json'] as String))
        .toList(growable: false);
  }

  RetrievalTrace _decode(String payload) => RetrievalTrace.fromJson(
        (jsonDecode(payload) as Map<dynamic, dynamic>).cast<String, dynamic>(),
      );

  void dispose() {
    if (_ownsDatabase) _db?.close();
    _db = null;
    _initialized = false;
  }
}
