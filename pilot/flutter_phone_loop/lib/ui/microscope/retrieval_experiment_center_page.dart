import 'package:flutter/material.dart';

import '../../experiments/retrieval_experiment_engine.dart';
import '../../experiments/retrieval_strategy.dart';
import '../../lineage/lineage_ids.dart';
import '../../lineage/lineage_models.dart';
import '../../lineage/lineage_store.dart';
import 'experiment_run_detail_page.dart';

class RetrievalExperimentCenterPage extends StatefulWidget {
  const RetrievalExperimentCenterPage({
    super.key,
    required this.store,
    required this.experimentEngine,
    this.traceId,
  });

  final LineageStore store;
  final RetrievalExperimentEngine experimentEngine;
  final String? traceId;

  @override
  State<RetrievalExperimentCenterPage> createState() =>
      _RetrievalExperimentCenterPageState();
}

class _RetrievalExperimentCenterPageState
    extends State<RetrievalExperimentCenterPage> {
  LineageTrace? trace;
  LineageEmbedding? queryEmbedding;
  List<LineageTrace> traces = const <LineageTrace>[];
  Map<String, List<ExperimentRunRecord>> runs = const {};
  Map<String, List<BuildJobRecord>> jobs = const {};
  bool loading = true;
  String? runningStrategyId;
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
      final latest = await widget.store.latestTraces(limit: 30);
      LineageTrace? selected;
      if (requestedTraceId != null) {
        selected = await widget.store.traceById(requestedTraceId);
      }
      selected ??= latest.firstOrNull;
      final runMap = <String, List<ExperimentRunRecord>>{};
      final jobMap = <String, List<BuildJobRecord>>{};
      if (selected != null) {
        for (final strategy in RetrievalStrategies.all.where(
          (item) => item.onDemand,
        )) {
          runMap[strategy.id] = await widget.store.experimentRunsForTrace(
            selected.traceId,
            strategyId: strategy.id,
            lane: RetrievalLane.shadow,
          );
          jobMap[strategy.id] =
              await widget.store.buildJobsForStrategy(strategy.id);
        }
      }
      final exactQuery = selected == null
          ? null
          : await widget.store.embeddingById(
              LineageIds.queryEmbeddingId(selected.traceId),
            );
      if (!mounted) return;
      setState(() {
        trace = selected;
        traces = latest;
        queryEmbedding = exactQuery;
        runs = runMap;
        jobs = jobMap;
      });
    } catch (caught) {
      if (mounted) setState(() => error = caught);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  bool get _ready =>
      trace?.status == TraceStatus.complete &&
      queryEmbedding?.representation == EmbeddingRepresentation.query;

  @override
  Widget build(BuildContext context) {
    final selected = trace;
    return Scaffold(
      key: const ValueKey<String>('retrieval-experiment-center-page'),
      appBar: AppBar(
        title: const Text('实验中心 / Experiment Center'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: loading ? null : () => _load(selected?.traceId),
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
              if (error != null) Text('实验数据读取失败：$error'),
              _traceCard(context),
              _activeCard(context),
              for (final strategy in RetrievalStrategies.all.where(
                (item) => item.onDemand,
              ))
                _strategyCard(context, strategy),
              _promotionCard(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _traceCard(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Trace prerequisites',
                  style: Theme.of(context).textTheme.titleSmall),
              if (traces.length > 1)
                DropdownButton<String>(
                  isExpanded: true,
                  value: trace?.traceId,
                  items: [
                    for (final item in traces)
                      DropdownMenuItem(
                        value: item.traceId,
                        child: Text(
                          item.queryText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: runningStrategyId == null ? _load : null,
                ),
              if (trace == null)
                const Text('没有可用 Trace。请先完成一次知识库检索。')
              else ...[
                SelectableText(trace!.traceId),
                Text('${trace!.queryText} · ${trace!.status.name}'),
                if (trace!.status != TraceStatus.complete)
                  const Text('当前 Trace 尚未完成，SHADOW 已禁用。'),
                if (queryEmbedding == null)
                  const Text('缺少精确 Query Embedding，SHADOW 已禁用。')
                else
                  Text(
                    '精确 Query Embedding · ${queryEmbedding!.embeddingId} · '
                    '${queryEmbedding!.dimension} dims · REAL',
                  ),
              ],
            ],
          ),
        ),
      );

  Widget _activeCard(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ACTIVE Control',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(RetrievalStrategies.activeControl.id),
              const Text('当前回答生产路径 · body + FTS5 + vector · 不由实验中心修改'),
            ],
          ),
        ),
      );

  Widget _strategyCard(
    BuildContext context,
    RetrievalStrategyDescriptor strategy,
  ) {
    final strategyRuns = runs[strategy.id] ?? const <ExperimentRunRecord>[];
    final latest = strategyRuns.firstOrNull;
    final strategyJobs = jobs[strategy.id] ?? const <BuildJobRecord>[];
    final total = strategyJobs.fold<int>(0, (sum, job) => sum + job.totalItems);
    final completed =
        strategyJobs.fold<int>(0, (sum, job) => sum + job.completedItems);
    final failedJob = strategyJobs
        .where((job) => job.status == BuildJobStatus.failed)
        .firstOrNull;
    final running = runningStrategyId == strategy.id;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    strategy.label,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const Chip(label: Text('SHADOW')),
              ],
            ),
            Text(strategy.id),
            Text(
              'representations · '
              '${strategy.representations.map((item) => item.name).join(' + ')}',
            ),
            if (strategy.maxSentenceRepresentationsPerChunk > 0)
              Text(
                'sentence cap · '
                '${strategy.maxSentenceRepresentationsPerChunk}/chunk',
              ),
            const SizedBox(height: 6),
            if (strategyJobs.isEmpty)
              const Text('Representation build · 尚未运行')
            else ...[
              Text('Representation build · $completed/$total'),
              if (total > 0)
                LinearProgressIndicator(value: completed / total),
              if (failedJob != null)
                Text(
                  'BUILD FAILED · ${failedJob.failureDetail ?? failedJob.failureCode ?? '原因未捕获'}',
                ),
            ],
            if (latest == null)
              const Text('Last run · 尚未运行')
            else ...[
              Text(
                latest.status == ExperimentRunStatus.failed
                    ? 'SHADOW FAILED · '
                        '${latest.completedItems}/${latest.totalItems}'
                    : 'Last run · ${latest.status.name.toUpperCase()} · '
                        '${latest.completedItems}/${latest.totalItems}',
              ),
              if (latest.failureDetail != null) Text(latest.failureDetail!),
              TextButton(
                onPressed: () => _openRun(strategy, latest),
                child: const Text('检查运行详情'),
              ),
            ],
            FilledButton.icon(
              key: ValueKey<String>('experiment-run-${strategy.id}'),
              onPressed: !_ready || runningStrategyId != null
                  ? null
                  : () => _run(strategy),
              icon: Icon(
                latest?.status == ExperimentRunStatus.failed
                    ? Icons.restart_alt
                    : Icons.play_arrow,
              ),
              label: Text(
                running
                    ? '运行中…'
                    : latest?.status == ExperimentRunStatus.failed
                        ? '继续 / 重试'
                        : '按需运行',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _promotionCard(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Promotion Gate · 冻结规则',
                  style: Theme.of(context).textTheme.titleSmall),
              const Text(
                '实验只写 SHADOW。切换 ACTIVE 前必须满足回归、基准、Phone Golden、'
                '升级与签名门禁，并需用户明确批准。',
              ),
            ],
          ),
        ),
      );

  Future<void> _run(RetrievalStrategyDescriptor strategy) async {
    final selected = trace;
    if (selected == null || !_ready || runningStrategyId != null) return;
    setState(() => runningStrategyId = strategy.id);
    try {
      await widget.experimentEngine.run(
        traceId: selected.traceId,
        strategyId: strategy.id,
      );
      await _load(selected.traceId);
    } catch (caught) {
      if (mounted) setState(() => error = caught);
    } finally {
      if (mounted) setState(() => runningStrategyId = null);
    }
  }

  Future<void> _openRun(
    RetrievalStrategyDescriptor strategy,
    ExperimentRunRecord run,
  ) async {
    final selected = trace;
    if (selected == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ExperimentRunDetailPage(
        store: widget.store,
        traceId: selected.traceId,
        strategyId: strategy.id,
        experimentRunId: run.experimentRunId,
      ),
    ));
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
