import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:pocketgallery_phone_pilot/chat/chat_models.dart';
import 'package:pocketgallery_phone_pilot/core/models.dart';
import 'package:pocketgallery_phone_pilot/services/lexical_fts_store.dart';

void main() {
  late Database db;
  late LexicalFtsStore store;

  setUp(() async {
    db = sqlite3.openInMemory();
    store = LexicalFtsStore(database: db);
    await store.initialize();
    await store.replaceDocument(ImportedDocument(
      documentId: 'd1',
      sourceName: 'cn.md',
      sha256: 'a',
      chunks: const [
        PgChunk(
          id: 'c1',
          documentId: 'd1',
          sourceName: 'cn.md',
          locator: 'p.1',
          ordinal: 0,
          text: '大模型在端侧运行时需要管理模型缓存和向量索引。',
        ),
        PgChunk(
          id: 'c2',
          documentId: 'd1',
          sourceName: 'cn.md',
          locator: 'p.2',
          ordinal: 1,
          text: '发送 31 03 51 01 后诊断程序等待最终标定结果。',
        ),
      ],
    ));
  });

  tearDown(() {
    store.dispose();
    db.dispose();
  });

  test('two-character CJK remains searchable and inspector labels fallback', () async {
    final result = await store.inspect('模型');
    expect(result.hits, isNotEmpty);
    expect(result.hits.first.chunk.id, 'c1');
    expect(result.hits.first.matchMode, 'cjk-short-exact');
    expect(result.hits.first.rawBm25, isNull);
    expect(result.hits.first.snippet, contains('模型'));
    expect(result.diagnostics, contains('2-char CJK fallback'));

    final regular = await store.search('模型');
    expect(regular.first.chunk.id, 'c1');
  });

  test('FTS inspector exposes REAL bm25 and highlighted snippet', () async {
    final result = await store.inspect('31 03 51 01');
    expect(result.hits, isNotEmpty);
    final hit = result.hits.first;
    expect(hit.chunk.id, 'c2');
    expect(hit.matchMode, 'fts5-trigram');
    expect(hit.rawBm25, isNotNull);
    expect(hit.affinity, greaterThan(0));
    expect(hit.snippet, anyOf(contains('<mark>31'), contains('31')));
    expect(hit.rank, 1);
  });

  test('scope is honored by inspector', () async {
    final result = await store.inspect(
      '模型',
      scope: const KnowledgeScope.documents({'missing'}),
    );
    expect(result.hits, isEmpty);
  });
}
