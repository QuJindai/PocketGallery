import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:pocketgallery_phone_pilot/core/evidence.dart';
import 'package:pocketgallery_phone_pilot/core/models.dart';
import 'package:pocketgallery_phone_pilot/services/knowledge_retriever.dart';
import 'package:pocketgallery_phone_pilot/services/lexical_fts_store.dart';

void main() {
  test('long CJK query recalls a semantically aligned phrase through trigram windows',
      () async {
    final db = sqlite3.openInMemory();
    final store = LexicalFtsStore(database: db);
    await store.initialize();
    await store.replaceDocument(const ImportedDocument(
      documentId: 'edge-ai',
      sourceName: '端侧模型性能测试方法.pdf',
      sha256: 'edge',
      chunks: [
        PgChunk(
          id: 'edge-1',
          documentId: 'edge-ai',
          sourceName: '端侧模型性能测试方法.pdf',
          locator: 'page 4',
          ordinal: 0,
          text: '端侧模型性能测试方法包括 TTFT、解码速度、峰值内存、功耗、温控降频和任务基准测试。',
        ),
      ],
    ));

    final result = await store.inspect('端侧模型如何测试');
    expect(result.hits, isNotEmpty);
    expect(result.hits.first.chunk.id, 'edge-1');
    expect(result.diagnostics, contains('CJK trigram-window'));

    store.dispose();
    db.close();
  });

  test('semantic-only auto routing accepts a separated high-confidence winner', () {
    const best = PgChunk(
      id: 'best',
      documentId: 'd1',
      sourceName: 'edge.pdf',
      locator: 'p4',
      ordinal: 0,
      text: '端侧模型性能测试方法',
    );
    const second = PgChunk(
      id: 'second',
      documentId: 'd2',
      sourceName: 'other.pdf',
      locator: 'p2',
      ordinal: 0,
      text: '其他内容',
    );
    const bundle = RetrievalBundle(
      lexicalHits: [],
      semanticHits: [
        RetrievalHit(chunk: best, score: 0.56, channel: 'embedding', rank: 1),
        RetrievalHit(chunk: second, score: 0.50, channel: 'embedding', rank: 2),
      ],
      hybridHits: [
        HybridHit(
          chunk: best,
          score: 0.034,
          channels: {'embedding'},
          lexicalRank: null,
          semanticRank: 1,
        ),
      ],
      evidence: [EvidenceItem(anchor: 'E1', chunk: best, score: 0.034)],
      lexicalOnly: false,
    );

    expect(bundle.relevantForAuto, isTrue);
  });

  test('evidence pack is conservative instead of blindly injecting five chunks', () {
    const chunks = [
      PgChunk(id: 'c1', documentId: 'd1', sourceName: 'a', locator: '1', ordinal: 0, text: 'a'),
      PgChunk(id: 'c2', documentId: 'd1', sourceName: 'a', locator: '2', ordinal: 1, text: 'b'),
      PgChunk(id: 'c3', documentId: 'd2', sourceName: 'b', locator: '1', ordinal: 0, text: 'c'),
      PgChunk(id: 'c4', documentId: 'd3', sourceName: 'c', locator: '1', ordinal: 0, text: 'd'),
      PgChunk(id: 'c5', documentId: 'd4', sourceName: 'd', locator: '1', ordinal: 0, text: 'e'),
    ];
    final hits = [
      HybridHit(chunk: chunks[0], score: 1.00, channels: const {'fts5', 'embedding'}, lexicalRank: 1, semanticRank: 1),
      HybridHit(chunk: chunks[1], score: 0.91, channels: const {'embedding'}, lexicalRank: null, semanticRank: 2),
      HybridHit(chunk: chunks[2], score: 0.69, channels: const {'embedding'}, lexicalRank: null, semanticRank: 3),
      HybridHit(chunk: chunks[3], score: 0.54, channels: const {'embedding'}, lexicalRank: null, semanticRank: 4),
      HybridHit(chunk: chunks[4], score: 0.40, channels: const {'embedding'}, lexicalRank: null, semanticRank: 5),
    ];

    final evidence = const EvidencePackBuilder().build(hits);
    expect(evidence.length, lessThanOrEqualTo(3));
    expect(evidence.map((e) => e.chunk.id), containsAllInOrder(['c1', 'c2']));
    expect(evidence.map((e) => e.chunk.id), isNot(contains('c4')));
    expect(evidence.map((e) => e.chunk.id), isNot(contains('c5')));
  });

  test('R4.5 benchmark expands to phone-realworld Chinese paraphrases', () async {
    final raw = await File('assets/golden/rag_microscope_benchmark.json').readAsString();
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final cases = (json['cases'] as List<dynamic>).cast<Map<String, dynamic>>();

    expect(cases.length, greaterThanOrEqualTo(20));
    expect(cases.any((c) => c['question'] == '端侧模型如何测试'), isTrue);
    expect(
      cases.any((c) => (c['tags'] as List<dynamic>).contains('phone-realworld')),
      isTrue,
    );
  });

  test('Auto retrieval decision is visible in chat instead of only Knowledge ON',
      () async {
    final page = await File('lib/ui/chat_page.dart').readAsString();
    expect(page, contains('Auto → Knowledge'));
    expect(page, contains('Auto → Model'));
  });

  test('R4.5 advances install version for in-place update', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    expect(
      RegExp(r'^version:\s*0\.4\.14\+15\s*$', multiLine: true)
          .hasMatch(pubspec),
      isTrue,
    );
  });
}
