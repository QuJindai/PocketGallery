import 'dart:convert';

import 'package:flutter_gemma/flutter_gemma.dart';

import '../core/evidence.dart';
import '../core/hybrid_ranker.dart';
import '../core/models.dart';
import '../lineage/lineage_ids.dart';
import '../lineage/lineage_models.dart';
import '../lineage/lineage_store.dart';
import '../lineage/r45_vector_migration.dart';
import '../lineage/runtime_lineage_recorder.dart';
import '../retrieval/active_vector_index.dart';
import '../retrieval/query_embedding_runtime.dart';
import '../retrieval/retrieval_runtime.dart';
import '../retrieval/sqlite_active_vector_index.dart';
import 'document_importer.dart';
import 'gemma_service.dart';
import 'knowledge_retriever.dart';
import 'lexical_fts_store.dart';
import 'semantic_store.dart';

class SemanticSyncProgress {
  const SemanticSyncProgress({
    required this.total,
    required this.completed,
    this.currentSource,
    this.currentChunkId,
  });

  final int total;
  final int completed;
  final String? currentSource;
  final String? currentChunkId;

  double get percent => total == 0 ? 1.0 : completed / total;
}

class KnowledgeEngine {
  KnowledgeEngine({
    LexicalFtsStore? lexicalStore,
    DocumentImporter? importer,
    GemmaService? gemma,
    SemanticStore? semanticStore,
    LineageStore? lineageStore,
    ActiveVectorIndex? activeVectorIndex,
  })  : lexicalStore = lexicalStore ?? LexicalFtsStore(),
        importer = importer ?? DocumentImporter(),
        gemma = gemma ?? GemmaService() {
    this.semanticStore = semanticStore ?? SemanticStore(this.lexicalStore);
    this.lineageStore = lineageStore ?? LineageStore();
    this.activeVectorIndex = activeVectorIndex ?? SqliteActiveVectorIndex();
    queryEmbeddingRuntime = QueryEmbeddingRuntime(
      generator: const FlutterGemmaEmbeddingGenerator(),
      store: this.lineageStore,
      modelIdentity: SemanticStore.embeddingModelIdentity,
    );
    runtimeLineageRecorder = RuntimeLineageRecorder(store: this.lineageStore);
    retrievalRuntime = RetrievalRuntime(
      lexicalStore: this.lexicalStore,
      queryEmbeddingRuntime: queryEmbeddingRuntime,
      activeVectorIndex: this.activeVectorIndex,
      recorder: runtimeLineageRecorder,
      embedderReady: FlutterGemma.hasActiveEmbedder,
      ranker: ranker,
    );
    r45VectorMigration = R45VectorMigration(
      lexicalStore: this.lexicalStore,
      observationStore: this.semanticStore.observationStore,
      lineageStore: this.lineageStore,
      activeVectorIndex: this.activeVectorIndex,
      embeddingGenerator: (chunk) async {
        final embedder = await FlutterGemma.getActiveEmbedder();
        return embedder.generateEmbedding(
          chunk.text,
          taskType: TaskType.retrievalDocument,
        );
      },
    );
    retriever = KnowledgeRetriever(
      lexicalStore: this.lexicalStore,
      semanticStore: this.semanticStore,
      ranker: ranker,
      evidenceBuilder: evidenceBuilder,
      runtime: retrievalRuntime,
    );
  }

  final LexicalFtsStore lexicalStore;
  late final SemanticStore semanticStore;
  late final KnowledgeRetriever retriever;
  late final LineageStore lineageStore;
  late final ActiveVectorIndex activeVectorIndex;
  late final QueryEmbeddingRuntime queryEmbeddingRuntime;
  late final RuntimeLineageRecorder runtimeLineageRecorder;
  late final RetrievalRuntime retrievalRuntime;
  late final R45VectorMigration r45VectorMigration;
  final DocumentImporter importer;
  final GemmaService gemma;
  final HybridRanker ranker = const HybridRanker();
  final EvidencePackBuilder evidenceBuilder = const EvidencePackBuilder();
  final CitationResolver citationResolver = CitationResolver();
  bool _r46MigrationReady = false;

  Future<void> initialize() async {
    await lexicalStore.initialize();
    await semanticStore.initialize();
    await lineageStore.initialize();
    await activeVectorIndex.initialize();

    // Keep the R4.5 retrieval stores intact. R4.6 only copies healthy Float32
    // observations into its own lineage/index and generates a body embedding
    // when the old observation is missing, stale or invalid. If the embedder
    // is not active yet, a later initialize() call after model setup resumes
    // this gate without triggering a model download here.
    if (!_r46MigrationReady && FlutterGemma.hasActiveEmbedder()) {
      final embedder = await FlutterGemma.getActiveEmbedder();
      final expectedDimension = await embedder.getDimension();
      final report = await r45VectorMigration.migrateActiveBodyVectors(
        activeModelIdentity: SemanticStore.embeddingModelIdentity,
        expectedDimension: expectedDimension,
      );
      _r46MigrationReady = report.failed == 0;
    }
  }

  Future<ImportedDocument> importPath(String path) async {
    await initialize();
    final result = await importer.importPathWithLineage(path);
    final doc = result.document;
    var buildState = BuildState.prepared;
    await _recordImportBuildState(
      doc,
      buildState,
      status: BuildJobStatus.running,
    );
    final oldIds = await lexicalStore.chunkIdsForDocument(doc.documentId);
    try {
      if (FlutterGemma.hasActiveEmbedder() && oldIds.isNotEmpty) {
        await semanticStore.removeIds(oldIds);
      }
      await lexicalStore.replaceDocument(doc);
      buildState = BuildState.lexicalCommitted;
      await _recordImportBuildState(
        doc,
        buildState,
        status: BuildJobStatus.running,
      );

      await lineageStore.replaceImportLineage(result);
      buildState = BuildState.lineageCommitted;
      await _recordImportBuildState(
        doc,
        buildState,
        status: doc.chunks.isEmpty
            ? BuildJobStatus.complete
            : BuildJobStatus.pending,
      );

      if (doc.chunks.isEmpty) {
        buildState = BuildState.ready;
        await _recordImportBuildState(
          doc,
          buildState,
          status: BuildJobStatus.complete,
        );
      } else if (FlutterGemma.hasActiveEmbedder()) {
        await semanticStore.addChunks(doc.chunks);
        final embedder = await FlutterGemma.getActiveEmbedder();
        final report = await r45VectorMigration.migrateActiveBodyVectors(
          activeModelIdentity: SemanticStore.embeddingModelIdentity,
          expectedDimension: await embedder.getDimension(),
        );
        if (report.failed != 0) {
          throw StateError(
            'ACTIVE vector commit failed for ${report.failed} item(s)',
          );
        }
        _r46MigrationReady = true;
        buildState = BuildState.ready;
      }
      return doc;
    } catch (error) {
      await _recordImportBuildState(
        doc,
        buildState,
        status: BuildJobStatus.failed,
        failureCode: 'IMPORT_BUILD_FAILED',
        failureDetail: error.toString(),
      );
      rethrow;
    }
  }

  Future<void> _recordImportBuildState(
    ImportedDocument document,
    BuildState state, {
    required BuildJobStatus status,
    String? failureCode,
    String? failureDetail,
  }) async {
    final now = DateTime.now().toUtc();
    final jobId = LineageIds.buildJobId(
      document.documentId,
      R45VectorMigration.activeStrategyId,
    );
    final existing = await lineageStore.buildJobById(jobId);
    await lineageStore.putBuildJob(BuildJobRecord(
      jobId: jobId,
      jobType: 'r46-import-lineage',
      strategyId: R45VectorMigration.activeStrategyId,
      documentId: document.documentId,
      status: status,
      totalItems: document.chunks.length,
      completedItems: state == BuildState.ready ? document.chunks.length : 0,
      checkpointJson: jsonEncode({
        'state': _buildStateValue(state),
        'chunkCount': document.chunks.length,
      }),
      currentSource: document.sourceName,
      failureCode: failureCode,
      failureDetail: failureDetail,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    ));
  }

  String _buildStateValue(BuildState state) => switch (state) {
        BuildState.prepared => 'prepared',
        BuildState.lexicalCommitted => 'lexical_committed',
        BuildState.lineageCommitted => 'lineage_committed',
        BuildState.vectorCommitted => 'vector_committed',
        BuildState.ready => 'ready',
      };

  Future<List<KnowledgeDocument>> listDocuments() async {
    await lexicalStore.initialize();
    return lexicalStore.listDocuments();
  }

  Future<void> removeDocument(String documentId) async {
    await initialize();
    final ids = await lexicalStore.chunkIdsForDocument(documentId);

    // Make the user-visible lexical/document deletion authoritative. A native
    // vector-store cleanup failure must never leave a supposedly temporary or
    // deleted document visible in the real knowledge library.
    try {
      await lexicalStore.removeDocument(documentId);
    } finally {
      if (ids.isNotEmpty) {
        try {
          if (FlutterGemma.hasActiveEmbedder()) {
            await semanticStore.removeIds(ids);
          } else {
            await semanticStore.observationStore.removeChunkIds(ids);
          }
        } catch (_) {
          // The RAG DB can retain an orphan row after a native cleanup error,
          // but semantic search resolves every hit back through lexicalStore
          // and therefore ignores it. Always remove the observability row so
          // index-health accounting remains truthful.
          await semanticStore.observationStore.removeChunkIds(ids);
        }
      }
    }
  }

  Future<void> rebuildDocumentEmbedding(String documentId) async {
    if (!FlutterGemma.hasActiveEmbedder()) return;
    await initialize();
    final chunks = await lexicalStore.chunksForDocument(documentId);
    if (chunks.isEmpty) return;
    await semanticStore.removeIds(chunks.map((x) => x.id));
    await semanticStore.addChunks(chunks);
  }

  Future<void> rebuildAllEmbeddings() async {
    if (!FlutterGemma.hasActiveEmbedder()) return;
    await initialize();
    final chunks = await lexicalStore.allChunks();
    await semanticStore.clear();
    if (chunks.isNotEmpty) await semanticStore.addChunks(chunks);
  }

  Future<void> syncMissingSemanticIndex({
    void Function(SemanticSyncProgress progress)? onProgress,
  }) async {
    if (!FlutterGemma.hasActiveEmbedder()) return;
    await initialize();

    final chunks = await lexicalStore.allChunks();
    final observations = await semanticStore.observationStore.listAll();
    final observationsByChunk = {
      for (final observation in observations) observation.chunkId: observation,
    };

    // Do not re-embed healthy chunks. This operation is deliberately
    // checkpoint/resume friendly: every successful add is persisted, and a
    // later run recomputes only the remaining missing/stale set.
    final pendingChunks = chunks.where((chunk) {
      final observation = observationsByChunk[chunk.id];
      return observation == null ||
          observation.modelIdentity != SemanticStore.embeddingModelIdentity;
    }).toList(growable: false);

    if (pendingChunks.isEmpty) {
      onProgress?.call(const SemanticSyncProgress(total: 0, completed: 0));
      return;
    }

    onProgress?.call(SemanticSyncProgress(
      total: pendingChunks.length,
      completed: 0,
      currentSource: pendingChunks.first.sourceName,
      currentChunkId: pendingChunks.first.id,
    ));

    await semanticStore.addChunks(pendingChunks,
      onProgress: (completed, total, current) {
        onProgress?.call(SemanticSyncProgress(
          total: total,
          completed: completed,
          currentSource: current.sourceName,
          currentChunkId: current.id,
        ));
      },
    );
  }

  Future<void> syncSemanticIndex() => syncMissingSemanticIndex();

  Future<KnowledgeAnswer> ask(String question) async {
    await initialize();
    final bundle = await retriever.retrieve(question);
    if (bundle.evidence.isEmpty) {
      return KnowledgeAnswer(
        answer: '未在本地资料中找到足够证据。',
        evidence: const [],
        citedAnchors: const [],
        lexicalHits: bundle.lexicalHits,
        semanticHits: bundle.semanticHits,
        hybridHits: bundle.hybridHits,
      );
    }

    if (!FlutterGemma.hasActiveModel()) {
      return KnowledgeAnswer(
        answer: '本机 Gemma 正在自动准备；FTS5 本地检索已经可用，请先查看下方 Evidence。模型就绪后会自动启用生成回答。',
        evidence: bundle.evidence,
        citedAnchors: const [],
        lexicalHits: bundle.lexicalHits,
        semanticHits: bundle.semanticHits,
        hybridHits: bundle.hybridHits,
      );
    }

    final answer = await gemma.answer(
      question: question,
      evidence: bundle.evidence,
    );
    return KnowledgeAnswer(
      answer: answer,
      evidence: bundle.evidence,
      citedAnchors: citationResolver.extract(answer, bundle.evidence),
      lexicalHits: bundle.lexicalHits,
      semanticHits: bundle.semanticHits,
      hybridHits: bundle.hybridHits,
    );
  }

  Future<void> clearAll() async {
    await initialize();
    if (FlutterGemma.hasActiveEmbedder()) await semanticStore.clear();
    await lexicalStore.clear();
  }

  Future<void> close() async {
    await gemma.close();
    await activeVectorIndex.close();
    lineageStore.dispose();
    lexicalStore.dispose();
    _r46MigrationReady = false;
  }
}
