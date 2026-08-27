import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketgallery_phone_pilot/chat/chat_models.dart';
import 'package:pocketgallery_phone_pilot/core/models.dart';
import 'package:pocketgallery_phone_pilot/services/knowledge_retriever.dart';
import 'package:pocketgallery_phone_pilot/services/lexical_fts_store.dart';
import 'package:pocketgallery_phone_pilot/services/semantic_store.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('R4.0.2 chat picker accepts multiple TXT MD PDF files', () async {
    final importer = await File('lib/services/document_importer.dart').readAsString();

    expect(importer, contains("allowedExtensions: const ['txt', 'md', 'pdf']"));
    expect(importer, contains('allowMultiple: true'));
  });

  test('R4.0.2 chat uploads import into knowledge base and bind current session', () async {
    final chat = await File('lib/ui/chat_page.dart').readAsString();

    expect(chat, contains('Icons.attach_file'));
    expect(chat, contains('_attachFiles'));
    expect(chat, contains('widget.engine.importer.pickDocumentPaths()'));
    expect(chat, contains('widget.engine.importPath(path)'));
    expect(chat, contains('KnowledgeScope.documents'));
    expect(chat, contains('widget.orchestrator.setScope'));
  });

  test('R4.0.2 attachment switches pure-model chat to auto knowledge mode', () async {
    final chat = await File('lib/ui/chat_page.dart').readAsString();

    expect(chat, contains('current.mode == ChatMode.modelOnly'));
    expect(chat, contains('widget.orchestrator.setMode'));
    expect(chat, contains('ChatMode.auto'));
  });

  test('R4.0.2 attachment chips detach from chat without deleting library file', () async {
    final chat = await File('lib/ui/chat_page.dart').readAsString();

    expect(chat, contains('InputChip'));
    expect(chat, contains('_detachDocument'));
    expect(chat, contains('附件已加入知识库'));
    expect(chat, isNot(contains('widget.engine.removeDocument')));
  });

  test('R4.0.2 explicit attachment scope falls back to document evidence on vague prompts', () async {
    final db = sqlite3.openInMemory();
    final lexical = LexicalFtsStore(database: db);
    await lexical.initialize();
    await lexical.replaceDocument(ImportedDocument(
      documentId: 'attached',
      sourceName: 'attached.pdf',
      sha256: 'attached-sha',
      chunks: List.generate(
        4,
        (i) => PgChunk(
          id: 'attached-$i',
          documentId: 'attached',
          sourceName: 'attached.pdf',
          locator: 'p${i + 1}',
          ordinal: i,
          text: 'Unique attached document content section $i about resilient systems.',
        ),
      ),
    ));

    final retriever = KnowledgeRetriever(
      lexicalStore: lexical,
      semanticStore: SemanticStore(lexical),
    );
    final result = await retriever.retrieve(
      '总结一下',
      scope: KnowledgeScope.documents({'attached'}),
      limit: 3,
    );

    expect(result.evidence, isNotEmpty);
    expect(result.relevantForAuto, isTrue);
    expect(
      result.evidence.map((e) => e.chunk.documentId).toSet(),
      equals({'attached'}),
    );
    db.close();
  });
}
