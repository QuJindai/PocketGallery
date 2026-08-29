import 'package:flutter_test/flutter_test.dart';
import 'package:pocketgallery_phone_pilot/chat/context_budgeter.dart';
import 'package:pocketgallery_phone_pilot/core/models.dart';
import 'package:pocketgallery_phone_pilot/services/knowledge_retriever.dart';
import 'package:pocketgallery_phone_pilot/services/lexical_fts_store.dart';
import 'package:pocketgallery_phone_pilot/services/semantic_store.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('corpus summary preserves one evidence item for each of six documents',
      () async {
    final db = sqlite3.openInMemory();
    final lexical = LexicalFtsStore(database: db);
    await lexical.initialize();

    for (var i = 0; i < 6; i++) {
      await lexical.replaceDocument(ImportedDocument(
        documentId: 'document-$i',
        sourceName: 'document-$i.md',
        sha256: 'sha-$i',
        chunks: [
          PgChunk(
            id: 'chunk-$i',
            documentId: 'document-$i',
            sourceName: 'document-$i.md',
            locator: 'section 1',
            ordinal: 0,
            text: '第 $i 份资料的独立主题与事实。',
          ),
        ],
      ));
    }

    final retriever = KnowledgeRetriever(
      lexicalStore: lexical,
      semanticStore: SemanticStore(lexical),
    );
    final result = await retriever.retrieve('总结知识库', limit: 8);

    expect(result.evidence, hasLength(6));
    expect(
      result.evidence.map((item) => item.chunk.documentId).toSet(),
      {
        'document-0',
        'document-1',
        'document-2',
        'document-3',
        'document-4',
        'document-5',
      },
    );

    db.close();
  });

  test('bounded evidence context keeps all six source identities', () {
    const budgeter = ContextBudgeter();
    final evidence = [
      for (var i = 0; i < 6; i++)
        EvidenceItem(
          anchor: 'E${i + 1}',
          chunk: PgChunk(
            id: 'chunk-$i',
            documentId: 'document-$i',
            sourceName: 'document-$i.md',
            locator: 'section 1',
            ordinal: 0,
            text: List.filled(900, '第$i份资料内容').join(),
          ),
          score: 1 / (i + 1),
        ),
    ];

    String context;
    try {
      context = (budgeter as dynamic).composeEvidenceContext(
        evidence,
        maxTokens: ContextBudgeter.evidenceReserveMax,
        maxItems: 8,
      ) as String;
    } catch (error) {
      fail('ContextBudgeter must compose a bounded, document-balanced context: '
          '$error');
    }

    for (var i = 0; i < 6; i++) {
      expect(context, contains('[E${i + 1}]'));
      expect(context, contains('document-$i.md'));
    }
    expect(
      budgeter.estimateTokens(context),
      lessThanOrEqualTo(ContextBudgeter.evidenceReserveMax),
    );
  });
}
