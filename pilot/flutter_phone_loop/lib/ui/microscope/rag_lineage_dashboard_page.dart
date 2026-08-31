import 'package:flutter/material.dart';

import '../../lineage/lineage_models.dart';
import '../../lineage/lineage_store.dart';
import '../../services/knowledge_engine.dart';

String formatGenerationSummary(
  GenerationStatsRecord? generation, {
  required int citationCount,
}) {
  if (generation == null) {
    return 'generation 未捕获 · TTFT 未捕获 · output tokens 未捕获 · '
        'decode 未捕获 · backend 未暴露 · citations $citationCount';
  }

  final ttft = generation.ttftMs == null
      ? 'TTFT 未捕获'
      : 'TTFT ${generation.ttftMs} ms';
  final output = generation.outputTokens == null
      ? 'output tokens 未捕获'
      : 'output ${generation.outputTokens} tokens';
  final decode = generation.decodeTokensPerSecond == null
      ? 'decode 未捕获'
      : 'decode ${generation.decodeTokensPerSecond!.toStringAsFixed(1)} tok/s';
  final backend = generation.backend == null
      ? 'backend 未暴露'
      : 'backend ${generation.backend}';
  return 'generation ${generation.generationMs} ms · $ttft · $output · '
      '$decode · $backend · citations $citationCount';
}

class RagLineageDashboardPage extends StatefulWidget {
  const RagLineageDashboardPage({
    super.key,
    required this.engine,
    required this.lineageStore,
    this.traceId,
  });

  final KnowledgeEngine engine;
  final LineageStore lineageStore;
  final String? traceId;

  @override
  State<RagLineageDashboardPage> createState() =>
      _RagLineageDashboardPageState();
}

class _RagLineageDashboardPageState
    extends State<RagLineageDashboardPage> {
  List<LineageTrace> traces = const <LineageTrace>[];
  _TraceLineage? lineage;
  bool loading = true;
  Object? error;

  @override
  void initState() {
    super.initState();
    _load(widget.traceId);
  }

  Future<void> _load(String? requestedTraceId) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final latest = await widget.lineageStore.latestTraces(limit: 30);
      LineageTrace? selected;
      if (requestedTraceId != null) {
        selected = await widget.lineageStore.traceById(requestedTraceId);
      }
      selected ??= latest.firstOrNull;
      final selectedTrace = selected;

      final choices = <LineageTrace>[
        if (selectedTrace != null &&
            !latest.any((item) => item.traceId == selectedTrace.traceId))
          selectedTrace,
        ...latest,
      ];
      final loaded =
          selectedTrace == null ? null : await _loadTrace(selectedTrace);
      if (!mounted) return;
      setState(() {
        traces = choices;
        lineage = loaded;
      });
    } catch (caught) {
      if (!mounted) return;
      setState(() => error = caught);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<_TraceLineage> _loadTrace(LineageTrace trace) async {
    final events = await widget.lineageStore.eventsForTrace(trace.traceId);
    final candidates =
        await widget.lineageStore.candidatesForTrace(trace.traceId);
    final router = await widget.lineageStore.routerDecisionForTrace(
      trace.traceId,
      trace.activeStrategyId,
      RetrievalLane.active,
    );
    final evidence = await widget.lineageStore.evidenceForTrace(trace.traceId);
    final budget =
        await widget.lineageStore.promptBudgetForTrace(trace.traceId);
    final generation =
        await widget.lineageStore.generationStatsForTrace(trace.traceId);
    final citations =
        await widget.lineageStore.citationsForTrace(trace.traceId);
    return _TraceLineage(
      trace: trace,
      events: events,
      candidates: candidates,
      router: router,
      evidence: evidence,
      budget: budget,
      generation: generation,
      citations: citations,
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = lineage;
    return Scaffold(
      appBar: AppBar(
        title: const Text('RAG Lineage'),
        actions: [
          IconButton(
            tooltip: '刷新真实记录',
            onPressed: loading ? null : () => _load(data?.trace.traceId),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (loading) const LinearProgressIndicator(),
              if (error != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('Lineage 读取失败：$error'),
                  ),
                ),
              _identityCard(context),
              const SizedBox(height: 8),
              if (!loading && data == null)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Text(
                      '尚无运行时 Trace。完成一次“自动”或“强制知识库”聊天后，这里会显示真实链路；缺失数据不会按 0 填充。',
                    ),
                  ),
                ),
              if (data != null) ...[
                _traceCard(context, data),
                const SizedBox(height: 8),
                ..._stageCards(context, data),
                const SizedBox(height: 8),
                _futureCard(context),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _identityCard(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '对象身份与真值',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              const Text('Chunk ≠ Vector · Chunk → Embedding → ACTIVE index entry'),
              const SizedBox(height: 8),
              const Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Chip(label: Text('REAL · 已捕获运行事实')),
                  Chip(label: Text('DERIVED · 由事实计算')),
                  Chip(label: Text('ACTIVE · 当前检索路径')),
                ],
              ),
              const SizedBox(height: 4),
              const Text('未捕获就是未捕获；backend 未暴露时不猜测，也不填充虚构时延。'),
            ],
          ),
        ),
      );

  Widget _traceCard(BuildContext context, _TraceLineage data) {
    final trace = data.trace;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (traces.length > 1)
              DropdownButton<String>(
                isExpanded: true,
                value: trace.traceId,
                items: [
                  for (final item in traces)
                    DropdownMenuItem<String>(
                      value: item.traceId,
                      child: Text(
                        '${item.queryText} · ${item.status.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: loading ? null : _load,
              ),
            Text(trace.queryText,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 5),
            SelectableText(trace.traceId),
            Text(
              '${trace.requestedMode} → ${trace.finalMode} · ${trace.status.name}',
            ),
            Text('strategy · ${trace.activeStrategyId} · ACTIVE'),
            if (trace.failureStage != null || trace.failureCode != null)
              Text(
                'failure · ${trace.failureStage ?? '未捕获'} / ${trace.failureCode ?? '未捕获'}',
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _stageCards(BuildContext context, _TraceLineage data) {
    final documentEvents = data.matchEvents(
      stages: const {'document', 'import', 'parse'},
      kindFragments: const {'document.', 'parse.'},
    );
    final chunkEvents = data.matchEvents(
      stages: const {'chunk'},
      kindFragments: const {'chunk.'},
    );
    final ftsEvents = data.matchEvents(stages: const {'fts'});
    final embeddingEvents = data.matchEvents(stages: const {'embedding'});
    final vectorEvents = data.matchEvents(stages: const {'vector'});
    final candidateEvents = data.matchEvents(stages: const {'candidate'});
    final fusionEvents = data.matchEvents(
      stages: const {'fusion', 'rerank'},
    );
    final routerEvents = data.matchEvents(stages: const {'router'});
    final contextEvents = data.matchEvents(
      stages: const {'evidence', 'context'},
    );
    final generationEvents = data.matchEvents(
      stages: const {'generation', 'citation'},
    );
    final selectedCandidates =
        data.candidates.where((item) => item.selectedForEvidence).length;
    final droppedCandidates =
        data.candidates.where((item) => item.dropReason != null).length;
    final router = data.router;
    final budget = data.budget;
    final generation = data.generation;

    return <Widget>[
      _stageCard(
        context,
        number: 1,
        title: '文档解析',
        badges: const {'REAL'},
        summary: documentEvents.isEmpty
            ? '本轮聊天不执行文档解析 · 导入阶段事实请到 Chunk Explorer 查看'
            : '${documentEvents.length} 条解析事件',
        events: documentEvents,
      ),
      _stageCard(
        context,
        number: 2,
        title: '切片',
        badges: const {'REAL'},
        summary: chunkEvents.isEmpty
            ? '本轮聊天不执行切片 · 使用已持久化 Chunk'
            : '${chunkEvents.length} 条切片事件',
        events: chunkEvents,
      ),
      _stageCard(
        context,
        number: 3,
        title: 'FTS5',
        badges: const {'REAL', 'ACTIVE'},
        summary: ftsEvents.isEmpty
            ? 'FTS5 运行数据未捕获'
            : '${ftsEvents.length} 条 FTS5 事件',
        events: ftsEvents,
      ),
      _stageCard(
        context,
        number: 4,
        title: 'Embedding',
        badges: const {'REAL', 'ACTIVE'},
        summary: embeddingEvents.isEmpty
            ? 'Query Embedding 未捕获'
            : '${embeddingEvents.length} 条 Embedding 事件',
        events: embeddingEvents,
      ),
      _stageCard(
        context,
        number: 5,
        title: '向量空间',
        badges: const {'REAL', 'ACTIVE'},
        summary: vectorEvents.isEmpty
            ? 'ACTIVE vector search 未捕获'
            : '${vectorEvents.length} 条 ACTIVE 检索事件',
        events: vectorEvents,
      ),
      _stageCard(
        context,
        number: 6,
        title: '候选池',
        badges: const {'REAL', 'ACTIVE'},
        summary: data.candidates.isEmpty
            ? '候选记录未捕获'
            : '${data.candidates.length} candidates · selected $selectedCandidates · dropped $droppedCandidates',
        events: candidateEvents,
      ),
      _stageCard(
        context,
        number: 7,
        title: '融合/重排',
        badges: const {'DERIVED', 'ACTIVE'},
        summary: fusionEvents.isEmpty
            ? '融合/重排事件未捕获'
            : '${fusionEvents.length} 条融合/重排事件',
        events: fusionEvents,
      ),
      _stageCard(
        context,
        number: 8,
        title: '路由决策',
        badges: const {'REAL', 'ACTIVE'},
        summary: router == null
            ? '路由决策未捕获'
            : '${router.finalUseKnowledge ? '使用知识库' : '不使用知识库'} · ${router.decisionReason} · FTS ${router.ftsHitCount} · top1 ${_number(router.top1Cosine)}',
        events: routerEvents,
      ),
      _stageCard(
        context,
        number: 9,
        title: '证据与上下文',
        badges: const {'REAL', 'DERIVED', 'ACTIVE'},
        summary: budget == null
            ? '${data.evidence.length} evidence · prompt budget 未捕获'
            : '${data.evidence.length} evidence · prefill ${budget.totalPrefillTokens}/${budget.modelContextLimit} · reserve ${budget.outputReserveTokens} · trimmed history ${budget.trimmedHistoryMessages} / evidence ${budget.trimmedEvidenceItems}',
        events: contextEvents,
      ),
      _stageCard(
        context,
        number: 10,
        title: '生成与引用',
        badges: const {'REAL', 'ACTIVE'},
        summary: formatGenerationSummary(
          generation,
          citationCount: data.citations.length,
        ),
        events: generationEvents,
      ),
    ];
  }

  Widget _stageCard(
    BuildContext context, {
    required int number,
    required String title,
    required Set<String> badges,
    required String summary,
    required List<TraceEventRecord> events,
  }) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(radius: 15, child: Text('$number')),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Wrap(
                    spacing: 4,
                    children: [
                      for (final badge in badges)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(badge),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(summary),
              for (final event in events.take(3)) ...[
                const SizedBox(height: 5),
                SelectableText(
                  '${event.kind} · ${event.truthKind.dbValue}${event.durationUs == null ? '' : ' · ${_duration(event.durationUs!)}'}\n${event.payloadJson}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      );

  Widget _futureCard(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('深潜页面', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              const Text('以下对照实验属于 R4.6-B；尚未实现的数据不会伪装成可用入口。'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.scatter_plot_outlined),
                label: const Text('Embedding 表征对照 · R4.6-B'),
              ),
              OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.compare_arrows),
                label: const Text('候选/路由策略对照 · R4.6-B'),
              ),
            ],
          ),
        ),
      );

  String _duration(int microseconds) {
    if (microseconds < 1000) return '$microseconds µs';
    final milliseconds = microseconds / 1000;
    final fractionDigits = milliseconds == milliseconds.roundToDouble() ? 0 : 1;
    return '${milliseconds.toStringAsFixed(fractionDigits)} ms';
  }

  String _number(double? value) =>
      value == null ? '未捕获' : value.toStringAsFixed(4);
}

class _TraceLineage {
  const _TraceLineage({
    required this.trace,
    required this.events,
    required this.candidates,
    required this.router,
    required this.evidence,
    required this.budget,
    required this.generation,
    required this.citations,
  });

  final LineageTrace trace;
  final List<TraceEventRecord> events;
  final List<CandidateRecord> candidates;
  final RouterDecisionRecord? router;
  final List<EvidenceRecord> evidence;
  final PromptBudgetRecord? budget;
  final GenerationStatsRecord? generation;
  final List<CitationRecord> citations;

  List<TraceEventRecord> matchEvents({
    required Set<String> stages,
    Set<String> kindFragments = const <String>{},
  }) =>
      events
          .where(
            (event) =>
                stages.contains(event.stage) ||
                kindFragments.any(event.kind.contains),
          )
          .toList(growable: false);
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
