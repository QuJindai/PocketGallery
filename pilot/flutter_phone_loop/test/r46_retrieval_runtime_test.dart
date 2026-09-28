import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:pocketgallery_phone_pilot/chat/chat_models.dart';
import 'package:pocketgallery_phone_pilot/core/models.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_models.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_store.dart';
import 'package:pocketgallery_phone_pilot/lineage/runtime_lineage_recorder.dart';
import 'package:pocketgallery_phone_pilot/retrieval/active_vector_index.dart';
import 'package:pocketgallery_phone_pilot/retrieval/query_embedding_runtime.dart';
import 'package:pocketgallery_phone_pilot/retrieval/retrieval_execution_context.dart';
import 'package:pocketgallery_phone_pilot/retrieval/retrieval_runtime.dart';
import 'package:pocketgallery_phone_pilot/services/lexical_fts_store.dart';

class _RecordingGenerator implements EmbeddingGenerator {
  int queryCalls = 0;

  @override
  Future<List<double>> generateQuery(String text) async {
    queryCalls++;
    return <double>[0.2, 0.8];
  }

  @override
  Future<List<double>> generateDocument(String text) async => const <double>[
    0.8,
    0.2,
  ];
}

class _RecordingIndex implements ActiveVectorIndex {
  List<double>? queryVector;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> add(VectorIndexRecord record) async {}

  @override
  Future<void> remove(String embeddingId) async {}

  @override
  Future<List<VectorSearchHit>> searchByEmbedding({
    required List<double> queryEmbedding,
    required int topK,
    required KnowledgeScope scope,
  }) async {
    queryVector = queryEmbedding;
    return const <VectorSearchHit>[
      VectorSearchHit(
        embeddingId: 'emb-body-c2',
        chunkId: 'c2',
        documentId: 'd1',
        similarity: 0.91,
        rank: 1,
      ),
      VectorSearchHit(
        embeddingId: 'emb-body-c1',
        chunkId: 'c1',
        documentId: 'd1',
        similarity: 0.80,
        rank: 2,
      ),
    ];
  }

  @override
  Future<VectorIndexProbe> probe() async => const VectorIndexProbe(
    initialized: true,
    databasePath: 'memory://runtime-test',
    backendId: 'recording-index',
    searchVerified: true,
  );

  @override
  Future<void> close() async {}
}

void main() {
  test(
    'active retrieval executes FTS, one query embedding, vector search, fusion and lineage',
    () async {
      final lexicalDb = sqlite3.openInMemory();
      final lineageDb = sqlite3.openInMemory();
      addTearDown(lexicalDb.close);
      addTearDown(lineageDb.close);
      final lexical = LexicalFtsStore(database: lexicalDb);
      await lexical.replaceDocument(
        const ImportedDocument(
          documentId: 'd1',
          sourceName: 'knowledge.md',
          sha256: 'sha-d1',
          chunks: <PgChunk>[
            PgChunk(
              id: 'c1',
              documentId: 'd1',
              sourceName: 'knowledge.md',
              locator: 'section:1',
              ordinal: 0,
              text: '端侧模型性能测试需要记录真实延迟。',
            ),
            PgChunk(
              id: 'c2',
              documentId: 'd1',
              sourceName: 'knowledge.md',
              locator: 'section:2',
              ordinal: 1,
              text: '向量检索还需要验证召回质量。',
            ),
          ],
        ),
      );

      final store = LineageStore(database: lineageDb);
      final recorder = RuntimeLineageRecorder(store: store);
      final trace = await recorder.startTrace(
        sessionId: 'session-runtime',
        turnId: 'turn-runtime',
        queryText: '端侧模型性能测试',
        requestedMode: 'auto',
        scopeJson: const KnowledgeScope.all().toJson(),
      );
      final generator = _RecordingGenerator();
      final queryRuntime = QueryEmbeddingRuntime(
        generator: generator,
        store: store,
        modelIdentity: 'EmbeddingGemma-test',
      );
      final index = _RecordingIndex();
      final runtime = RetrievalRuntime(
        lexicalStore: lexical,
        queryEmbeddingRuntime: queryRuntime,
        activeVectorIndex: index,
        recorder: recorder,
        embedderReady: () => true,
      );
      final execution = RetrievalExecutionContext(
        traceId: trace.traceId,
        sessionId: 'session-runtime',
        turnId: 'turn-runtime',
        strategyId: RuntimeLineageRecorder.activeStrategyId,
        lane: RetrievalLane.active,
        requestedMode: 'auto',
      );

      final bundle = await runtime.execute(
        '端侧模型性能测试',
        scope: const KnowledgeScope.all(),
        limit: 8,
        execution: execution,
      );
      final persistedQuery = await store.embeddingById(
        bundle.queryEmbeddingId!,
      );

      expect(bundle.lexicalHits, isNotEmpty);
      expect(bundle.semanticHits.map((hit) => hit.chunk.id), <String>[
        'c2',
        'c1',
      ]);
      expect(bundle.hybridHits.first.chunk.id, 'c1');
      expect(
        bundle.hybridHits.first.channels,
        containsAll(<String>['fts5', 'embedding']),
      );
      expect(bundle.relevantForAuto, isTrue);
      expect(bundle.evidence, isNotEmpty);
      expect(generator.queryCalls, 1);
      expect(identical(index.queryVector, bundle.queryEmbeddingVector), isTrue);
      expect(persistedQuery, isNotNull);

      final events = await store.eventsForTrace(trace.traceId);
      expect(
        events.map((event) => event.kind),
        containsAll(<String>[
          'fts.search_completed',
          'embedding.query_completed',
          'vector.search_completed',
          'fusion.completed',
          'candidate.pool_built',
          'router.evaluated',
          'evidence.selected',
        ]),
      );
      final candidates = await store.candidatesForTrace(trace.traceId);
      expect(
        candidates.singleWhere((row) => row.chunkId == 'c1').sourceChannels,
        'embedding,fts5',
      );
      final decision = await store.routerDecisionForTrace(
        trace.traceId,
        execution.strategyId,
        execution.lane,
      );
      expect(decision!.finalUseKnowledge, isTrue);
      expect(decision.decisionReason, 'dual_channel');
      expect(await store.evidenceForTrace(trace.traceId), isNotEmpty);
    },
  );
}
