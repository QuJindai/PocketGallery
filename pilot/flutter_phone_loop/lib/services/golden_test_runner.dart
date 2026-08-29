import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../chat/chat_models.dart';
import '../chat/chat_orchestrator.dart';
import '../chat/chat_session_store.dart';
import '../core/evidence.dart';
import '../core/models.dart';
import '../eval/retrieval_benchmark_fixture.dart';
import '../lineage/lineage_ids.dart';
import '../lineage/lineage_models.dart';
import '../lineage/lineage_store.dart';
import 'gemma_chat_service.dart';
import 'golden_gate_executor.dart';
import 'golden_test_report_store.dart';
import 'golden_test_state.dart';
import 'knowledge_engine.dart';
import 'knowledge_retriever.dart';

class GoldenTestReport {
  GoldenTestReport(this.startedAt, this.results, {this.snapshot});

  factory GoldenTestReport.fromSnapshot(GoldenTestSnapshot snapshot) {
    return GoldenTestReport(
      snapshot.startedAt,
      [
        for (final gate in snapshot.gates)
          GateResult(
            gate.name,
            gate.status == GoldenGateStatus.passed,
            gate.detail,
          ),
      ],
      snapshot: snapshot,
    );
  }

  final DateTime startedAt;
  final List<GateResult> results;
  final GoldenTestSnapshot? snapshot;

  bool get passed =>
      snapshot?.passed ?? results.every((result) => result.passed);

  Map<String, Object?> toJson() => snapshot?.toJson() ?? {
        'startedAt': startedAt.toIso8601String(),
        'passed': passed,
        'results': results.map((result) => result.toJson()).toList(),
      };
}

class GoldenLineageVerifier {
  const GoldenLineageVerifier();

  static const requiredRuntimeEventKinds = <String>{
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
  };

  Future<List<GateResult>> verify(
    LineageStore store,
    String? traceId,
  ) async {
    if (traceId == null || traceId.trim().isEmpty) {
      return const <GateResult>[
        GateResult('F8_RUNTIME_LINEAGE', false, 'traceId 未捕获'),
        GateResult('F9_QUERY_VECTOR_IDENTITY', false, 'traceId 未捕获'),
        GateResult('F10_CONTEXT_BUDGET', false, 'traceId 未捕获'),
      ];
    }

    final trace = await store.traceById(traceId);
    final events = await store.eventsForTrace(traceId);
    final activeEvents = trace == null
        ? const <TraceEventRecord>[]
        : events
            .where(
              (event) =>
                  event.lane == RetrievalLane.active &&
                  event.strategyId == trace.activeStrategyId,
            )
            .toList(growable: false);
    final capturedKinds = activeEvents.map((event) => event.kind).toSet();
    final missingKinds = requiredRuntimeEventKinds.difference(capturedKinds);
    final f8Passed =
        trace?.status == TraceStatus.complete && missingKinds.isEmpty;
    final f8 = GateResult(
      'F8_RUNTIME_LINEAGE',
      f8Passed,
      trace == null
          ? 'trace row 未捕获 · $traceId'
          : 'status=${trace.status.name} · ACTIVE events=${capturedKinds.length} · missing=${missingKinds.isEmpty ? 'none' : missingKinds.join(',')}',
    );

    final queryEmbeddingId = LineageIds.queryEmbeddingId(traceId);
    final embedding = await store.embeddingById(queryEmbeddingId);
    final embeddingEvent = _event(activeEvents, 'embedding.query_completed');
    final vectorEvent = _event(activeEvents, 'vector.search_completed');
    final embeddingPayload = _payload(embeddingEvent);
    final vectorPayload = _payload(vectorEvent);
    var embeddingValid = false;
    if (embedding != null) {
      try {
        embedding.validate();
        embeddingValid =
            embedding.embeddingId == queryEmbeddingId &&
            embedding.sourceKind == 'query' &&
            embedding.sourceId == traceId &&
            embedding.chunkId == null &&
            embedding.representation == EmbeddingRepresentation.query &&
            embedding.modelIdentity.isNotEmpty &&
            embedding.taskMode == 'retrieval_query';
      } catch (_) {
        embeddingValid = false;
      }
    }
    final f9Passed =
        embeddingValid &&
        embeddingPayload['embeddingId'] == queryEmbeddingId &&
        embeddingPayload['modelIdentity'] == embedding?.modelIdentity &&
        embeddingPayload['dimension'] == embedding?.dimension &&
        embeddingPayload['vectorSha256'] == embedding?.vectorSha256 &&
        vectorPayload['queryEmbeddingId'] == queryEmbeddingId;
    final f9 = GateResult(
      'F9_QUERY_VECTOR_IDENTITY',
      f9Passed,
      embedding == null
          ? 'query embedding row 未捕获 · $queryEmbeddingId'
          : 'id=$queryEmbeddingId · dim=${embedding.dimension} · sha=${_short(embedding.vectorSha256)} · vectorEvent=${vectorPayload['queryEmbeddingId'] ?? '未捕获'}',
    );

    final budget = await store.promptBudgetForTrace(traceId);
    final componentSum = budget == null
        ? null
        : budget.systemTokens +
            budget.historyTokens +
            budget.evidenceTokens +
            budget.queryTokens;
    final componentsNonNegative = budget != null &&
        <int>[
          budget.systemTokens,
          budget.historyTokens,
          budget.evidenceTokens,
          budget.queryTokens,
          budget.outputReserveTokens,
          budget.totalPrefillTokens,
          budget.remainingTokens,
        ].every((value) => value >= 0);
    final f10Passed =
        budget != null &&
        budget.lane == RetrievalLane.active &&
        budget.strategyId == trace?.activeStrategyId &&
        budget.modelContextLimit > 0 &&
        componentsNonNegative &&
        componentSum == budget.totalPrefillTokens &&
        budget.totalPrefillTokens + budget.outputReserveTokens <=
            budget.modelContextLimit &&
        budget.remainingTokens ==
            budget.modelContextLimit -
                budget.totalPrefillTokens -
                budget.outputReserveTokens;
    final f10 = GateResult(
      'F10_CONTEXT_BUDGET',
      f10Passed,
      budget == null
          ? 'prompt budget row 未捕获'
          : 'components=$componentSum · prefill=${budget.totalPrefillTokens} · reserve=${budget.outputReserveTokens} · limit=${budget.modelContextLimit} · remaining=${budget.remainingTokens}',
    );

    return <GateResult>[f8, f9, f10];
  }

  TraceEventRecord? _event(
    List<TraceEventRecord> events,
    String kind,
  ) {
    for (final event in events) {
      if (event.kind == kind) return event;
    }
    return null;
  }

  Map<String, dynamic> _payload(TraceEventRecord? event) {
    if (event == null) return const <String, dynamic>{};
    try {
      final decoded = jsonDecode(event.payloadJson);
      return decoded is Map<String, dynamic>
          ? decoded
          : const <String, dynamic>{};
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  String _short(String value) =>
      value.length <= 12 ? value : '${value.substring(0, 12)}…';
}

class GoldenF7Assertion {
  static final RegExp _citationPattern = RegExp(r'\[E\d+\]');

  static GateResult evaluate(
    ChatMessage reply,
    Set<String> validAnchors,
  ) {
    final text = reply.text.trim();
    final rawCitations = _citationPattern
        .allMatches(text)
        .map((match) => match.group(0)!.substring(1, match.group(0)!.length - 1))
        .toSet();
    final sentinel = text.contains('PG_EVIDENCE_LAST_6');
    final citesE6 = rawCitations.contains('E6') &&
        reply.citedAnchors.contains('E6');
    final validCitations = rawCitations.isNotEmpty &&
        rawCitations.every(validAnchors.contains) &&
        reply.citedAnchors.every(validAnchors.contains);
    final knowledgeMode = reply.retrievalMode?.startsWith('knowledge:') ?? false;
    final passed = text.isNotEmpty &&
        sentinel &&
        citesE6 &&
        validCitations &&
        knowledgeMode;
    return GateResult(
      'F7_CHAT_REALWORLD',
      passed,
      'sentinel=$sentinel citesE6=$citesE6 '
      'validCitations=$validCitations knowledgeMode=$knowledgeMode '
      'citations=${rawCitations.toList()..sort()} '
      'reply=${_compact(text, 180)}',
    );
  }
}

class GoldenTestRunner {
  GoldenTestRunner(
    this.engine, {
    GoldenGateExecutor? executor,
    GoldenTestReportStore? reportStore,
  })  : _executor = executor ?? GoldenGateExecutor(),
        _reportStore = reportStore ?? GoldenTestReportStore();

  final KnowledgeEngine engine;
  final GoldenGateExecutor _executor;
  final GoldenTestReportStore _reportStore;

  Future<GoldenTestReport> run({GoldenProgressCallback? onProgress}) async {
    final context = _GoldenRunContext(engine);
    final snapshot = await _executor.execute(
      runId: 'phone-${DateTime.now().toUtc().microsecondsSinceEpoch}',
      gates: [
        GoldenGateSpec(
          name: 'F1_IMPORT_CHUNK',
          label: '导入并切分临时语料',
          timeout: const Duration(seconds: 45),
          run: context.runF1,
        ),
        GoldenGateSpec(
          name: 'F2_FTS5',
          label: 'FTS5 精确召回',
          timeout: const Duration(seconds: 30),
          blockedWhen: _f1DidNotPass,
          blockedReason: 'F1 fixture preparation did not pass',
          run: context.runF2,
        ),
        GoldenGateSpec(
          name: 'F3_EMBEDDING',
          label: 'Embedding 语义召回',
          timeout: const Duration(seconds: 90),
          blockedWhen: _f1DidNotPass,
          blockedReason: 'F1 fixture preparation did not pass',
          run: context.runF3,
        ),
        GoldenGateSpec(
          name: 'F4_HYBRID_RERANK',
          label: 'Hybrid / Rerank',
          timeout: const Duration(seconds: 90),
          blockedWhen: _f1DidNotPass,
          blockedReason: 'F1 fixture preparation did not pass',
          run: context.runF4,
        ),
        GoldenGateSpec(
          name: 'F5_EVIDENCE',
          label: '证据包与锚点',
          timeout: const Duration(seconds: 20),
          blockedWhen: _f1DidNotPass,
          blockedReason: 'F1 fixture preparation did not pass',
          run: context.runF5,
        ),
        GoldenGateSpec(
          name: 'F6_GEMMA_CITATION',
          label: '真实 Gemma 引用回答',
          timeout: const Duration(seconds: 240),
          blockedWhen: _f1DidNotPass,
          blockedReason: 'F1 fixture preparation did not pass',
          run: context.runF6,
        ),
        GoldenGateSpec(
          name: 'F7_CHAT_REALWORLD',
          label: '重证据连续第二轮',
          timeout: const Duration(seconds: 240),
          blockedWhen: (snapshot) =>
              _f1DidNotPass(snapshot) ||
              snapshot.gate('F6_GEMMA_CITATION')?.status !=
                  GoldenGateStatus.passed,
          blockedReason: 'F1 or F6 did not pass',
          run: context.runF7,
        ),
        GoldenGateSpec(
          name: 'F8_RUNTIME_LINEAGE',
          label: 'ACTIVE 运行时血缘闭环',
          timeout: const Duration(seconds: 10),
          blockedWhen: _f6DidNotPass,
          blockedReason: 'F6 lineage source did not pass',
          run: context.runF8,
        ),
        GoldenGateSpec(
          name: 'F9_QUERY_VECTOR_IDENTITY',
          label: '查询向量身份一致性',
          timeout: const Duration(seconds: 10),
          blockedWhen: _f6DidNotPass,
          blockedReason: 'F6 lineage source did not pass',
          run: context.runF9,
        ),
        GoldenGateSpec(
          name: 'F10_CONTEXT_BUDGET',
          label: '上下文预算守恒',
          timeout: const Duration(seconds: 10),
          blockedWhen: _f6DidNotPass,
          blockedReason: 'F6 lineage source did not pass',
          run: context.runF10,
        ),
      ],
      onProgress: onProgress,
      onCheckpoint: (snapshot) async {
        await _reportStore.save(snapshot);
      },
      onGateTimeout: context.onGateTimeout,
      cleanup: context.cleanup,
    );
    return GoldenTestReport.fromSnapshot(snapshot);
  }

  static bool _f1DidNotPass(GoldenTestSnapshot snapshot) =>
      snapshot.gate('F1_IMPORT_CHUNK')?.status != GoldenGateStatus.passed;

  static bool _f6DidNotPass(GoldenTestSnapshot snapshot) =>
      snapshot.gate('F6_GEMMA_CITATION')?.status !=
      GoldenGateStatus.passed;
}

class _GoldenRunContext {
  _GoldenRunContext(this.engine);

  final KnowledgeEngine engine;
  RetrievalBenchmarkLease? fixture;
  GemmaChatService? chatModel;
  ChatSessionStore? chatStore;
  ChatSession? chatSession;
  Database? chatDatabase;
  String? lineageTraceId;
  Future<List<GateResult>>? lineageVerification;
  bool f1TimedOut = false;

  Future<GateResult> runF1() async {
    try {
      fixture = await RetrievalBenchmarkFixture.prepare(
        engine,
        resetKnownFixtures: true,
      );
      final documents = await engine.listDocuments();
      final bySource = {
        for (final document in documents) document.sourceName: document,
      };
      final chunkCounts = <int>[];
      for (final sourceName in const [
        'pg_golden_calibration.txt',
        'pg_golden_robot.txt',
        'pg_golden_network.txt',
      ]) {
        final document = bySource[sourceName];
        final chunks = document == null
            ? const <PgChunk>[]
            : await engine.lexicalStore.chunksForDocument(document.documentId);
        chunkCounts.add(chunks.length);
      }
      return GateResult(
        'F1_IMPORT_CHUNK',
        chunkCounts.every((count) => count > 0),
        'chunks=${chunkCounts.fold<int>(0, (sum, count) => sum + count)} '
        'perSource=$chunkCounts',
      );
    } finally {
      if (f1TimedOut) {
        await fixture?.cleanup();
        await RetrievalBenchmarkFixture.removeKnownFixtures(engine);
      }
    }
  }

  Future<GateResult> runF2() async {
    final hits = await engine.lexicalStore.search('31 03 51 01');
    return GateResult(
      'F2_FTS5',
      hits.isNotEmpty &&
          hits.first.chunk.sourceName == 'pg_golden_calibration.txt',
      hits.isEmpty ? 'no hit' : 'top1=${hits.first.chunk.sourceName}',
    );
  }

  Future<GateResult> runF3() async {
    final hits =
        await engine.semanticStore.search('为什么诊断程序一直等不到标定完成状态');
    return GateResult(
      'F3_EMBEDDING',
      hits.isNotEmpty &&
          hits.first.chunk.sourceName == 'pg_golden_calibration.txt',
      hits.isEmpty
          ? 'no hit'
          : 'top1=${hits.first.chunk.sourceName} '
              'score=${hits.first.score.toStringAsFixed(3)}',
    );
  }

  Future<List<HybridHit>> _hybridHits() async {
    const query = '31 03 51 01 为什么 DSA 一直等待';
    return engine.ranker.fuse(
      query: query,
      lexical: await engine.lexicalStore.search(query),
      semantic: await engine.semanticStore.search(query),
    );
  }

  Future<GateResult> runF4() async {
    final hits = await _hybridHits();
    return GateResult(
      'F4_HYBRID_RERANK',
      hits.isNotEmpty &&
          hits.first.chunk.sourceName == 'pg_golden_calibration.txt',
      hits.isEmpty
          ? 'no hit'
          : 'top1=${hits.first.chunk.sourceName} '
              'channels=${hits.first.channels.join("+")}',
    );
  }

  Future<GateResult> runF5() async {
    final evidence = const EvidencePackBuilder().build(await _hybridHits());
    return GateResult(
      'F5_EVIDENCE',
      evidence.isNotEmpty &&
          evidence.first.chunk.sourceName == 'pg_golden_calibration.txt' &&
          evidence.first.anchor == 'E1',
      evidence.isEmpty
          ? 'no evidence'
          : '${evidence.first.anchor}=${evidence.first.chunk.sourceName}',
    );
  }

  Future<GateResult> runF6() async {
    chatDatabase = sqlite3.openInMemory();
    chatStore = ChatSessionStore(database: chatDatabase);
    await chatStore!.initialize();
    chatModel = GemmaChatService();
    final orchestrator = ChatOrchestrator(
      store: chatStore!,
      retriever: engine.retriever,
      model: chatModel!,
      lineageRecorder: engine.runtimeLineageRecorder,
      lineageStore: engine.lineageStore,
    );
    var session = await orchestrator.newSession(title: 'Golden real chat');
    session = await orchestrator.setMode(session.id, ChatMode.knowledge);
    chatSession = session;
    final reply = await orchestrator.sendMessage(
      session.id,
      '请解释 31 03 51 01 获取标定结果时为什么 DSA 可能持续等待；回答中必须保留 31 03 51 01 并引用本轮证据。',
    );
    lineageTraceId = reply.traceId;
    final passed = reply.text.contains('31 03 51 01') &&
        (reply.text.contains('等待') || reply.text.contains('处理中')) &&
        reply.citedAnchors.isNotEmpty &&
        (reply.retrievalMode?.startsWith('knowledge:') ?? false);
    return GateResult(
      'F6_GEMMA_CITATION',
      passed,
      'citations=${reply.citedAnchors} mode=${reply.retrievalMode} '
      'reply=${_compact(reply.text, 220)}',
    );
  }

  Future<GateResult> runF7() async {
    final store = chatStore;
    final model = chatModel;
    final session = chatSession;
    if (store == null || model == null || session == null) {
      throw StateError('F6 chat session is unavailable');
    }
    final orchestrator = ChatOrchestrator(
      store: store,
      retriever: const _GoldenHeavyEvidenceRetriever(),
      model: model,
    );
    final reply = await orchestrator.sendMessage(
      session.id,
      '请只回答本轮证据中编号最大的那条证据正文开头的标记，并引用该条证据；不要回答其他内容。',
    );
    final validAnchors = reply.evidence
        .map((evidence) => evidence.anchor)
        .toSet();
    return GoldenF7Assertion.evaluate(reply, validAnchors);
  }

  Future<GateResult> runF8() => _lineageGate(0);

  Future<GateResult> runF9() => _lineageGate(1);

  Future<GateResult> runF10() => _lineageGate(2);

  Future<GateResult> _lineageGate(int index) async {
    final verification = lineageVerification ??=
        const GoldenLineageVerifier().verify(
      engine.lineageStore,
      lineageTraceId,
    );
    final gates = await verification;
    return gates[index];
  }

  Future<void> onGateTimeout(GoldenGateSnapshot gate) async {
    if (gate.name == 'F1_IMPORT_CHUNK') {
      f1TimedOut = true;
      await RetrievalBenchmarkFixture.removeKnownFixtures(engine);
    }
    if (gate.name == 'F6_GEMMA_CITATION' ||
        gate.name == 'F7_CHAT_REALWORLD') {
      await chatModel?.close();
    }
  }

  Future<void> cleanup() async {
    final errors = <Object>[];
    try {
      await chatModel?.close();
    } catch (error) {
      errors.add(error);
    }
    try {
      chatDatabase?.close();
    } catch (error) {
      errors.add(error);
    }
    try {
      await fixture?.cleanup();
    } catch (error) {
      errors.add(error);
    }
    try {
      await RetrievalBenchmarkFixture.removeKnownFixtures(engine);
    } catch (error) {
      errors.add(error);
    }
    if (errors.isNotEmpty) {
      throw StateError('Golden cleanup failed: ${errors.join(" | ")}');
    }
  }
}

class _GoldenHeavyEvidenceRetriever implements KnowledgeRetrievalGateway {
  const _GoldenHeavyEvidenceRetriever();

  @override
  Future<RetrievalBundle> retrieve(
    String query, {
    KnowledgeScope scope = const KnowledgeScope.all(),
    int limit = 8,
    RetrievalExecutionContext? execution,
  }) async {
    final chunks = List<PgChunk>.generate(6, (index) {
      final number = index + 1;
      final marker = number == 6
          ? 'PG_EVIDENCE_LAST_6'
          : 'PG_EVIDENCE_ITEM_$number';
      return PgChunk(
        id: 'golden-heavy-$number',
        documentId: 'golden-heavy-doc-$number',
        sourceName: 'pg_golden_heavy_$number.txt',
        locator: 'chunk#$number',
        ordinal: 0,
        text: '$marker。第$number条上下文证据。'
            '${'制造现场诊断与模型上下文预算验证内容。' * 120}',
      );
    }, growable: false);
    final lexical = <RetrievalHit>[
      for (var index = 0; index < chunks.length; index += 1)
        RetrievalHit(
          chunk: chunks[index],
          score: 1.0 - index * 0.05,
          channel: 'fts5',
          rank: index + 1,
        ),
    ];
    final hybrid = <HybridHit>[
      for (var index = 0; index < chunks.length; index += 1)
        HybridHit(
          chunk: chunks[index],
          score: 1.0 / (index + 1),
          channels: const {'fts5'},
          lexicalRank: index + 1,
          semanticRank: null,
        ),
    ];
    return RetrievalBundle(
      lexicalHits: lexical,
      semanticHits: const [],
      hybridHits: hybrid,
      evidence: [
        for (var index = 0; index < chunks.length; index += 1)
          EvidenceItem(
            anchor: 'E${index + 1}',
            chunk: chunks[index],
            score: hybrid[index].score,
          ),
      ],
      lexicalOnly: true,
    );
  }
}

String _compact(String text, int maxCharacters) {
  final compact = text.replaceAll('\n', ' ').trim();
  if (compact.length <= maxCharacters) return compact;
  return compact.substring(0, maxCharacters);
}
