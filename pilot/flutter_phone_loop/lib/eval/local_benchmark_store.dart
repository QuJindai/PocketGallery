import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'retrieval_benchmark.dart';

class LocalBenchmarkCase {
  const LocalBenchmarkCase({
    required this.id,
    required this.question,
    required this.expectedDocumentIds,
    required this.expectedChunkIds,
    required this.tags,
    required this.sourceTraceId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String question;
  final Set<String> expectedDocumentIds;
  final Set<String> expectedChunkIds;
  final Set<String> tags;
  final String? sourceTraceId;
  final DateTime createdAt;
  final DateTime updatedAt;

  RetrievalBenchmarkCase toBenchmarkCase() => RetrievalBenchmarkCase(
        id: id,
        question: question,
        expectedDocumentIds: expectedDocumentIds,
        expectedSourceNames: const <String>{},
        expectedChunkIds: expectedChunkIds,
        expectedUseKnowledge:
            expectedDocumentIds.isNotEmpty || expectedChunkIds.isNotEmpty,
        tags: tags,
      );
}

class LocalBenchmarkStore {
  LocalBenchmarkStore({Database? database, String? databasePath})
      : _db = database,
        _databasePath = databasePath,
        _ownsDatabase = database == null;

  LocalBenchmarkStore.inMemory()
      : _db = sqlite3.openInMemory(),
        _databasePath = null,
        _ownsDatabase = true;

  static const databaseFileName = 'pocketgallery_local_benchmark.db';

  Database? _db;
  final String? _databasePath;
  final bool _ownsDatabase;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    if (_db == null) {
      final path = _databasePath ??
          p.join(
            (await getApplicationDocumentsDirectory()).path,
            databaseFileName,
          );
      _db = sqlite3.open(path);
    }
    _db!.execute('PRAGMA journal_mode=WAL;');
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS pg_local_benchmark_cases (
        case_id TEXT PRIMARY KEY,
        question TEXT NOT NULL,
        expected_document_ids_json TEXT NOT NULL,
        expected_chunk_ids_json TEXT NOT NULL,
        tags_json TEXT NOT NULL,
        source_trace_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    _initialized = true;
  }

  Future<void> putCase(LocalBenchmarkCase value) async {
    await initialize();
    if (value.id.trim().isEmpty || value.question.trim().isEmpty) {
      throw ArgumentError('Case ID and question must not be empty');
    }
    if (value.expectedDocumentIds.isEmpty && value.expectedChunkIds.isEmpty) {
      throw ArgumentError(
        'At least one expected document or chunk must be selected',
      );
    }
    _db!.execute('''
      INSERT INTO pg_local_benchmark_cases (
        case_id, question, expected_document_ids_json,
        expected_chunk_ids_json, tags_json, source_trace_id,
        created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(case_id) DO UPDATE SET
        question = excluded.question,
        expected_document_ids_json = excluded.expected_document_ids_json,
        expected_chunk_ids_json = excluded.expected_chunk_ids_json,
        tags_json = excluded.tags_json,
        source_trace_id = excluded.source_trace_id,
        updated_at = excluded.updated_at
    ''', [
      value.id,
      value.question.trim(),
      _encodeSet(value.expectedDocumentIds),
      _encodeSet(value.expectedChunkIds),
      _encodeSet(value.tags),
      value.sourceTraceId,
      value.createdAt.toUtc().toIso8601String(),
      value.updatedAt.toUtc().toIso8601String(),
    ]);
  }

  Future<LocalBenchmarkCase?> caseById(String id) async {
    await initialize();
    final rows = _db!.select(
      'SELECT * FROM pg_local_benchmark_cases WHERE case_id = ? LIMIT 1',
      [id],
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<List<LocalBenchmarkCase>> listCases() async {
    await initialize();
    return _db!
        .select('''
          SELECT * FROM pg_local_benchmark_cases
          ORDER BY updated_at DESC, case_id
        ''')
        .map(_fromRow)
        .toList(growable: false);
  }

  Future<void> deleteCase(String id) async {
    await initialize();
    _db!.execute(
      'DELETE FROM pg_local_benchmark_cases WHERE case_id = ?',
      [id],
    );
  }

  String _encodeSet(Set<String> values) {
    final sorted = values.toList()..sort();
    return jsonEncode(sorted);
  }

  Set<String> _decodeSet(Object? value) {
    if (value is! String || value.isEmpty) return <String>{};
    try {
      return (jsonDecode(value) as List<dynamic>).whereType<String>().toSet();
    } catch (_) {
      return <String>{};
    }
  }

  LocalBenchmarkCase _fromRow(Row row) => LocalBenchmarkCase(
        id: row['case_id'] as String,
        question: row['question'] as String,
        expectedDocumentIds: _decodeSet(
          row['expected_document_ids_json'],
        ),
        expectedChunkIds: _decodeSet(row['expected_chunk_ids_json']),
        tags: _decodeSet(row['tags_json']),
        sourceTraceId: row['source_trace_id'] as String?,
        createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
        updatedAt: DateTime.parse(row['updated_at'] as String).toUtc(),
      );

  void dispose() {
    if (_ownsDatabase) _db?.close();
    _db = null;
    _initialized = false;
  }
}
