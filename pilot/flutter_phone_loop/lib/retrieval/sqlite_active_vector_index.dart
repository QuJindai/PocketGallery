import 'dart:convert';

import 'package:flutter_gemma_rag_sqlite/flutter_gemma_rag_sqlite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../chat/chat_models.dart';
import 'active_vector_index.dart';

class BackendVectorHit {
  const BackendVectorHit({
    required this.id,
    required this.similarity,
    required this.metadataJson,
  });

  final String id;
  final double similarity;
  final String? metadataJson;
}

abstract interface class ActiveVectorBackend {
  bool get isInitialized;

  Future<void> initialize(String databasePath);

  Future<void> add({
    required String id,
    required String content,
    required List<double> embedding,
    required String metadataJson,
  });

  Future<void> remove(String id);

  Future<List<BackendVectorHit>> search({
    required List<double> queryEmbedding,
    required int topK,
  });

  Future<void> close();
}

class SqliteVectorBackend implements ActiveVectorBackend {
  SqliteVectorBackend({SqliteVectorStore? store})
    : _store = store ?? SqliteVectorStore();

  final SqliteVectorStore _store;

  @override
  bool get isInitialized => _store.isInitialized;

  @override
  Future<void> initialize(String databasePath) =>
      _store.initialize(databasePath);

  @override
  Future<void> add({
    required String id,
    required String content,
    required List<double> embedding,
    required String metadataJson,
  }) => _store.addDocument(
    id: id,
    content: content,
    embedding: embedding,
    metadata: metadataJson,
  );

  @override
  Future<void> remove(String id) => _store.removeDocument(id: id);

  @override
  Future<List<BackendVectorHit>> search({
    required List<double> queryEmbedding,
    required int topK,
  }) async {
    final rows = await _store.searchSimilar(
      queryEmbedding: queryEmbedding,
      topK: topK,
      threshold: -1.0,
    );
    return [
      for (final row in rows)
        BackendVectorHit(
          id: row.id,
          similarity: row.similarity,
          metadataJson: row.metadata,
        ),
    ];
  }

  @override
  Future<void> close() => _store.close();
}

class SqliteActiveVectorIndex implements ActiveVectorIndex {
  SqliteActiveVectorIndex({ActiveVectorBackend? backend, String? databasePath})
    : _backend = backend ?? SqliteVectorBackend(),
      _databasePathOverride = databasePath;

  SqliteActiveVectorIndex.forTest(
    ActiveVectorBackend backend, {
    String databasePath = 'pocketgallery_vectors_v46.db',
  }) : _backend = backend,
       _databasePathOverride = databasePath;

  static const databaseFileName = 'pocketgallery_vectors_v46.db';
  static const backendId = 'sqlite-vec-v46';

  final ActiveVectorBackend _backend;
  final String? _databasePathOverride;
  String? _resolvedDatabasePath;

  @override
  Future<void> initialize() async {
    if (_backend.isInitialized) return;
    final path =
        _databasePathOverride ??
        p.join(
          (await getApplicationDocumentsDirectory()).path,
          databaseFileName,
        );
    await _backend.initialize(path);
    _resolvedDatabasePath = path;
  }

  @override
  Future<void> add(VectorIndexRecord record) async {
    await initialize();
    if (record.embeddingId.isEmpty ||
        record.chunkId.isEmpty ||
        record.documentId.isEmpty) {
      throw ArgumentError('Vector index identity fields must be non-empty');
    }
    if (record.embeddingId == record.chunkId) {
      throw ArgumentError('embeddingId must be independent from chunkId');
    }
    if (record.embedding.isEmpty ||
        record.embedding.any((value) => !value.isFinite)) {
      throw ArgumentError(
        'Vector index embedding must be finite and non-empty',
      );
    }
    await _backend.add(
      id: record.embeddingId,
      content: record.content,
      embedding: record.embedding,
      metadataJson: jsonEncode({
        'chunkId': record.chunkId,
        'documentId': record.documentId,
        'modelIdentity': record.modelIdentity,
      }),
    );
  }

  @override
  Future<void> remove(String embeddingId) async {
    await initialize();
    await _backend.remove(embeddingId);
  }

  @override
  Future<List<VectorSearchHit>> searchByEmbedding({
    required List<double> queryEmbedding,
    required int topK,
    required KnowledgeScope scope,
  }) async {
    await initialize();
    if (topK <= 0 || queryEmbedding.isEmpty) return const [];
    if (queryEmbedding.any((value) => !value.isFinite)) {
      throw ArgumentError('Query embedding must contain only finite values');
    }
    final allowed = scope.documentIds;
    if (!scope.isAll && (allowed == null || allowed.isEmpty)) return const [];

    // Preserve the exact query vector object supplied by QueryEmbeddingRuntime.
    // Scope filtering is intentionally performed after a bounded deterministic
    // overfetch in Task 2; later work may push the filter into sqlite-vec once
    // that optimization is separately regression-tested.
    final candidateK = scope.isAll ? topK : (topK * 8).clamp(topK, 96).toInt();
    final rows = await _backend.search(
      queryEmbedding: queryEmbedding,
      topK: candidateK,
    );

    final out = <VectorSearchHit>[];
    for (final row in rows) {
      final metadata = _decodeMetadata(row.metadataJson);
      final chunkId = metadata['chunkId'];
      final documentId = metadata['documentId'];
      if (chunkId is! String || chunkId.isEmpty) continue;
      if (documentId is! String || documentId.isEmpty) continue;
      if (!scope.isAll && !allowed!.contains(documentId)) continue;
      out.add(
        VectorSearchHit(
          embeddingId: row.id,
          chunkId: chunkId,
          documentId: documentId,
          similarity: row.similarity,
          rank: out.length + 1,
        ),
      );
      if (out.length >= topK) break;
    }
    return out;
  }

  Map<String, dynamic> _decodeMetadata(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }

  @override
  Future<VectorIndexProbe> probe() async {
    final path =
        _resolvedDatabasePath ?? _databasePathOverride ?? databaseFileName;
    return VectorIndexProbe(
      initialized: _backend.isInitialized,
      databasePath: path,
      backendId: backendId,
      searchVerified: false,
    );
  }

  @override
  Future<void> close() async {
    await _backend.close();
    _resolvedDatabasePath = null;
  }
}
