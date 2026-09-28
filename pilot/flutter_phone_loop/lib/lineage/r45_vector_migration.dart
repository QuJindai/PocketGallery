import 'dart:convert';

import '../core/models.dart';
import '../observability/vector_observation_store.dart';
import '../retrieval/active_vector_index.dart';
import '../services/lexical_fts_store.dart';
import 'import_lineage.dart';
import 'lineage_ids.dart';
import 'lineage_models.dart';
import 'lineage_store.dart';

typedef DocumentEmbeddingGenerator =
    Future<List<double>> Function(PgChunk chunk);

class VectorMigrationReport {
  const VectorMigrationReport({
    required this.reusedFromR45,
    required this.generated,
    required this.resumedPersisted,
    required this.alreadyCommitted,
    required this.failed,
  });

  final int reusedFromR45;
  final int generated;
  final int resumedPersisted;
  final int alreadyCommitted;
  final int failed;
}

class VectorMigrationProgress {
  const VectorMigrationProgress({
    required this.total,
    required this.completed,
    required this.failed,
    this.currentSource,
    this.currentChunkId,
  });

  final int total;
  final int completed;
  final int failed;
  final String? currentSource;
  final String? currentChunkId;

  double get percent => total == 0 ? 1 : completed / total;
}

class R45VectorMigration {
  R45VectorMigration({
    required this.lexicalStore,
    required this.observationStore,
    required this.lineageStore,
    required this.activeVectorIndex,
    required this.embeddingGenerator,
  });

  static const activeStrategyId = 'active.r45-body-hybrid';

  final LexicalFtsStore lexicalStore;
  final VectorObservationStore observationStore;
  final LineageStore lineageStore;
  final ActiveVectorIndex activeVectorIndex;
  final DocumentEmbeddingGenerator embeddingGenerator;

  Future<VectorMigrationReport> migrateActiveBodyVectors({
    required String activeModelIdentity,
    required int expectedDimension,
    void Function(VectorMigrationProgress progress)? onProgress,
  }) async {
    if (activeModelIdentity.trim().isEmpty) {
      throw ArgumentError.value(
        activeModelIdentity,
        'activeModelIdentity',
        'must not be empty',
      );
    }
    if (expectedDimension <= 0) {
      throw ArgumentError.value(
        expectedDimension,
        'expectedDimension',
        'must be positive',
      );
    }

    await lexicalStore.initialize();
    await observationStore.initialize();
    await lineageStore.initialize();
    await activeVectorIndex.initialize();
    final backend = await activeVectorIndex.probe();

    final documents = await lexicalStore.listDocuments();
    final allChunks = await lexicalStore.allChunks();
    final observations = await observationStore.listAll();
    final observationByChunk = {
      for (final observation in observations) observation.chunkId: observation,
    };
    final chunksByDocument = <String, List<PgChunk>>{};
    for (final chunk in allChunks) {
      chunksByDocument
          .putIfAbsent(chunk.documentId, () => <PgChunk>[])
          .add(chunk);
    }

    var reusedFromR45 = 0;
    var generated = 0;
    var resumedPersisted = 0;
    var alreadyCommitted = 0;
    var failed = 0;
    var processed = 0;

    void progress(PgChunk? current) {
      onProgress?.call(
        VectorMigrationProgress(
          total: allChunks.length,
          completed: processed,
          failed: failed,
          currentSource: current?.sourceName,
          currentChunkId: current?.id,
        ),
      );
    }

    progress(allChunks.isEmpty ? null : allChunks.first);

    for (final document in documents) {
      final chunks = <PgChunk>[...?chunksByDocument[document.documentId]]
        ..sort((a, b) => a.ordinal.compareTo(b.ordinal));
      final jobId = LineageIds.buildJobId(
        document.documentId,
        activeStrategyId,
      );
      final existingJob = await lineageStore.buildJobById(jobId);
      final createdAt = existingJob?.createdAt ?? DateTime.now().toUtc();

      await _putJob(
        jobId: jobId,
        documentId: document.documentId,
        status: BuildJobStatus.running,
        state: BuildState.prepared,
        totalItems: chunks.length,
        completedItems: 0,
        currentSource: document.sourceName,
        createdAt: createdAt,
      );
      await _writeLegacyLineage(document, chunks, createdAt);
      await _putJob(
        jobId: jobId,
        documentId: document.documentId,
        status: BuildJobStatus.running,
        state: BuildState.lineageCommitted,
        totalItems: chunks.length,
        completedItems: 0,
        currentSource: document.sourceName,
        createdAt: createdAt,
      );

      var committedForDocument = 0;
      var failedForDocument = 0;
      for (final chunk in chunks) {
        final embeddingId = LineageIds.bodyEmbeddingId(chunk.id);
        final existingIndex = await lineageStore.vectorIndexEntryForEmbedding(
          embeddingId,
          activeStrategyId,
          RetrievalLane.active,
        );
        if (existingIndex?.commitStatus == VectorCommitStatus.committed) {
          alreadyCommitted++;
          committedForDocument++;
          processed++;
          progress(chunk);
          continue;
        }

        LineageEmbedding? embedding = await lineageStore.embeddingById(
          embeddingId,
        );
        if (_reusablePersisted(
          embedding,
          activeModelIdentity,
          expectedDimension,
        )) {
          resumedPersisted++;
        } else {
          embedding = null;
          final observation = observationByChunk[chunk.id];
          if (_reusableObservation(
            observation,
            activeModelIdentity,
            expectedDimension,
          )) {
            embedding = LineageEmbedding.fromVector(
              embeddingId: embeddingId,
              sourceKind: 'chunk',
              sourceId: chunk.id,
              documentId: chunk.documentId,
              chunkId: chunk.id,
              representation: EmbeddingRepresentation.body,
              vector: observation!.vector,
              modelIdentity: activeModelIdentity,
              taskMode: 'retrieval_document',
              generationMs: 0,
              generatedAt: observation.updatedAt,
            );
            await lineageStore.putEmbedding(embedding);
            reusedFromR45++;
          } else {
            try {
              final vector = await embeddingGenerator(chunk);
              if (vector.length != expectedDimension) {
                throw StateError(
                  'Generated embedding dimension ${vector.length} != $expectedDimension',
                );
              }
              embedding = LineageEmbedding.fromVector(
                embeddingId: embeddingId,
                sourceKind: 'chunk',
                sourceId: chunk.id,
                documentId: chunk.documentId,
                chunkId: chunk.id,
                representation: EmbeddingRepresentation.body,
                vector: vector,
                modelIdentity: activeModelIdentity,
                taskMode: 'retrieval_document',
              );
              await lineageStore.putEmbedding(embedding);
              generated++;
            } catch (error) {
              failed++;
              failedForDocument++;
              await _putIndexEntry(
                embeddingId: embeddingId,
                backendId: backend.backendId,
                status: VectorCommitStatus.failed,
                failureCode: 'EMBEDDING_GENERATION_FAILED',
                failureDetail: '$error',
              );
              processed++;
              progress(chunk);
              continue;
            }
          }
        }

        final readyEmbedding = embedding;
        if (readyEmbedding == null) {
          failed++;
          failedForDocument++;
          await _putIndexEntry(
            embeddingId: embeddingId,
            backendId: backend.backendId,
            status: VectorCommitStatus.failed,
            failureCode: 'EMBEDDING_NOT_PERSISTED',
            failureDetail: 'No valid persisted body embedding was available.',
          );
          processed++;
          progress(chunk);
          continue;
        }

        await _putIndexEntry(
          embeddingId: readyEmbedding.embeddingId,
          backendId: backend.backendId,
          status: VectorCommitStatus.pending,
        );
        try {
          await activeVectorIndex.add(
            VectorIndexRecord(
              embeddingId: readyEmbedding.embeddingId,
              chunkId: chunk.id,
              documentId: chunk.documentId,
              content: chunk.text,
              embedding: readyEmbedding.vector,
              modelIdentity: readyEmbedding.modelIdentity,
            ),
          );
          await _putIndexEntry(
            embeddingId: readyEmbedding.embeddingId,
            backendId: backend.backendId,
            status: VectorCommitStatus.committed,
            committedAt: DateTime.now().toUtc(),
          );
          committedForDocument++;
        } catch (error) {
          failed++;
          failedForDocument++;
          await _putIndexEntry(
            embeddingId: readyEmbedding.embeddingId,
            backendId: backend.backendId,
            status: VectorCommitStatus.failed,
            failureCode: 'VECTOR_INDEX_ADD_FAILED',
            failureDetail: '$error',
          );
        }
        processed++;
        progress(chunk);
      }

      if (failedForDocument == 0 && committedForDocument == chunks.length) {
        await _putJob(
          jobId: jobId,
          documentId: document.documentId,
          status: BuildJobStatus.running,
          state: BuildState.vectorCommitted,
          totalItems: chunks.length,
          completedItems: committedForDocument,
          currentSource: document.sourceName,
          createdAt: createdAt,
        );
        await _putJob(
          jobId: jobId,
          documentId: document.documentId,
          status: BuildJobStatus.complete,
          state: BuildState.ready,
          totalItems: chunks.length,
          completedItems: committedForDocument,
          currentSource: document.sourceName,
          createdAt: createdAt,
        );
      } else {
        await _putJob(
          jobId: jobId,
          documentId: document.documentId,
          status: BuildJobStatus.failed,
          state: BuildState.lineageCommitted,
          totalItems: chunks.length,
          completedItems: committedForDocument,
          currentSource: document.sourceName,
          createdAt: createdAt,
          failureCode: 'R45_VECTOR_MIGRATION_INCOMPLETE',
          failureDetail:
              '$failedForDocument vector operation(s) failed for ${document.sourceName}',
        );
      }
    }

    return VectorMigrationReport(
      reusedFromR45: reusedFromR45,
      generated: generated,
      resumedPersisted: resumedPersisted,
      alreadyCommitted: alreadyCommitted,
      failed: failed,
    );
  }

  Future<void> _writeLegacyLineage(
    KnowledgeDocument document,
    List<PgChunk> chunks,
    DateTime importedAt,
  ) async {
    final existing = await lineageStore.lineageDocumentById(
      document.documentId,
    );
    if (existing?.provenanceQuality == ProvenanceQuality.exact) {
      return;
    }
    await lineageStore.upsertLineageDocument(
      documentId: document.documentId,
      sourceName: document.sourceName,
      sha256: document.sha256,
      fileType: _fileType(document.sourceName),
      sizeBytes: null,
      pageCount: null,
      parseStatus: 'legacy-existing',
      parseErrorCode: null,
      parseErrorDetail: null,
      extractedCharCount: chunks.fold<int>(
        0,
        (sum, chunk) => sum + chunk.text.runes.length,
      ),
      emptyPageCount: 0,
      provenanceQuality: 'legacy',
      importedAt: importedAt,
    );
    for (final chunk in chunks) {
      await lineageStore.upsertLineageChunk(
        chunkId: chunk.id,
        documentId: chunk.documentId,
        sectionId: null,
        locator: chunk.locator,
        ordinal: chunk.ordinal,
        startOffset: null,
        endOffset: null,
        charCount: chunk.text.runes.length,
        tokenCount: null,
        overlapFromPrevious: 0,
        chunkStrategy: 'r45-existing',
        boundaryReason: null,
        provenanceQuality: 'legacy',
      );
    }
  }

  bool _reusableObservation(
    VectorObservation? observation,
    String activeModelIdentity,
    int expectedDimension,
  ) =>
      observation != null &&
      observation.modelIdentity == activeModelIdentity &&
      observation.dimension == expectedDimension &&
      observation.vector.length == expectedDimension &&
      observation.norm.isFinite &&
      observation.norm > 0 &&
      observation.vector.every((value) => value.isFinite);

  bool _reusablePersisted(
    LineageEmbedding? embedding,
    String activeModelIdentity,
    int expectedDimension,
  ) {
    if (embedding == null ||
        embedding.modelIdentity != activeModelIdentity ||
        embedding.dimension != expectedDimension ||
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

  Future<void> _putIndexEntry({
    required String embeddingId,
    required String backendId,
    required VectorCommitStatus status,
    DateTime? committedAt,
    String? failureCode,
    String? failureDetail,
  }) => lineageStore.putVectorIndexEntry(
    VectorIndexEntryRecord(
      indexEntryId: LineageIds.vectorIndexEntryId(
        embeddingId,
        backendId,
        activeStrategyId,
        RetrievalLane.active,
      ),
      embeddingId: embeddingId,
      backendId: backendId,
      strategyId: activeStrategyId,
      lane: RetrievalLane.active,
      commitStatus: status,
      committedAt: committedAt,
      failureCode: failureCode,
      failureDetail: failureDetail,
    ),
  );

  Future<void> _putJob({
    required String jobId,
    required String documentId,
    required BuildJobStatus status,
    required BuildState state,
    required int totalItems,
    required int completedItems,
    required String currentSource,
    required DateTime createdAt,
    String? failureCode,
    String? failureDetail,
  }) => lineageStore.putBuildJob(
    BuildJobRecord(
      jobId: jobId,
      jobType: 'r45-active-body-migration',
      strategyId: activeStrategyId,
      documentId: documentId,
      status: status,
      totalItems: totalItems,
      completedItems: completedItems,
      checkpointJson: jsonEncode({'state': _buildStateValue(state)}),
      currentSource: currentSource,
      failureCode: failureCode,
      failureDetail: failureDetail,
      createdAt: createdAt,
      updatedAt: DateTime.now().toUtc(),
    ),
  );

  String _buildStateValue(BuildState state) => switch (state) {
    BuildState.prepared => 'prepared',
    BuildState.lexicalCommitted => 'lexical_committed',
    BuildState.lineageCommitted => 'lineage_committed',
    BuildState.vectorCommitted => 'vector_committed',
    BuildState.ready => 'ready',
  };

  String _fileType(String sourceName) {
    final dot = sourceName.lastIndexOf('.');
    if (dot < 0 || dot == sourceName.length - 1) return 'unknown';
    final ext = sourceName.substring(dot + 1).toLowerCase();
    return switch (ext) {
      'txt' || 'md' || 'pdf' => ext,
      _ => 'unknown',
    };
  }
}
