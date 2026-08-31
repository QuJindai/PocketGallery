import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../chat/chat_orchestrator.dart';
import '../../lineage/lineage_models.dart';
import '../../lineage/lineage_store.dart';
import '../../lineage/trace_snapshot.dart';
import '../../services/knowledge_engine.dart';
import 'candidate_pool_page.dart';
import 'chunk_lineage_page.dart';
import 'document_parse_microscope_page.dart';
import 'embedding_microscope_page.dart';
import 'evidence_context_page.dart';
import 'fts_lineage_page.dart';
import 'generation_citation_page.dart';
import 'lineage_dashboard_visuals.dart';
import 'lineage_formatters.dart';
import 'rag_stage.dart';
import 'rank_trajectory_page.dart';
import 'retrieval_experiment_center_page.dart';
import 'router_decision_page.dart';
import 'trace_actions.dart';
import 'vector_space_page.dart';

export 'lineage_formatters.dart' show formatGenerationSummary;

class RagLineageDashboardPage extends StatefulWidget {
  const RagLineageDashboardPage({
    super.key,
    required this.engine,
    required this.lineageStore,
    this.traceId,
    this.orchestrator,
  });

  final KnowledgeEngine engine;
  final LineageStore lineageStore;
  final String? traceId;
  final ChatOrchestrator? orchestrator;

  @override
  State<RagLineageDashboardPage> createState() =>
      _RagLineageDashboardPageState();
}

class _RagLineageDashboardPageState extends State<RagLineageDashboardPage> {
  List<LineageTrace> traces = const <LineageTrace>[];
  TraceSnapshot? snapshot;
  bool loading = true;
  bool actionBusy = false;
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
      final choices = <LineageTrace>[
        if (selected != null &&
            !latest.any((item) => item.traceId == selected!.traceId))
          selected,
        ...latest,
      ];
      final loaded = selected == null
          ? null
          : await TraceSnapshot.load(widget.lineageStore, selected.traceId);
      if (!mounted) return;
      setState(() {
        traces = choices;
        snapshot = loaded;
      });
    } catch (caught) {
      if (!mounted) return;
      setState(() => error = caught);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = snapshot;
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
              if (loading || actionBusy) const LinearProgressIndicator(),
              if (error != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('Lineage 读取失败：$error'),
                  ),
                ),
              _identityCard(context),
              if (!loading && data == null)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Text(
                      '尚无运行时 Trace。完成一次“自动”或“强制知识库”聊天后，'
                      '这里会显示真实链路；缺失数据不会按 0 填充。',
                    ),
                  ),
                ),
              if (data != null) ...[
                _traceHeader(context, data),
                const SizedBox(height: 8),
                _stageStrip(data),
                const SizedBox(height: 8),
                for (final stage in RagStage.values) ...[
                  _stageSummaryCard(context, data, stage),
                  const SizedBox(height: 6),
                ],
                TraceWaterfallCard(events: data.events),
                LineageGraphCard(snapshot: data),
                ActiveShadowSummaryCard(
                  snapshot: data,
                  onOpenExperiments: () => _openExperiments(data),
                ),
                TraceActionsCard(
                  onRerun: () => _rerun(data),
                  onCopy: () => _copyTraceId(data.trace.traceId),
                  onCompare: () => _compare(data),
                  onExport: () => _export(data),
                  rerunEnabled: widget.orchestrator != null && !actionBusy,
                  compareEnabled: traces.length > 1 && !actionBusy,
                ),
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
              Text('R4.6-B/C · 完整运行显微镜',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              const Text('Chunk ≠ Vector · Chunk → Embedding → index entry'),
              const SizedBox(height: 8),
              const Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Chip(label: Text('REAL · 已捕获运行事实')),
                  Chip(label: Text('DERIVED · 由事实计算')),
                  Chip(label: Text('ACTIVE · 当前回答路径')),
                  Chip(label: Text('SHADOW · 隔离实验')),
                ],
              ),
              const Text('未捕获就是未捕获；backend 未暴露时不猜测。'),
            ],
          ),
        ),
      );

  Widget _traceHeader(BuildContext context, TraceSnapshot data) {
    final trace = data.trace;
    final elapsed = trace.completedAt?.difference(trace.startedAt);
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
            SelectableText('Trace ID: ${trace.traceId}'),
            Text(
              '${trace.requestedMode} → ${trace.finalMode} · '
              '${trace.status.name} · '
              '${elapsed == null ? '总耗时未捕获' : '总耗时 ${(elapsed.inMilliseconds / 1000).toStringAsFixed(2)} s'}',
            ),
            Text('strategy · ${trace.activeStrategyId} · ACTIVE'),
            if (trace.failureStage != null || trace.failureCode != null)
              Text(
                'failure · ${trace.failureStage ?? '未捕获'} / '
                '${trace.failureCode ?? '未捕获'}',
              ),
          ],
        ),
      ),
    );
  }

  Widget _stageStrip(TraceSnapshot data) => SingleChildScrollView(
        key: const ValueKey<String>('rag-stage-strip'),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final stage in RagStage.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  key: ValueKey<String>('rag-stage-${stage.number}'),
                  avatar: CircleAvatar(child: Text('${stage.number}')),
                  label: Text('${stage.number} ${stage.title}'),
                  onPressed: () => _openStage(data, stage),
                ),
              ),
          ],
        ),
      );

  Widget _stageSummaryCard(
    BuildContext context,
    TraceSnapshot data,
    RagStage stage,
  ) {
    final events = _eventsForStage(data, stage);
    final badges = _badgesForStage(stage);
    return Card(
      key: ValueKey<String>('rag-stage-summary-${stage.number}'),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openStage(data, stage),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(radius: 15, child: Text('${stage.number}')),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      stage.title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final badge in badges)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(badge),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(_stageSummary(data, stage)),
              for (final event in events.take(2)) ...[
                const SizedBox(height: 5),
                SelectableText(
                  '${event.kind} · ${event.truthKind.dbValue} · '
                  '${formatDurationUs(event.durationUs)}\n${event.payloadJson}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<String> _badgesForStage(RagStage stage) => switch (stage) {
        RagStage.rank => const <String>['DERIVED', 'ACTIVE'],
        RagStage.evidence => const <String>['REAL', 'DERIVED', 'ACTIVE'],
        _ => const <String>['REAL', 'ACTIVE'],
      };

  List<TraceEventRecord> _eventsForStage(
    TraceSnapshot data,
    RagStage stage,
  ) {
    final stages = switch (stage) {
      RagStage.documentParse => const <String>{'document', 'import', 'parse'},
      RagStage.chunk => const <String>{'chunk'},
      RagStage.fts => const <String>{'fts'},
      RagStage.embedding => const <String>{'embedding'},
      RagStage.vectorSpace => const <String>{'vector'},
      RagStage.candidates => const <String>{'candidate'},
      RagStage.rank => const <String>{'fusion', 'rerank'},
      RagStage.router => const <String>{'router'},
      RagStage.evidence => const <String>{'evidence', 'context'},
      RagStage.generation => const <String>{'generation', 'citation'},
    };
    return data.events
        .where((event) => stages.contains(event.stage))
        .toList(growable: false);
  }

  String _stageSummary(TraceSnapshot data, RagStage stage) {
    final events = _eventsForStage(data, stage);
    final activeCandidates = data.candidates
        .where((candidate) => candidate.lane == RetrievalLane.active)
        .toList(growable: false);
    return switch (stage) {
      RagStage.documentParse => data.documentsById.isEmpty
          ? '本轮聊天不执行文档解析 · 导入阶段事实按关联来源显示'
          : '${data.documentsById.length} 文档 · ${data.sectionsById.length} sections',
      RagStage.chunk => data.chunksById.isEmpty
          ? '本轮聊天不执行切片 · 使用已持久化 Chunk'
          : '${data.chunksById.length} 个关联 Chunk',
      RagStage.fts => events.isEmpty
          ? 'FTS5 运行数据未捕获'
          : '${events.length} 条 FTS5 事件',
      RagStage.embedding => data.queryEmbedding == null
          ? 'Query Embedding 未捕获'
          : '${data.queryEmbedding!.dimension} dims · '
              '${data.queryEmbedding!.generationMs} ms · REAL',
      RagStage.vectorSpace => activeCandidates
              .where((candidate) => candidate.vectorRank != null)
              .isEmpty
          ? 'ACTIVE vector search 未捕获'
          : '${activeCandidates.where((candidate) => candidate.vectorRank != null).length} vector hits',
      RagStage.candidates =>
        '${activeCandidates.length} candidates · selected '
            '${activeCandidates.where((item) => item.selectedForEvidence).length} · '
            'dropped ${activeCandidates.where((item) => item.dropReason != null).length}',
      RagStage.rank => events.isEmpty
          ? '融合/重排事件未捕获'
          : '${events.length} 条融合/重排事件',
      RagStage.router => data.activeRouter == null
          ? '路由决策未捕获'
          : '${data.activeRouter!.finalUseKnowledge ? '使用知识库' : '不使用知识库'} · '
              '${data.activeRouter!.decisionReason} · '
              'FTS ${data.activeRouter!.ftsHitCount} · '
              'top1 ${formatNumber(data.activeRouter!.top1Cosine)}',
      RagStage.evidence => data.budget == null
          ? '${data.evidence.length} evidence · prompt budget 未捕获'
          : '${data.evidence.length} evidence · prefill '
              '${data.budget!.totalPrefillTokens}/${data.budget!.modelContextLimit} · '
              'reserve ${data.budget!.outputReserveTokens} · '
              'trimmed history ${data.budget!.trimmedHistoryMessages} / '
              'evidence ${data.budget!.trimmedEvidenceItems}',
      RagStage.generation => formatGenerationSummary(
          data.generation,
          citationCount: data.citations.length,
        ),
    };
  }

  Future<void> _openStage(TraceSnapshot data, RagStage stage) async {
    final page = switch (stage) {
      RagStage.documentParse => DocumentParseMicroscopePage(snapshot: data),
      RagStage.chunk => ChunkLineagePage(engine: widget.engine, snapshot: data),
      RagStage.fts => FtsLineagePage(snapshot: data),
      RagStage.embedding =>
        EmbeddingMicroscopePage(engine: widget.engine, snapshot: data),
      RagStage.vectorSpace =>
        VectorSpacePage(engine: widget.engine, snapshot: data),
      RagStage.candidates => CandidatePoolPage(snapshot: data),
      RagStage.rank => RankTrajectoryPage(snapshot: data),
      RagStage.router => RouterDecisionPage(snapshot: data),
      RagStage.evidence => EvidenceContextPage(snapshot: data),
      RagStage.generation => GenerationCitationPage(snapshot: data),
    };
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  Future<void> _openExperiments(TraceSnapshot data) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => RetrievalExperimentCenterPage(
        store: widget.lineageStore,
        experimentEngine: widget.engine.experimentEngine,
        traceId: data.trace.traceId,
      ),
    ));
    await _load(data.trace.traceId);
  }

  Future<void> _rerun(TraceSnapshot data) async {
    final orchestrator = widget.orchestrator;
    if (orchestrator == null || actionBusy) return;
    setState(() => actionBusy = true);
    try {
      final reply = await orchestrator.rerunTrace(data.trace);
      await _load(reply.traceId);
    } catch (caught) {
      if (mounted) _showMessage('Trace 重跑失败：$caught');
    } finally {
      if (mounted) setState(() => actionBusy = false);
    }
  }

  Future<void> _copyTraceId(String traceId) async {
    await Clipboard.setData(ClipboardData(text: traceId));
    if (mounted) _showMessage('Trace ID 已复制');
  }

  Future<void> _export(TraceSnapshot data) async {
    try {
      final path = await writeRedactedTraceReport(data);
      if (mounted) _showMessage('脱敏报告已保存：$path');
    } catch (caught) {
      if (mounted) _showMessage('导出失败：$caught');
    }
  }

  Future<void> _compare(TraceSnapshot baseline) async {
    final alternatives = traces
        .where((trace) => trace.traceId != baseline.trace.traceId)
        .toList(growable: false);
    if (alternatives.isEmpty) return;
    final selected = await showModalBottomSheet<LineageTrace>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('选择历史 Trace')),
            for (final trace in alternatives)
              ListTile(
                title: Text(trace.queryText),
                subtitle: Text(trace.traceId),
                onTap: () => Navigator.of(sheetContext).pop(trace),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final other = await TraceSnapshot.load(
      widget.lineageStore,
      selected.traceId,
    );
    final comparison = TraceComparison.between(baseline, other);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Trace 对比 · DERIVED'),
        content: Text(
          'candidate Δ ${comparison.candidateDelta}\n'
          'evidence Δ ${comparison.evidenceDelta}\n'
          'citation Δ ${comparison.citationDelta}\n'
          'known duration Δ ${formatDurationUs(comparison.knownDurationDeltaUs.abs())} '
          '${comparison.knownDurationDeltaUs < 0 ? '更快' : '更慢/相同'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
