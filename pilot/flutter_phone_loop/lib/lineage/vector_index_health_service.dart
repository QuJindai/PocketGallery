import '../chat/chat_models.dart';
import '../retrieval/active_vector_index.dart';
import '../services/lexical_fts_store.dart';
import 'lineage_ids.dart';
import 'lineage_models.dart';
import 'lineage_store.dart';
import 'runtime_lineage_recorder.dart';

/// A durable, ACTIVE-lane view of vector readiness.
///
/// [generated] and [persisted] are intentionally separate fields even though
/// this snapshot can only count a generated vector after its durable lineage
/// row exists. Generation attempts that never reached durable storage are not
/// observable and therefore are never invented here.
class ActiveVectorHealth {
  const ActiveVectorHealth({
    required this.required,
    required this.generated,
    required this.persisted,
    required this.indexed,
    required this.searchVerified,
    required this.pending,
    required this.failed,
    required this.staleModel,
  });

  final int required;
  final int generated;
  final int persisted;
  final int indexed;
  final bool searchVerified;
  final int pending;
  final int failed;
  final int staleModel;

  bool get ready =>
      required > 0 &&
      generated == required &&
      persisted == required &&
      indexed == required &&
      searchVerified &&
      pending == 0 &&
      failed == 0 &&
      staleModel == 0;
}

/// Verifies the body-vector path that retrieval actually uses.
///
/// SHADOW representations and the legacy observation database are excluded by
/// construction. A committed metadata row is necessary but not sufficient:
/// readiness also requires a real scoped search through [activeVectorIndex].
class VectorIndexHealthService {
  VectorIndexHealthService({
    required this.lexicalStore,
    required this.lineageStore,
    required this.activeVectorIndex,
    required this.activeModelIdentity,
    this.strategyId = RuntimeLineageRecorder.activeStrategyId,
  });

  final LexicalFtsStore lexicalStore;
  final LineageStore lineageStore;
  final ActiveVectorIndex activeVectorIndex;
  final String Function() activeModelIdentity;
  final String strategyId;

  Future<ActiveVectorHealth> snapshot() async {
    final chunks = await lexicalStore.allChunks();
    final activeModel = activeModelIdentity().trim();

    var generated = 0;
    var persisted = 0;
    var indexed = 0;
    var pending = 0;
    var failed = 0;
    var staleModel = 0;
    VectorIndexProbe? probe;
    try {
      probe = await activeVectorIndex.probe();
    } catch (_) {
      // Probe failure is represented as an unverified, non-ready snapshot.
    }

    LineageEmbedding? searchSample;
    String? searchDocumentId;
    for (final chunk in chunks) {
      final embeddingId = LineageIds.bodyEmbeddingId(chunk.id);
      final embedding = await lineageStore.embeddingById(embeddingId);
      final entry = await lineageStore.vectorIndexEntryForEmbedding(
        embeddingId,
        strategyId,
        RetrievalLane.active,
      );
      if (!_isValidBodyEmbedding(embedding, chunk.id)) {
        if (entry?.commitStatus == VectorCommitStatus.failed) {
          failed++;
        } else {
          pending++;
        }
        continue;
      }

      generated++;
      persisted++;
      if (activeModel.isEmpty || embedding!.modelIdentity != activeModel) {
        staleModel++;
      }

      if (entry == null ||
          probe == null ||
          entry.backendId != probe.backendId ||
          entry.commitStatus == VectorCommitStatus.pending) {
        pending++;
        continue;
      }
      if (entry.commitStatus == VectorCommitStatus.failed) {
        failed++;
        continue;
      }

      indexed++;
      searchSample ??= embedding;
      searchDocumentId ??= chunk.documentId;
    }

    var searchVerified = false;
    final sample = searchSample;
    final sampleDocument = searchDocumentId;
    final structurallyReady =
        chunks.isNotEmpty &&
        generated == chunks.length &&
        persisted == chunks.length &&
        indexed == chunks.length &&
        pending == 0 &&
        failed == 0 &&
        staleModel == 0 &&
        probe?.initialized == true;
    if (structurallyReady && sample != null && sampleDocument != null) {
      try {
        final hits = await activeVectorIndex.searchByEmbedding(
          queryEmbedding: sample.vector,
          topK: 8,
          scope: KnowledgeScope.documents(<String>{sampleDocument}),
        );
        searchVerified = hits.any(
          (hit) =>
              hit.embeddingId == sample.embeddingId &&
              hit.chunkId == sample.chunkId &&
              hit.documentId == sampleDocument,
        );
      } catch (_) {
        // Search failures are health evidence, not screen-breaking errors.
      }
    }

    return ActiveVectorHealth(
      required: chunks.length,
      generated: generated,
      persisted: persisted,
      indexed: indexed,
      searchVerified: searchVerified,
      pending: pending,
      failed: failed,
      staleModel: staleModel,
    );
  }

  bool _isValidBodyEmbedding(LineageEmbedding? embedding, String chunkId) {
    if (embedding == null ||
        embedding.sourceKind != 'chunk' ||
        embedding.sourceId != chunkId ||
        embedding.chunkId != chunkId ||
        embedding.representation != EmbeddingRepresentation.body) {
      return false;
    }
    try {
      embedding.validate();
      return true;
    } catch (_) {
      return false;
    }
  }
}
