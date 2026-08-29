import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
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
import 'knowledge_engine.dart';
import 'knowledge_retriever.dart';

class GoldenTestReport {
  GoldenTestReport(this.startedAt, this.results);
  final DateTime startedAt;
  final List<GateResult> results;

  bool get passed => results.every((r) => r.passed);

  Map<String, Object> toJson() => {
        'startedAt': startedAt.toIso8601String(),
        'passed': passed,
        'results': results.map((e) => e.toJson()).toList(),
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

class GoldenTestRunner {
  GoldenTestRunner(this.engine);
  final KnowledgeEngine engine;

  Future<GoldenTestReport> run() async {
    final results = <GateResult>[];
    final started = DateTime.now();
    RetrievalBenchmarkLease? fixture;
    GemmaChatService? chatModel;
    Database? chatDb;

    try {
      // Remove stale diagnostics left by older builds, then install a fresh
      // deterministic corpus. The lease is always cleaned in finally so Phone
      // Golden Test never permanently alters the user's knowledge library.
      fixture = await RetrievalBenchmarkFixture.prepare(
        engine,
        resetKnownFixtures: true,
      );

      final docs = await engine.listDocuments();
      final bySource = {for (final doc in docs) doc.sourceName: doc};
      final a = bySource['pg_golden_calibration.txt'];
      final b = bySource['pg_golden_robot.txt'];
      final c = bySource['pg_golden_network.txt'];
      final aChunks = a == null
          ? const <PgChunk>[]
          : await engine.lexicalStore.chunksForDocument(a.documentId);
      final bChunks = b == null
          ? const <PgChunk>[]
          : await engine.lexicalStore.chunksForDocument(b.documentId);
      final cChunks = c == null
          ? const <PgChunk>[]
          : await engine.lexicalStore.chunksForDocument(c.documentId);
      results.add(GateResult(
        'F1_IMPORT_CHUNK',
        aChunks.isNotEmpty && bChunks.isNotEmpty && cChunks.isNotEmpty,
        'chunks=${aChunks.length + bChunks.length + cChunks.length}',
      ));

      final fts = await engine.lexicalStore.search('31 03 51 01');
      results.add(GateResult(
        'F2_FTS5',
        fts.isNotEmpty &&
            fts.first.chunk.sourceName == 'pg_golden_calibration.txt',
        fts.isEmpty ? 'no hit' : 'top1=${fts.first.chunk.sourceName}',
      ));

      final sem =
          await engine.semanticStore.search('为什么诊断程序一直等不到标定完成状态');
      results.add(GateResult(
        'F3_EMBEDDING',
        sem.isNotEmpty &&
            sem.first.chunk.sourceName == 'pg_golden_calibration.txt',
        sem.isEmpty
            ? 'no hit'
            : 'top1=${sem.first.chunk.sourceName} score=${sem.first.score.toStringAsFixed(3)}',
      ));

      final hybrid = engine.ranker.fuse(
        query: '31 03 51 01 为什么 DSA 一直等待',
        lexical: await engine.lexicalStore.search('31 03 51 01 为什么 DSA 一直等待'),
        semantic: await engine.semanticStore.search('31 03 51 01 为什么 DSA 一直等待'),
      );
      results.add(GateResult(
        'F4_HYBRID_RERANK',
        hybrid.isNotEmpty &&
            hybrid.first.chunk.sourceName == 'pg_golden_calibration.txt',
        hybrid.isEmpty
            ? 'no hit'
            : 'top1=${hybrid.first.chunk.sourceName} channels=${hybrid.first.channels.join("+")}',
      ));

      final evidence = const EvidencePackBuilder().build(hybrid);
      results.add(GateResult(
        'F5_EVIDENCE',
        evidence.isNotEmpty &&
            evidence.first.chunk.sourceName == 'pg_golden_calibration.txt' &&
            evidence.first.anchor == 'E1',
        evidence.isEmpty
            ? 'no evidence'
            : '${evidence.first.anchor}=${evidence.first.chunk.sourceName}',
      ));

      // F6 now uses the same path as the Chat tab instead of the old one-shot
      // GemmaService helper. This prevents a green diagnostic while real chat
      // is broken.
      chatDb = sqlite3.openInMemory();
      final chatStore = ChatSessionStore(database: chatDb);
      await chatStore.initialize();
      chatModel = GemmaChatService();
      final orchestrator = ChatOrchestrator(
        store: chatStore,
        retriever: engine.retriever,
        model: chatModel,
        lineageRecorder: engine.runtimeLineageRecorder,
        lineageStore: engine.lineageStore,
      );
      var session = await orchestrator.newSession(title: 'Golden real chat');
      session = await orchestrator.setMode(session.id, ChatMode.knowledge);
      final reply = await orchestrator.sendMessage(
        session.id,
        '请解释 31 03 51 01 获取标定结果时为什么 DSA 可能持续等待；回答中必须保留 31 03 51 01。',
      );
      final answerOk = reply.text.contains('31 03 51 01') &&
          (reply.text.contains('等待') || reply.text.contains('处理中')) &&
          reply.citedAnchors.isNotEmpty;
      results.add(GateResult(
        'F6_GEMMA_CITATION',
        answerOk,
        reply.text.replaceAll('\n', ' ').substring(
              0,
              reply.text.length > 220 ? 220 : reply.text.length,
            ),
      ));

      // Reuse the SAME logical session with a deliberately large evidence pack.
      // Older code retained the native chat indefinitely, so accumulated state
      // plus this prefill could exceed remaining entries and poison the cached
      // session. R4.3 must bound the evidence/history and build a fresh native
      // chat for the turn.
      final heavyOrchestrator = ChatOrchestrator(
        store: chatStore,
        retriever: const _GoldenHeavyEvidenceRetriever(),
        model: chatModel,
      );
      final heavyReply = await heavyOrchestrator.sendMessage(
        session.id,
        '请基于本轮证据用一句话说明上下文预算是否正常，并引用证据。',
      );
      results.add(GateResult(
        'F7_CHAT_REALWORLD',
        heavyReply.text.trim().isNotEmpty,
        'second-turn=${heavyReply.text.replaceAll('\n', ' ').substring(0, heavyReply.text.length > 160 ? 160 : heavyReply.text.length)}',
      ));
      results.addAll(
        await const GoldenLineageVerifier().verify(
          engine.lineageStore,
          reply.traceId,
        ),
      );
    } catch (e, st) {
      results.add(GateResult('RUNTIME_EXCEPTION', false, '$e\n$st'));
    } finally {
      try {
        await chatModel?.close();
      } catch (_) {}
      try {
        chatDb?.close();
      } catch (_) {}
      await fixture?.cleanup();
      try {
        await RetrievalBenchmarkFixture.removeKnownFixtures(engine);
      } catch (_) {}
    }

    final report = GoldenTestReport(started, results);
    final docs = await getApplicationDocumentsDirectory();
    await File(p.join(docs.path, 'PG_GOLDEN_LAST.json'))
        .writeAsString(const JsonEncoder.withIndent('  ').convert(report.toJson()));
    return report;
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
    final chunks = List<PgChunk>.generate(
      5,
      (i) => PgChunk(
        id: 'golden-heavy-$i',
        documentId: 'golden-heavy-doc',
        sourceName: 'pg_golden_heavy_context.txt',
        locator: 'chunk#$i',
        ordinal: i,
        text: '第${i + 1}段上下文证据。${'制造现场诊断与模型上下文预算验证内容。' * 120}',
      ),
      growable: false,
    );
    final lexical = <RetrievalHit>[
      for (var i = 0; i < chunks.length; i++)
        RetrievalHit(
          chunk: chunks[i],
          score: 1.0 - i * 0.05,
          channel: 'fts5',
          rank: i + 1,
        ),
    ];
    final hybrid = <HybridHit>[
      for (var i = 0; i < chunks.length; i++)
        HybridHit(
          chunk: chunks[i],
          score: 1.0 / (i + 1),
          channels: const {'fts5'},
          lexicalRank: i + 1,
          semanticRank: null,
        ),
    ];
    return RetrievalBundle(
      lexicalHits: lexical,
      semanticHits: const [],
      hybridHits: hybrid,
      evidence: [
        for (var i = 0; i < chunks.length; i++)
          EvidenceItem(
            anchor: 'E${i + 1}',
            chunk: chunks[i],
            score: hybrid[i].score,
          ),
      ],
      lexicalOnly: true,
    );
  }
}
