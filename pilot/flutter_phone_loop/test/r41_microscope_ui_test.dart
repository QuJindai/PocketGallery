import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('six approved microscope surfaces exist and are reachable', () async {
    const files = [
      'lib/ui/microscope/retrieval_trace_page.dart',
      'lib/ui/microscope/fts_inspector_page.dart',
      'lib/ui/microscope/vector_microscope_page.dart',
      'lib/ui/microscope/hybrid_rank_lab_page.dart',
      'lib/ui/microscope/chunk_explorer_page.dart',
      'lib/ui/microscope/retrieval_benchmark_page.dart',
    ];
    for (final path in files) {
      expect(await File(path).exists(), isTrue, reason: path);
    }

    final chat = await File('lib/ui/chat_page.dart').readAsString();
    final knowledge = await File('lib/ui/knowledge_page.dart').readAsString();
    expect(chat, contains('检索依据'));
    expect(chat, contains('RetrievalTracePage'));
    expect(knowledge, contains('RAG 显微镜'));
    expect(knowledge, contains('索引健康'));
    expect(knowledge, contains('检索基准'));
  });

  test('microscope visibly distinguishes REAL and DERIVED data', () async {
    final trace = await File(
      'lib/ui/microscope/retrieval_trace_page.dart',
    ).readAsString();
    final fts = await File(
      'lib/ui/microscope/fts_inspector_page.dart',
    ).readAsString();
    final vector = await File(
      'lib/ui/microscope/vector_microscope_page.dart',
    ).readAsString();
    expect('$trace\n$fts\n$vector', contains('REAL'));
    expect('$trace\n$fts\n$vector', contains('DERIVED'));
    expect(vector, contains('UMAP · 未启用'));
    expect(vector, contains('t-SNE · 未启用'));
  });

  test('production microscope UI does not hard-code prototype quality scores', () async {
    final dir = Directory('lib/ui/microscope');
    final files = await dir
        .list(recursive: true)
        .where((e) => e is File && e.path.endsWith('.dart'))
        .cast<File>()
        .toList();
    final source = (await Future.wait(files.map((e) => e.readAsString()))).join('\n');
    for (final forbidden in ['86.7%', '93.3%', '0.625', '8.42']) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });
}
