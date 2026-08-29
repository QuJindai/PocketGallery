import 'package:flutter_gemma/flutter_gemma.dart';

import '../core/evidence.dart';
import '../core/hybrid_ranker.dart';
import '../core/models.dart';
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
  })  : lexicalStore = lexicalStore ?? LexicalFtsStore(),
        importer = importer ?? DocumentImporter(),
        gemma = gemma ?? GemmaService() {
    semanticStore = SemanticStore(this.lexicalStore);
    retriever = KnowledgeRetriever(
      lexicalStore: this.lexicalStore,
      semanticStore: semanticStore,
      ranker: ranker,
      evidenceBuilder: evidenceBuilder,
    );
  }

  final LexicalFtsStore lexicalStore;
  late final SemanticStore semanticStore;
  late final KnowledgeRetriever retriever;
  final DocumentImporter importer;
  final GemmaService gemma;
  final HybridRanker ranker = const HybridRanker();
  final EvidencePackBuilder evidenceBuilder = const EvidencePackBuilder();
  final CitationResolver citationResolver = CitationResolver();

  Future<void> initialize() async {
    await lexicalStore.initialize();
    await semanticStore.initialize();
  }

  Future<ImportedDocument> importPath(String path) async {
    await initialize();
    final doc = await importer.importPath(path);
    final oldIds = await lexicalStore.chunkIdsForDocument(doc.documentId);
    if (FlutterGemma.hasActiveEmbedder() && oldIds.isNotEmpty) {
      await semanticStore.removeIds(oldIds);
    }
    await lexicalStore.replaceDocument(doc);
    if (FlutterGemma.hasActiveEmbedder() && doc.chunks.isNotEmpty) {
      await semanticStore.addChunks(doc.chunks);
    }
    return doc;
  }

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

    await semanticStore.addChunks(pendingChunks, onProgress: (completed, total, current) {
      onProgress?.call(SemanticSyncProgress(
        total: total,
        completed: completed,
        currentSource: current.sourceName,
        currentChunkId: current.id,
      ));
    });
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
    lexicalStore.dispose();
  }
}
