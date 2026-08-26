import '../core/evidence.dart';
import '../core/hybrid_ranker.dart';
import '../core/models.dart';
import 'document_importer.dart';
import 'gemma_service.dart';
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
  }

  final LexicalFtsStore lexicalStore;
  late final SemanticStore semanticStore;
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
    if (oldIds.isNotEmpty) await semanticStore.removeIds(oldIds);
    await lexicalStore.replaceDocument(doc);
    await semanticStore.addChunks(doc.chunks);
    return doc;
  }

  Future<KnowledgeAnswer> ask(String question) async {
    await initialize();
    final lexical = await lexicalStore.search(question);
    final semantic = await semanticStore.search(question);
    final hybrid = ranker.fuse(
      query: question,
      lexical: lexical,
      semantic: semantic,
      limit: 8,
    );
    final evidence = evidenceBuilder.build(hybrid);
    if (evidence.isEmpty) {
      return KnowledgeAnswer(
        answer: '未在本地资料中找到足够证据。',
        evidence: const [],
        citedAnchors: const [],
        lexicalHits: lexical,
        semanticHits: semantic,
        hybridHits: hybrid,
      );
    }
    final answer = await gemma.answer(question: question, evidence: evidence);
    return KnowledgeAnswer(
      answer: answer,
      evidence: evidence,
      citedAnchors: citationResolver.extract(answer, evidence),
      lexicalHits: lexical,
      semanticHits: semantic,
      hybridHits: hybrid,
    );
  }

  Future<void> clearAll() async {
    await initialize();
    await semanticStore.clear();
    await lexicalStore.clear();
  }

  Future<void> close() async {
    await gemma.close();
    lexicalStore.dispose();
  }
}
