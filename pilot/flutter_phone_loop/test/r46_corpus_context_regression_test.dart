import 'dart:io';

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

    final context = budgeter.composeEvidenceContext(
      evidence,
      maxTokens: ContextBudgeter.evidenceReserveMax,
      maxItems: 8,
    );

    for (var i = 0; i < 6; i++) {
      expect(context, contains('[E${i + 1}]'));
      expect(context, contains('document-$i.md'));
    }
    expect(
      budgeter.estimateTokens(context),
      lessThanOrEqualTo(ContextBudgeter.evidenceReserveMax),
    );
  });

  test('long metadata cannot evict later anchors or exceed a tight budget', () {
    const budgeter = ContextBudgeter();
    const maxTokens = 240;
    final evidence = [
      for (var i = 0; i < 6; i++)
        EvidenceItem(
          anchor: 'E${i + 1}',
          chunk: PgChunk(
            id: 'chunk-$i-${List.filled(1500, 'c').join()}-$i',
            documentId: 'document-$i',
            sourceName: 'document-$i-${List.filled(1500, 's').join()}-$i.md',
            locator: 'section-$i-${List.filled(1500, 'l').join()}-$i',
            ordinal: 0,
            text: List.filled(900, '第$i份资料内容').join(),
          ),
          score: 1 / (i + 1),
        ),
    ];

    final context = budgeter.composeEvidenceContext(
      evidence,
      maxTokens: maxTokens,
      maxItems: 8,
    );

    for (var i = 0; i < 6; i++) {
      expect(context, contains('[E${i + 1}]'));
      expect(context, contains('source="document-$i-'));
    }
    expect(budgeter.estimateTokens(context), lessThanOrEqualTo(maxTokens));
  });

  test('truncation marker is included inside the requested token budget', () {
    const budgeter = ContextBudgeter();
    const maxTokens = 24;

    final trimmed = budgeter.trimTextToTokenBudget(
      List.filled(1000, 'abcdef').join(),
      maxTokens,
    );

    expect(trimmed, contains('[context budget truncated]'));
    expect(budgeter.estimateTokens(trimmed), lessThanOrEqualTo(maxTokens));
  });

  test('R4.6 advances the in-place update build number beyond R4.5', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    final match = RegExp(
      r'^version:\s*0\.4\.\d+\+(\d+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(match, isNotNull);
    expect(int.parse(match!.group(1)!), greaterThanOrEqualTo(16));
  });
}
