import 'package:flutter/material.dart';

import '../../experiments/retrieval_experiment_engine.dart';
import '../../experiments/retrieval_strategy.dart';
import '../../lineage/lineage_ids.dart';
import '../../lineage/lineage_models.dart';
import '../../lineage/lineage_store.dart';
import '../../okf/okf_experiment_engine.dart';
import '../../okf/okf_models.dart';
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
  Future<_OkfLabSnapshot>? okfLabFuture;
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
      final selectableTraces = <LineageTrace>[...latest];
      final selectedTrace = selected;
      if (selectedTrace != null &&
          !selectableTraces.any(
            (item) => item.traceId == selectedTrace.traceId,
          )) {
        selectableTraces.add(selectedTrace);
      }
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
          jobMap[strategy.id] = await widget.store.buildJobsForStrategy(
            strategy.id,
          );
        }
      }
      final labFuture = selected == null
          ? null
          : _loadOkfLabSnapshot(selected);
      final exactQuery = selected == null
          ? null
          : await widget.store.embeddingById(
              LineageIds.queryEmbeddingId(selected.traceId),
            );
      if (!mounted) return;
      setState(() {
        trace = selected;
        traces = selectableTraces;
        queryEmbedding = exactQuery;
        runs = runMap;
        jobs = jobMap;
        okfLabFuture = labFuture;
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
              _okfLabCard(context),
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
          Text(
            'Trace prerequisites',
            style: Theme.of(context).textTheme.titleSmall,
          ),
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
          Text('ACTIVE Control', style: Theme.of(context).textTheme.titleSmall),
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
    final completed = strategyJobs.fold<int>(
      0,
      (sum, job) => sum + job.completedItems,
    );
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
              if (total > 0) LinearProgressIndicator(value: completed / total),
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

  Widget _okfLabCard(BuildContext context) {
    final future = okfLabFuture;
    if (widget.experimentEngine is! OkfAwareRetrievalExperimentEngine ||
        future == null) {
      return const SizedBox.shrink();
    }
    return Card(
      key: const ValueKey<String>('okf-lab-card'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: FutureBuilder<_OkfLabSnapshot>(
          future: future,
          builder: (context, snapshot) {
            final data = snapshot.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'OKF Lab · 三臂对照',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                const Text('同一 Trace / Query Embedding / 本地模型条件下比较知识表示差异。'),
                const SizedBox(height: 8),
                _okfArm(
                  context,
                  title: 'BARE MODEL',
                  detail: '纯模型基线 · Evidence 0 · Context 0 · 本轮生成 NOT RUN',
                ),
                _okfArm(
                  context,
                  title: 'MARKDOWN CONTROL',
                  detail: data == null
                      ? '读取中…'
                      : 'ACTIVE · candidates ${data.activeCandidateCount} · '
                            'evidence ${data.activeEvidenceCount} · 不读取 OKF 信号',
                ),
                _okfArm(
                  context,
                  title: 'OKF v0.2',
                  detail: data == null
                      ? '读取中…'
                      : 'SHADOW · ${data.runStatus} · candidates '
                            '${data.okfCandidateCount} · evidence '
                            '${data.okfEvidenceCount} · OKF docs ${data.okfDocumentCount}',
                ),
                if (snapshot.hasError)
                  Text('OKF Lab 读取失败：${snapshot.error}')
                else if (data != null) ...[
                  const Divider(),
                  Text(
                    '信任 · verified ${data.verifiedCount} · generated '
                    '${data.generatedCount} · provenance ${data.provenanceCount}',
                  ),
                  Text(
                    '新鲜度 · fresh ${data.freshCount} · stale '
                    '${data.staleCount} · deprecated ${data.deprecatedCount} · '
                    'unknown ${data.unknownCount}',
                  ),
                  if (data.reasons.isEmpty)
                    const Text('OKF 调整原因 · 尚未运行 OKF SHADOW')
                  else ...[
                    const SizedBox(height: 6),
                    const Text('为什么改变排序：'),
                    for (final reason in data.reasons.take(3)) Text('• $reason'),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _okfArm(
    BuildContext context, {
    required String title,
    required String detail,
  }) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.all(9),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).dividerColor),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 132,
          child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Expanded(child: Text(detail)),
      ],
    ),
  );

  Future<_OkfLabSnapshot> _loadOkfLabSnapshot(LineageTrace selected) async {
    final engine = widget.experimentEngine;
    if (engine is! OkfAwareRetrievalExperimentEngine) {
      return const _OkfLabSnapshot.empty();
    }
    final activeCandidates = await widget.store.candidatesForTrace(
      selected.traceId,
      strategyId: selected.activeStrategyId,
      lane: RetrievalLane.active,
    );
    final activeEvidence = await widget.store.evidenceForTrace(
      selected.traceId,
      strategyId: selected.activeStrategyId,
      lane: RetrievalLane.active,
    );
    final okfCandidates = await widget.store.candidatesForTrace(
      selected.traceId,
      strategyId: RetrievalStrategies.okfV02Structured.id,
      lane: RetrievalLane.shadow,
    );
    final okfEvidence = await widget.store.evidenceForTrace(
      selected.traceId,
      strategyId: RetrievalStrategies.okfV02Structured.id,
      lane: RetrievalLane.shadow,
    );
    final signals = await engine.okfStore.candidateSignals(
      traceId: selected.traceId,
      strategyId: RetrievalStrategies.okfV02Structured.id,
    );
    final documents = await engine.okfStore.documentsByIds(
      signals.map((item) => item.documentId),
    );
    final runs = await widget.store.experimentRunsForTrace(
      selected.traceId,
      strategyId: RetrievalStrategies.okfV02Structured.id,
      lane: RetrievalLane.shadow,
    );
    return _OkfLabSnapshot(
      activeCandidateCount: activeCandidates.length,
      activeEvidenceCount: activeEvidence.length,
      okfCandidateCount: okfCandidates.length,
      okfEvidenceCount: okfEvidence.length,
      okfDocumentCount: documents.length,
      runStatus: runs.isEmpty ? 'NOT RUN' : runs.first.status.name.toUpperCase(),
      verifiedCount: documents
          .where((item) => item.trustTier == OkfTrustTier.verified)
          .length,
      generatedCount: documents
          .where((item) => item.trustTier == OkfTrustTier.generated)
          .length,
      provenanceCount: documents
          .where((item) => item.trustTier == OkfTrustTier.provenance)
          .length,
      freshCount: documents
          .where((item) => item.freshness == OkfFreshness.fresh)
          .length,
      staleCount: documents
          .where((item) => item.freshness == OkfFreshness.stale)
          .length,
      deprecatedCount: documents
          .where((item) => item.freshness == OkfFreshness.deprecated)
          .length,
      unknownCount: documents
          .where((item) => item.freshness == OkfFreshness.unknown)
          .length,
      reasons: signals
          .map((item) => '${item.documentId} · ${item.reason} · '
              '${item.baseScore.toStringAsFixed(3)} → '
              '${item.finalScore.toStringAsFixed(3)}')
          .toList(growable: false),
    );
  }

  Widget _promotionCard(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Promotion Gate · 冻结规则',
            style: Theme.of(context).textTheme.titleSmall,
          ),
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
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExperimentRunDetailPage(
          store: widget.store,
          traceId: selected.traceId,
          strategyId: strategy.id,
          experimentRunId: run.experimentRunId,
        ),
      ),
    );
  }
}

class _OkfLabSnapshot {
  const _OkfLabSnapshot({
    required this.activeCandidateCount,
    required this.activeEvidenceCount,
    required this.okfCandidateCount,
    required this.okfEvidenceCount,
    required this.okfDocumentCount,
    required this.runStatus,
    required this.verifiedCount,
    required this.generatedCount,
    required this.provenanceCount,
    required this.freshCount,
    required this.staleCount,
    required this.deprecatedCount,
    required this.unknownCount,
    required this.reasons,
  });

  const _OkfLabSnapshot.empty()
    : activeCandidateCount = 0,
      activeEvidenceCount = 0,
      okfCandidateCount = 0,
      okfEvidenceCount = 0,
      okfDocumentCount = 0,
      runStatus = 'NOT RUN',
      verifiedCount = 0,
      generatedCount = 0,
      provenanceCount = 0,
      freshCount = 0,
      staleCount = 0,
      deprecatedCount = 0,
      unknownCount = 0,
      reasons = const <String>[];

  final int activeCandidateCount;
  final int activeEvidenceCount;
  final int okfCandidateCount;
  final int okfEvidenceCount;
  final int okfDocumentCount;
  final String runStatus;
  final int verifiedCount;
  final int generatedCount;
  final int provenanceCount;
  final int freshCount;
  final int staleCount;
  final int deprecatedCount;
  final int unknownCount;
  final List<String> reasons;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
