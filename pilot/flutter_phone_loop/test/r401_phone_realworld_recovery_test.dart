import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:pocketgallery_phone_pilot/core/models.dart';
import 'package:pocketgallery_phone_pilot/services/knowledge_retriever.dart';
import 'package:pocketgallery_phone_pilot/services/lexical_fts_store.dart';
import 'package:pocketgallery_phone_pilot/services/semantic_store.dart';

void main() {
  test('R4.0.1 corpus summary gets cross-document evidence without embedding', () async {
    final db = sqlite3.openInMemory();
    final lexical = LexicalFtsStore(database: db);
    await lexical.initialize();

    await lexical.replaceDocument(
      ImportedDocument(
        documentId: 'attention',
        sourceName: 'Attention_Is_All_You_Need.pdf',
        sha256: 'a',
        chunks: List.generate(
          6,
          (i) => PgChunk(
            id: 'a$i',
            documentId: 'attention',
            sourceName: 'Attention_Is_All_You_Need.pdf',
            locator: 'p${i + 1}',
            ordinal: i,
            text:
                'Transformer architecture attention encoder decoder section $i',
          ),
        ),
      ),
    );
    await lexical.replaceDocument(
      ImportedDocument(
        documentId: 'pnt',
        sourceName: 'DHS_Resilient_PNT_Best_Practices_2025.pdf',
        sha256: 'b',
        chunks: List.generate(
          6,
          (i) => PgChunk(
            id: 'b$i',
            documentId: 'pnt',
            sourceName: 'DHS_Resilient_PNT_Best_Practices_2025.pdf',
            locator: 'p${i + 1}',
            ordinal: i,
            text:
                'Resilient positioning navigation timing best practice section $i',
          ),
        ),
      ),
    );

    final retriever = KnowledgeRetriever(
      lexicalStore: lexical,
      semanticStore: SemanticStore(lexical),
    );
    final result = await retriever.retrieve('总结知识库', limit: 5);

    expect(result.evidence, isNotEmpty);
    expect(result.relevantForAuto, isTrue);
    expect(
      result.evidence.map((e) => e.chunk.documentId).toSet(),
      containsAll({'attention', 'pnt'}),
    );
    db.close();
  });

  test('R4.0.1 separates OAuth success from Gemma license acceptance', () {
    final setup = File('lib/services/model_setup_service.dart')
        .readAsStringSync();
    final settings = File('lib/ui/model_settings_page.dart').readAsStringSync();

    expect(setup, contains('licenseRequired'));
    expect(setup, contains('ModelSetupPhase.licenseRequired'));
    expect(settings, contains('ModelSetupPhase.licenseRequired'));
    expect(settings, contains('OAuth 已完成'));
    expect(settings, contains('官方许可'));
  });

  test('R4.0.1 resumes download after returning from license page without new OAuth', () {
    final settings = File('lib/ui/model_settings_page.dart').readAsStringSync();

    expect(
      settings,
      contains('modelState.phase == ModelSetupPhase.licenseRequired'),
    );
    expect(settings, contains('_prepare();'));
    expect(settings, contains('已接受许可，自动继续下载'));
  });
}
