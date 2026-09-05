import 'package:flutter_gemma/flutter_gemma.dart';

import '../core/evidence.dart';
import '../core/hybrid_ranker.dart';
import '../core/models.dart';
import 'document_importer.dart';
import 'gemma_service.dart';
import 'knowledge_retriever.dart';
import 'lexical_fts_store.dart';
import 'semantic_store.dart';

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
    if (FlutterGemma.hasActiveEmbedder() && ids.isNotEmpty) {
      await semanticStore.removeIds(ids);
    }
    await lexicalStore.removeDocument(documentId);
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

  Future<void> syncSemanticIndex() async {
    if (!FlutterGemma.hasActiveEmbedder()) return;
    await initialize();
    final chunks = await lexicalStore.allChunks();
    if (chunks.isNotEmpty) await semanticStore.addChunks(chunks);
  }

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
