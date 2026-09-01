import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

class VectorObservation {
  const VectorObservation({
    required this.chunkId,
    required this.documentId,
    required this.vector,
    required this.dimension,
    required this.norm,
    required this.modelIdentity,
    required this.updatedAt,
  });

  final String chunkId;
  final String documentId;
  final List<double> vector;
  final int dimension;
  final double norm;
  final String modelIdentity;
  final DateTime updatedAt;
}

class VectorObservationIdentity {
  const VectorObservationIdentity({
    required this.chunkId,
    required this.documentId,
    required this.dimension,
    required this.norm,
    required this.modelIdentity,
  });

  final String chunkId;
  final String documentId;
  final int dimension;
  final double norm;
  final String modelIdentity;
}

class VectorObservationStore {
  VectorObservationStore({Database? database})
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
      CREATE TABLE IF NOT EXISTS pg_vector_observations (
        chunk_id TEXT PRIMARY KEY,
        document_id TEXT NOT NULL,
        dimension INTEGER NOT NULL,
        vector_f32 BLOB NOT NULL,
        norm REAL NOT NULL,
        model_identity TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    _db!.execute('''
      CREATE INDEX IF NOT EXISTS pg_vector_observations_document
      ON pg_vector_observations(document_id, chunk_id);
    ''');
    _initialized = true;
  }

  Future<void> putChunkVector({
    required String chunkId,
    required String documentId,
    required List<double> vector,
    required String modelIdentity,
    DateTime? updatedAt,
  }) async {
    await initialize();
    if (vector.isEmpty) {
      throw ArgumentError.value(vector, 'vector', 'must not be empty');
    }
    final norm = math.sqrt(vector.fold<double>(0, (s, x) => s + x * x));
    final bytes = encodeFloat32(vector);
    _db!.execute('''
      INSERT OR REPLACE INTO pg_vector_observations
      (chunk_id, document_id, dimension, vector_f32, norm, model_identity, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    ''', [
      chunkId,
      documentId,
      vector.length,
      bytes,
      norm,
      modelIdentity,
      (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
    ]);
  }

  Future<VectorObservation?> getChunkVector(String chunkId) async {
    await initialize();
    final rows = _db!.select('''
      SELECT chunk_id, document_id, dimension, vector_f32, norm,
             model_identity, updated_at
      FROM pg_vector_observations
      WHERE chunk_id = ? LIMIT 1
    ''', [chunkId]);
    if (rows.isEmpty) return null;
    return _row(rows.first);
  }

  Future<List<VectorObservation>> listForDocuments(Set<String> documentIds) async {
    await initialize();
    if (documentIds.isEmpty) return const [];
    final ids = documentIds.toList()..sort();
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = _db!.select('''
      SELECT chunk_id, document_id, dimension, vector_f32, norm,
             model_identity, updated_at
      FROM pg_vector_observations
      WHERE document_id IN ($placeholders)
      ORDER BY document_id, chunk_id
    ''', ids);
    return rows.map(_row).toList(growable: false);
  }

  Future<List<VectorObservation>> listAll({int? limit}) async {
    await initialize();
    final sql = StringBuffer('''
      SELECT chunk_id, document_id, dimension, vector_f32, norm,
             model_identity, updated_at
      FROM pg_vector_observations
      ORDER BY document_id, chunk_id
    ''');
    final args = <Object?>[];
    if (limit != null) {
      sql.write(' LIMIT ?');
      args.add(limit.clamp(1, 10000));
    }
    return _db!.select(sql.toString(), args).map(_row).toList(growable: false);
  }

  Future<List<VectorObservationIdentity>> listIdentities() async {
    await initialize();
    final rows = _db!.select('''
      SELECT chunk_id, document_id, dimension, norm, model_identity
      FROM pg_vector_observations
      ORDER BY document_id, chunk_id
    ''');
    return rows
        .map(
          (row) => VectorObservationIdentity(
            chunkId: row['chunk_id'] as String,
            documentId: row['document_id'] as String,
            dimension: (row['dimension'] as num).toInt(),
            norm: (row['norm'] as num).toDouble(),
            modelIdentity: row['model_identity'] as String,
          ),
        )
        .toList(growable: false);
  }

  Future<int> count() async {
    await initialize();
    return (_db!.select('SELECT COUNT(*) AS c FROM pg_vector_observations').first['c']
            as num)
        .toInt();
  }

  Future<void> removeChunkIds(Iterable<String> chunkIds) async {
    await initialize();
    final stmt = _db!.prepare(
      'DELETE FROM pg_vector_observations WHERE chunk_id = ?',
    );
    try {
      for (final id in chunkIds) {
        stmt.execute([id]);
      }
    } finally {
      stmt.close();
    }
  }

  Future<void> clear() async {
    await initialize();
    _db!.execute('DELETE FROM pg_vector_observations');
  }

  VectorObservation _row(Row row) {
    final dimension = (row['dimension'] as num).toInt();
    final vector = decodeFloat32(row['vector_f32'] as Uint8List, dimension);
    return VectorObservation(
      chunkId: row['chunk_id'] as String,
      documentId: row['document_id'] as String,
      vector: vector,
      dimension: dimension,
      norm: (row['norm'] as num).toDouble(),
      modelIdentity: row['model_identity'] as String,
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  static Uint8List encodeFloat32(List<double> vector) {
    final data = ByteData(vector.length * 4);
    for (var i = 0; i < vector.length; i++) {
      data.setFloat32(i * 4, vector[i], Endian.little);
    }
    return data.buffer.asUint8List();
  }

  static List<double> decodeFloat32(Uint8List bytes, int dimension) {
    if (bytes.lengthInBytes != dimension * 4) {
      throw StateError(
        'Vector BLOB length ${bytes.lengthInBytes} does not match dimension $dimension',
      );
    }
    final data = ByteData.sublistView(bytes);
    return List<double>.generate(
      dimension,
      (i) => data.getFloat32(i * 4, Endian.little),
      growable: false,
    );
  }

  void dispose() {
    if (_ownsDatabase) _db?.close();
    _db = null;
    _initialized = false;
  }
}
