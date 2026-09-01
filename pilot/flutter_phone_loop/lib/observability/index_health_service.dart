import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/models.dart';
import '../lineage/vector_index_health_service.dart';
import '../services/lexical_fts_store.dart';
import 'vector_observation_store.dart';

class ChunkInspection {
  const ChunkInspection({
    required this.chunk,
    required this.characterCount,
    required this.overlapChars,
    required this.ftsReady,
    required this.vectorReady,
    required this.vectorDimension,
    required this.vectorNorm,
    required this.vectorModelIdentity,
  });

  final PgChunk chunk;
  final int characterCount;
  final int overlapChars;
  final bool ftsReady;
  final bool vectorReady;
  final int? vectorDimension;
  final double? vectorNorm;
  final String? vectorModelIdentity;
}

class IndexHealthSnapshot {
  const IndexHealthSnapshot({
    required this.documentCount,
    required this.chunkCount,
    required this.ftsIndexedCount,
    required this.vectorIndexedCount,
    required this.missingVectorCount,
    required this.staleVectorCount,
    required this.zeroChunkDocuments,
    required this.duplicateShaGroups,
    required this.ftsDbBytes,
    required this.vectorDbBytes,
    required this.observabilityDbBytes,
    this.activeVectorHealth,
  });

  final int documentCount;
  final int chunkCount;
  final int ftsIndexedCount;
  final int vectorIndexedCount;
  final int missingVectorCount;
  final int staleVectorCount;
  final int zeroChunkDocuments;
  final int duplicateShaGroups;
  final int? ftsDbBytes;
  final int? vectorDbBytes;
  final int? observabilityDbBytes;
  final ActiveVectorHealth? activeVectorHealth;

  double get ftsCoverage => chunkCount == 0 ? 1 : ftsIndexedCount / chunkCount;
  double get vectorCoverage =>
      chunkCount == 0 ? 1 : vectorIndexedCount / chunkCount;
}

class IndexHealthService {
  IndexHealthService({
    required this.lexicalStore,
    required this.vectorStore,
    required this.activeModelIdentity,
    this.activeVectorHealthService,
  });

  final LexicalFtsStore lexicalStore;
  final VectorObservationStore vectorStore;
  final String Function() activeModelIdentity;
  final VectorIndexHealthService? activeVectorHealthService;

  Future<IndexHealthSnapshot> snapshot({bool includeFileSizes = true}) async {
    final documents = await lexicalStore.listDocuments();
    final chunks = await lexicalStore.allChunks();
    final observations = await vectorStore.listAll();
    final observationById = {
      for (final observation in observations) observation.chunkId: observation,
    };
    final activeModel = activeModelIdentity();
    final activeVectorHealth = await activeVectorHealthService?.snapshot();

    var missing = 0;
    var stale = 0;
    for (final chunk in chunks) {
      final observation = observationById[chunk.id];
      if (observation == null) {
        missing++;
      } else if (activeModel.isNotEmpty &&
          observation.modelIdentity != activeModel) {
        stale++;
      }
    }

    final shaCounts = <String, int>{};
    for (final document in documents) {
      if (document.sha256.isNotEmpty) {
        shaCounts.update(document.sha256, (v) => v + 1, ifAbsent: () => 1);
      }
    }

    int? ftsBytes;
    int? vectorBytes;
    int? observationBytes;
    if (includeFileSizes) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        ftsBytes = await _fileLength(p.join(dir.path, 'pocketgallery_fts5.db'));
        vectorBytes = await _fileLength(
          p.join(dir.path, 'pocketgallery_vectors.db'),
        );
        observationBytes = await _fileLength(
          p.join(dir.path, 'pocketgallery_observability.db'),
        );
      } catch (_) {
        // File-size telemetry is optional; logical health remains available.
      }
    }

    // pg_chunks and pg_chunks_fts are written/deleted in the same explicit
    // transaction by LexicalFtsStore. This count is therefore a REAL invariant
    // of the local store's write path, rather than a synthetic percentage.
    final ftsCount = chunks.length;

    return IndexHealthSnapshot(
      documentCount: documents.length,
      chunkCount: chunks.length,
      ftsIndexedCount: ftsCount,
      vectorIndexedCount: chunks
          .where((chunk) => observationById.containsKey(chunk.id))
          .length,
      missingVectorCount: missing,
      staleVectorCount: stale,
      zeroChunkDocuments: documents.where((d) => d.chunkCount == 0).length,
      duplicateShaGroups: shaCounts.values.where((count) => count > 1).length,
      ftsDbBytes: ftsBytes,
      vectorDbBytes: vectorBytes,
      observabilityDbBytes: observationBytes,
      activeVectorHealth: activeVectorHealth,
    );
  }

  Future<List<ChunkInspection>> inspectDocument(String documentId) async {
    final chunks = await lexicalStore.chunksForDocument(documentId);
    final observations = {
      for (final observation in await vectorStore.listForDocuments({
        documentId,
      }))
        observation.chunkId: observation,
    };
    final result = <ChunkInspection>[];
    for (var i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      final observation = observations[chunk.id];
      result.add(
        ChunkInspection(
          chunk: chunk,
          characterCount: chunk.text.runes.length,
          overlapChars: i == 0 ? 0 : _overlap(chunks[i - 1].text, chunk.text),
          ftsReady: true,
          vectorReady: observation != null,
          vectorDimension: observation?.dimension,
          vectorNorm: observation?.norm,
          vectorModelIdentity: observation?.modelIdentity,
        ),
      );
    }
    return result;
  }

  Future<int?> _fileLength(String path) async {
    final file = File(path);
    return await file.exists() ? file.length() : null;
  }

  int _overlap(String previous, String current) {
    final max = previous.length < current.length
        ? previous.length
        : current.length;
    final bound = max > 256 ? 256 : max;
    for (var length = bound; length > 0; length--) {
      if (previous.substring(previous.length - length) ==
          current.substring(0, length)) {
        return length;
      }
    }
    return 0;
  }
}
