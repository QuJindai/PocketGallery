import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/release_version.dart';

void main() {
  test('missing-vector repair filters existing observations before embedding', () async {
    final engine = await File('lib/services/knowledge_engine.dart').readAsString();

    expect(engine, contains('syncMissingSemanticIndex'));
    expect(engine, contains('observationStore.listAll'));
    expect(engine, contains('pendingChunks'));
    expect(engine, contains('SemanticStore.embeddingModelIdentity'));
    expect(engine, contains('onProgress'));
  });

  test('Chunk Explorer exposes real repair progress instead of a frozen label', () async {
    final page = await File(
      'lib/ui/microscope/chunk_explorer_page.dart',
    ).readAsString();

    expect(page, contains('SemanticSyncProgress'));
    expect(page, contains('repairProgress'));
    expect(page, contains(r'补建 ${p.completed}/${p.total}'));
    expect(page, contains('p.percent'));
    expect(page, contains('p.currentSource'));
  });

  test('repair remains resumable and does not clear healthy vectors', () async {
    final engine = await File('lib/services/knowledge_engine.dart').readAsString();

    final syncStart = engine.indexOf('syncMissingSemanticIndex');
    final syncEnd = engine.indexOf('Future<void> syncSemanticIndex', syncStart);
    expect(syncStart, greaterThanOrEqualTo(0));
    expect(syncEnd, greaterThan(syncStart));
    final syncBody = engine.substring(syncStart, syncEnd);
    expect(syncBody, isNot(contains('semanticStore.clear()')));
    expect(syncBody, contains('semanticStore.addChunks(pendingChunks'));
  });

  test('document deletion cannot leave reserved Golden documents in lexical DB', () async {
    final engine = await File('lib/services/knowledge_engine.dart').readAsString();
    final fixture = await File(
      'lib/eval/retrieval_benchmark_fixture.dart',
    ).readAsString();

    expect(engine, contains('lexicalStore.removeDocument(documentId)'));
    expect(engine, contains('finally'));
    expect(engine, contains('removeChunkIds(ids)'));
    expect(fixture, contains('cleanupReservedGoldenDocuments'));
  });

  test('R4.4+ keeps a monotonic install version for in-place update', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    final version = parseReleaseVersion(pubspec);
    expect(
      isReleaseVersionAtLeast(version, major: 0, minor: 4, patch: 0),
      isTrue,
    );
    expect(version.build, greaterThanOrEqualTo(14));
  });
}
