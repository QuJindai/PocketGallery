import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pocketgallery_phone_pilot/eval/local_benchmark_store.dart';
import 'package:pocketgallery_phone_pilot/eval/retrieval_benchmark.dart';
import 'package:pocketgallery_phone_pilot/eval/retrieval_evaluator.dart';

void main() {
  test('local real-corpus benchmark cases survive a database restart',
      () async {
    final directory = await Directory.systemTemp.createTemp('pg-benchmark-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/local-benchmark.db';
    final first = LocalBenchmarkStore(databasePath: path);
    await first.initialize();
    await first.putCase(LocalBenchmarkCase(
      id: 'local-1',
      question: '电池安全验证检查什么？',
      expectedDocumentIds: const <String>{'doc-1'},
      expectedChunkIds: const <String>{'chunk-1', 'chunk-2'},
      tags: const <String>{'phone-real', 'safety'},
      sourceTraceId: 'tr-source',
      createdAt: DateTime.utc(2026, 8, 31),
      updatedAt: DateTime.utc(2026, 8, 31, 0, 0, 1),
    ));
    first.dispose();

    final reopened = LocalBenchmarkStore(databasePath: path);
    await reopened.initialize();
    addTearDown(reopened.dispose);
    final rows = await reopened.listCases();

    expect(rows, hasLength(1));
    expect(rows.single.question, '电池安全验证检查什么？');
    expect(rows.single.expectedDocumentIds, {'doc-1'});
    expect(rows.single.expectedChunkIds, {'chunk-1', 'chunk-2'});
    expect(rows.single.tags, {'phone-real', 'safety'});
    expect(rows.single.sourceTraceId, 'tr-source');
    expect(rows.single.toBenchmarkCase().expectedUseKnowledge, isTrue);
  });

  test('a local case requires an explicit expected document or chunk',
      () async {
    final store = LocalBenchmarkStore.inMemory();
    await store.initialize();
    addTearDown(store.dispose);

    await expectLater(
      store.putCase(LocalBenchmarkCase(
        id: 'invalid',
        question: '没有标签',
        expectedDocumentIds: const <String>{},
        expectedChunkIds: const <String>{},
        tags: const <String>{},
        sourceTraceId: 'tr-source',
        createdAt: DateTime.utc(2026, 8, 31),
        updatedAt: DateTime.utc(2026, 8, 31),
      )),
      throwsArgumentError,
    );
  });

  test('router and citation metrics stay unavailable without observations', () {
    const benchmark = RetrievalBenchmarkCase(
      id: 'q-local',
      question: '验证',
      expectedDocumentIds: {'doc-1'},
      expectedSourceNames: {},
      expectedChunkIds: {'chunk-1'},
      expectedUseKnowledge: true,
      tags: {'local'},
    );
    const evaluator = RetrievalEvaluator();

    final unavailable = evaluator.aggregate(const [benchmark], const [
      BenchmarkCaseResult(
        caseId: 'q-local',
        strategy: RetrievalStrategy.hybrid,
        hits: [
          BenchmarkHit(
            chunkId: 'chunk-1',
            documentId: 'doc-1',
            sourceName: 'doc.md',
          ),
        ],
      ),
    ]);
    expect(unavailable!.routerAccuracy, isNull);
    expect(unavailable.citationGroundingRate, isNull);

    final observed = evaluator.aggregate(const [benchmark], const [
      BenchmarkCaseResult(
        caseId: 'q-local',
        strategy: RetrievalStrategy.hybrid,
        hits: [
          BenchmarkHit(
            chunkId: 'chunk-1',
            documentId: 'doc-1',
            sourceName: 'doc.md',
          ),
        ],
        routerUseKnowledge: true,
        citedChunkIds: {'chunk-1'},
      ),
    ]);
    expect(observed!.routerAccuracy, 1);
    expect(observed.citationGroundingRate, 1);
  });
}
