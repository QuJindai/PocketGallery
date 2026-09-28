import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:pocketgallery_phone_pilot/chat/chat_models.dart';
import 'package:pocketgallery_phone_pilot/chat/chat_orchestrator.dart';
import 'package:pocketgallery_phone_pilot/chat/chat_session_store.dart';
import 'package:pocketgallery_phone_pilot/core/models.dart';
import 'package:pocketgallery_phone_pilot/lineage/generation_models.dart';
import 'package:pocketgallery_phone_pilot/lineage/import_lineage.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_ids.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_models.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_store.dart';
import 'package:pocketgallery_phone_pilot/lineage/runtime_lineage_recorder.dart';
import 'package:pocketgallery_phone_pilot/retrieval/active_vector_index.dart';
import 'package:pocketgallery_phone_pilot/retrieval/query_embedding_runtime.dart';
import 'package:pocketgallery_phone_pilot/retrieval/retrieval_runtime.dart';
import 'package:pocketgallery_phone_pilot/services/knowledge_retriever.dart';
import 'package:pocketgallery_phone_pilot/services/lexical_fts_store.dart';
import 'package:pocketgallery_phone_pilot/services/semantic_store.dart';

class _Generator implements EmbeddingGenerator {
  @override
  Future<List<double>> generateQuery(String text) async => <double>[0.25, 0.75];

  @override
  Future<List<double>> generateDocument(String text) async => const <double>[
    0.75,
    0.25,
  ];
}

class _Index implements ActiveVectorIndex {
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
  }) async => const <VectorSearchHit>[
    VectorSearchHit(
      embeddingId: 'emb-body-c1',
      chunkId: 'c1',
      documentId: 'd1',
      similarity: 0.88,
      rank: 1,
    ),
  ];

  @override
  Future<VectorIndexProbe> probe() async => const VectorIndexProbe(
    initialized: true,
    databasePath: 'memory://chat-lineage',
    backendId: 'chat-lineage-index',
    searchVerified: true,
  );

  @override
  Future<void> close() async {}
}

class _Model implements ChatModelGateway {
  _Model({this.failure});

  final Object? failure;

  @override
  Future<ChatTurnResult> sendTurn({
    required String sessionId,
    required List<ChatMessage> priorMessages,
    required String userText,
    required List<EvidenceItem> evidence,
    required bool forceKnowledge,
  }) async {
    final error = failure;
    if (error != null) throw error;
    return const ChatTurnResult(
      text: '依据本地资料回答 [E1]',
      evidenceTokenCounts: <String, int>{'E1': 91},
      budget: ContextBudgetDecision(
        modelContextLimit: 8192,
        systemTokens: 120,
        historyTokens: 0,
        evidenceTokens: 240,
        queryTokens: 30,
        outputReserveTokens: 700,
        totalPrefillTokens: 390,
        remainingTokens: 7102,
        trimmedHistoryMessages: 0,
        trimmedEvidenceItems: 0,
        trimDetails: <String>[],
      ),
      generation: GenerationTelemetry(generationMs: 17),
    );
  }

  @override
  Future<void> resetSession(String sessionId) async {}

  @override
  Future<void> close() async {}
}

class _Fixture {
  _Fixture._({
    required this.lexicalDb,
    required this.lineageDb,
    required this.chatDb,
    required this.store,
    required this.recorder,
    required this.orchestrator,
  });

  final Database lexicalDb;
  final Database lineageDb;
  final Database chatDb;
  final LineageStore store;
  final RuntimeLineageRecorder recorder;
  final ChatOrchestrator orchestrator;

  static Future<_Fixture> create({Object? modelFailure}) async {
    final lexicalDb = sqlite3.openInMemory();
    final lineageDb = sqlite3.openInMemory();
    final chatDb = sqlite3.openInMemory();
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
            text: '端侧模型性能测试必须保存真实检索血缘。',
          ),
        ],
      ),
    );
    final lineage = LineageStore(database: lineageDb);
    await lineage.upsertLineageDocument(
      documentId: 'd1',
      sourceName: 'knowledge.md',
      sha256: 'sha-d1',
      fileType: 'md',
      sizeBytes: 120,
      pageCount: 1,
      parseStatus: ParseStatus.parsed.dbValue,
      parseErrorCode: null,
      parseErrorDetail: null,
      extractedCharCount: 22,
      emptyPageCount: 0,
      provenanceQuality: ProvenanceQuality.exact.name,
      importedAt: DateTime.utc(2026, 8, 31),
    );
    await lineage.upsertLineageSection(
      sectionId: 'section-d1-1',
      documentId: 'd1',
      pageNo: 1,
      heading: '性能测试',
      sectionType: 'heading',
      startOffset: 0,
      endOffset: 22,
      charCount: 22,
      parseStatus: ParseStatus.parsed.dbValue,
    );
    await lineage.upsertLineageChunk(
      chunkId: 'c1',
      documentId: 'd1',
      sectionId: 'section-d1-1',
      locator: 'section:1',
      ordinal: 0,
      startOffset: 0,
      endOffset: 22,
      charCount: 22,
      tokenCount: 18,
      overlapFromPrevious: 0,
      chunkStrategy: 'fixed-char-v1',
      boundaryReason: 'document-end',
      provenanceQuality: ProvenanceQuality.exact.name,
    );
    final recorder = RuntimeLineageRecorder(store: lineage);
    final runtime = RetrievalRuntime(
      lexicalStore: lexical,
      queryEmbeddingRuntime: QueryEmbeddingRuntime(
        generator: _Generator(),
        store: lineage,
        modelIdentity: 'EmbeddingGemma-test',
      ),
      activeVectorIndex: _Index(),
      recorder: recorder,
      embedderReady: () => true,
    );
    final retriever = KnowledgeRetriever(
      lexicalStore: lexical,
      semanticStore: SemanticStore(lexical),
      runtime: runtime,
    );
    final chatStore = ChatSessionStore(database: chatDb);
    await chatStore.initialize();
    final orchestrator = ChatOrchestrator(
      store: chatStore,
      retriever: retriever,
      model: _Model(failure: modelFailure),
      lineageRecorder: recorder,
      lineageStore: lineage,
    );
    return _Fixture._(
      lexicalDb: lexicalDb,
      lineageDb: lineageDb,
      chatDb: chatDb,
      store: lineage,
      recorder: recorder,
      orchestrator: orchestrator,
    );
  }

  void close() {
    lexicalDb.close();
    lineageDb.close();
    chatDb.close();
  }
}

void main() {
  test(
    'one Auto knowledge turn persists the complete R4.6 lineage lifecycle',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final session = await fixture.orchestrator.newSession();

      final reply = await fixture.orchestrator.sendMessage(
        session.id,
        '端侧模型性能测试如何保留血缘',
      );
      final messages = await fixture.orchestrator.store.messages(session.id);
      final user = messages.singleWhere(
        (message) => message.role == ChatRole.user,
      );
      final traceId = LineageIds.traceId(session.id, user.id);

      expect(reply.traceId, traceId);
      final trace = await fixture.store.traceById(traceId);
      expect(trace!.status, TraceStatus.complete);
      final events = await fixture.store.eventsForTrace(traceId);
      expect(events.map((event) => event.kind), <String>[
        'trace.started',
        'fts.search_completed',
        'embedding.query_completed',
        'vector.search_completed',
        'fusion.completed',
        'candidate.pool_built',
        'router.evaluated',
        'evidence.selected',
        'context.budgeted',
        'generation.completed',
        'citation.resolved',
        'trace.completed',
      ]);
      expect(await fixture.store.promptBudgetForTrace(traceId), isNotNull);
      final generation = await fixture.store.generationStatsForTrace(traceId);
      expect(generation!.generationMs, 17);
      expect(generation.ttftMs, isNull);
      final evidence = await fixture.store.evidenceForTrace(traceId);
      expect(evidence.single.tokenCount, 91);
      expect(
        evidence.single.selectionReason,
        contains('context_token_allocation'),
      );
      final citations = await fixture.store.citationsForTrace(traceId);
      expect(citations, hasLength(1));
      expect(citations.single.sectionId, 'section-d1-1');
      expect(citations.single.pageNo, 1);
    },
  );

  test(
    'model failure keeps retrieval evidence and marks the same trace failed',
    () async {
      final fixture = await _Fixture.create(
        modelFailure: StateError('model generation failed'),
      );
      addTearDown(fixture.close);
      final session = await fixture.orchestrator.newSession();

      await expectLater(
        fixture.orchestrator.sendMessage(session.id, '端侧模型性能测试如何保留血缘'),
        throwsA(isA<StateError>()),
      );

      final traces = await fixture.store.latestTraces();
      expect(traces, hasLength(1));
      expect(traces.single.status, TraceStatus.failed);
      expect(traces.single.failureStage, 'generation');
      expect(
        await fixture.store.candidatesForTrace(traces.single.traceId),
        isNotEmpty,
      );
      expect(
        await fixture.store.evidenceForTrace(traces.single.traceId),
        isNotEmpty,
      );
      final events = await fixture.store.eventsForTrace(traces.single.traceId);
      expect(events.last.kind, 'trace.failed');
    },
  );

  test(
    'rerunning a trace creates a new real turn with the same query and scope',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final session = await fixture.orchestrator.newSession();
      final firstReply = await fixture.orchestrator.sendMessage(
        session.id,
        '端侧模型性能测试如何保留血缘',
      );
      final original = await fixture.store.traceById(firstReply.traceId!);

      final rerunReply = await fixture.orchestrator.rerunTrace(original!);
      final rerun = await fixture.store.traceById(rerunReply.traceId!);

      expect(rerunReply.traceId, isNot(firstReply.traceId));
      expect(rerun!.queryText, original.queryText);
      expect(rerun.requestedMode, original.requestedMode);
      expect(rerun.scopeJson, original.scopeJson);
      expect(rerun.status, TraceStatus.complete);
    },
  );
}
