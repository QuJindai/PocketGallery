import 'package:flutter/material.dart';

import '../../core/hybrid_ranker.dart';
import '../../eval/local_benchmark_store.dart';
import '../../eval/retrieval_benchmark.dart';
import '../../eval/retrieval_benchmark_fixture.dart';
import '../../eval/retrieval_evaluator.dart';
import '../../lineage/lineage_models.dart';
import '../../lineage/trace_snapshot.dart';
import '../../services/knowledge_engine.dart';
import 'benchmark_case_detail_page.dart';

enum _BenchmarkDatasetKind { golden, local }

class RetrievalBenchmarkPage extends StatefulWidget {
  const RetrievalBenchmarkPage({super.key, required this.engine});

  final KnowledgeEngine engine;

  @override
  State<RetrievalBenchmarkPage> createState() => _RetrievalBenchmarkPageState();
}

class _RetrievalBenchmarkPageState extends State<RetrievalBenchmarkPage> {
  RetrievalBenchmarkDataset? dataset;
  List<LocalBenchmarkCase> localCases = const <LocalBenchmarkCase>[];
  _BenchmarkDatasetKind datasetKind = _BenchmarkDatasetKind.golden;
  final Map<RetrievalStrategy, RetrievalMetrics?> metrics = {};
  final Map<RetrievalStrategy, List<BenchmarkCaseResult>> results = {};
  bool loading = true;
  bool running = false;
  Object? error;
  double alternateLexicalWeight = 1.15;
  double alternateSemanticWeight = 1.0;
  double alternateDualBonus = 0.02;
  HybridRanker? lastCurrentHybrid;
  HybridRanker? lastAlternateHybrid;
  String status = '未运行';

  @override
  void initState() {
    super.initState();
    _loadDataset();
  }

  Future<void> _loadDataset() async {
    try {
      final value = await RetrievalBenchmarkDataset.loadAsset(
        'assets/golden/rag_microscope_benchmark.json',
      );
      await widget.engine.localBenchmarkStore.initialize();
      final local = await widget.engine.localBenchmarkStore.listCases();
      if (!mounted) return;
      setState(() {
        dataset = value;
        localCases = local;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e;
        loading = false;
      });
    }
  }

  RetrievalBenchmarkDataset? get _selectedDataset {
    if (datasetKind == _BenchmarkDatasetKind.golden) return dataset;
    return RetrievalBenchmarkDataset(
      'Local Real Corpus',
      localCases.map((item) => item.toBenchmarkCase()).toList(growable: false),
    );
  }

  Future<void> _saveLatestTrace() async {
    final traces = await widget.engine.lineageStore.latestTraces(limit: 30);
    LineageTrace? selectedTrace;
    for (final item in traces) {
      if (item.status == TraceStatus.complete) {
        selectedTrace = item;
        break;
      }
    }
    if (selectedTrace == null) {
      if (mounted) setState(() => status = '没有可保存的完整 Trace');
      return;
    }
    final snapshot = await TraceSnapshot.load(
      widget.engine.lineageStore,
      selectedTrace.traceId,
    );
    final candidates = snapshot.candidatesFor(
      strategyId: selectedTrace.activeStrategyId,
      lane: RetrievalLane.active,
    );
    if (!mounted) return;
    if (candidates.isEmpty) {
      setState(() => status = '该 Trace 没有可标注候选');
      return;
    }
    final chosen = <String>{};
    final selectedChunks = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('选择期望 Chunk'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(selectedTrace!.queryText),
                const SizedBox(height: 8),
                for (final candidate in candidates)
                  CheckboxListTile(
                    value: chosen.contains(candidate.chunkId),
                    title: Text(candidate.chunkId),
                    subtitle: Text(
                      snapshot.chunksById[candidate.chunkId]?.documentId ??
                          '来源文档未捕获',
                    ),
                    onChanged: (checked) => setDialogState(() {
                      if (checked ?? false) {
                        chosen.add(candidate.chunkId);
                      } else {
                        chosen.remove(candidate.chunkId);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: chosen.isEmpty
                  ? null
                  : () => Navigator.of(dialogContext).pop(Set.of(chosen)),
              child: const Text('保存 Case'),
            ),
          ],
        ),
      ),
    );
    if (selectedChunks == null || selectedChunks.isEmpty) return;
    final now = DateTime.now().toUtc();
    final expectedDocuments = <String>{
      for (final chunkId in selectedChunks)
        if (snapshot.chunksById[chunkId] != null)
          snapshot.chunksById[chunkId]!.documentId,
    };
    await widget.engine.localBenchmarkStore.putCase(LocalBenchmarkCase(
      id: 'local-${now.microsecondsSinceEpoch}',
      question: selectedTrace.queryText,
      expectedDocumentIds: expectedDocuments,
      expectedChunkIds: selectedChunks,
      tags: const <String>{'local-real', 'trace-labeled'},
      sourceTraceId: selectedTrace.traceId,
      createdAt: now,
      updatedAt: now,
    ));
    final updated = await widget.engine.localBenchmarkStore.listCases();
    if (!mounted) return;
    setState(() {
      localCases = updated;
      datasetKind = _BenchmarkDatasetKind.local;
      metrics.clear();
      results.clear();
      status = '已保存本地 Case · ${selectedTrace!.traceId}';
    });
  }

  Future<void> _run() async {
    final data = _selectedDataset;
    if (data == null || data.cases.isEmpty || running) return;
    final currentHybrid = widget.engine.ranker;
    final alternateHybrid = HybridRanker(
      lexicalWeight: alternateLexicalWeight,
      semanticWeight: alternateSemanticWeight,
      dualChannelBonus: alternateDualBonus,
    );
    setState(() {
      running = true;
      error = null;
      status = '准备临时 Golden 基准语料…';
      metrics.clear();
      results.clear();
      lastCurrentHybrid = currentHybrid;
      lastAlternateHybrid = alternateHybrid;
    });

    RetrievalBenchmarkLease? lease;
    var completed = false;
    try {
      if (datasetKind == _BenchmarkDatasetKind.golden) {
        // Golden labels refer to pg_golden_* sources. Seed their deterministic
        // fixture only for this run; local cases always use the real corpus.
        lease = await RetrievalBenchmarkFixture.prepare(
          widget.engine,
          resetKnownFixtures: true,
        );
      }

      final runner = RetrievalBenchmarkRunner(
        lexicalStore: widget.engine.lexicalStore,
        semanticStore: widget.engine.semanticStore,
        currentHybrid: currentHybrid,
        alternateHybrid: alternateHybrid,
      );
      const evaluator = RetrievalEvaluator();
      for (final strategy in RetrievalStrategy.values) {
        if (!mounted) return;
        setState(() => status = '运行 ${_label(strategy)}…');
        final strategyResults = await runner.runDataset(data, strategy);
        if (!mounted) return;
        setState(() {
          results[strategy] = strategyResults;
          metrics[strategy] = evaluator.aggregate(data.cases, strategyResults);
        });
      }
      completed = true;
      if (mounted) {
        setState(() => status = '评估完成，正在清理临时 Golden 语料…');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e;
          status = '运行失败';
        });
      }
    } finally {
      await lease?.cleanup();
      if (mounted) {
        setState(() {
          running = false;
          if (completed) {
            status = datasetKind == _BenchmarkDatasetKind.golden
                ? '完成 · ${data.cases.length} cases · 临时 Golden 已清理'
                : '完成 · ${data.cases.length} local-real cases';
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedDataset = _selectedDataset;
    return Scaffold(
      appBar: AppBar(title: const Text('检索基准 / A-B Lab')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (loading) const LinearProgressIndicator(),
            if (dataset != null) ...[
              SegmentedButton<_BenchmarkDatasetKind>(
                segments: const [
                  ButtonSegment(
                    value: _BenchmarkDatasetKind.golden,
                    label: Text('Packaged Golden'),
                  ),
                  ButtonSegment(
                    value: _BenchmarkDatasetKind.local,
                    label: Text('Local Real Corpus'),
                  ),
                ],
                selected: <_BenchmarkDatasetKind>{datasetKind},
                onSelectionChanged: running
                    ? null
                    : (values) => setState(() {
                          datasetKind = values.single;
                          metrics.clear();
                          results.clear();
                          status = '未运行';
                        }),
              ),
              const SizedBox(height: 8),
              Text(selectedDataset?.name ?? '数据集不可用',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                datasetKind == _BenchmarkDatasetKind.golden
                    ? '${selectedDataset?.cases.length ?? 0} 个带人工期望来源的 Golden cases · 运行时自动装载临时基准语料，结束后清理'
                    : '${localCases.length} 个持久化本地真实语料 cases · 不复制原始向量',
              ),
            ],
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Alternate Hybrid 参数',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    _slider(
                      'Lexical weight',
                      alternateLexicalWeight,
                      0.5,
                      1.5,
                      (v) => setState(() => alternateLexicalWeight = v),
                    ),
                    _slider(
                      'Semantic weight',
                      alternateSemanticWeight,
                      0.5,
                      1.5,
                      (v) => setState(() => alternateSemanticWeight = v),
                    ),
                    _slider(
                      'Dual bonus',
                      alternateDualBonus,
                      0,
                      0.08,
                      (v) => setState(() => alternateDualBonus = v),
                    ),
                    FilledButton.icon(
                      onPressed: selectedDataset == null ||
                              selectedDataset.cases.isEmpty ||
                              running
                          ? null
                          : _run,
                      icon: const Icon(Icons.science_outlined),
                      label: Text(running ? status : '运行 A/B 检索基准'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const ValueKey<String>('save-trace-local-benchmark'),
                      onPressed: running ? null : _saveLatestTrace,
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: const Text('保存最新 Trace 为本地 Case'),
                    ),
                  ],
                ),
              ),
            ),
            if (running) const LinearProgressIndicator(),
            if (error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('Benchmark 失败：$error'),
                ),
              ),
            const SizedBox(height: 8),
            Text('评估结果 · $status',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            for (final strategy in RetrievalStrategy.values)
              _metricsCard(strategy, metrics[strategy]),
            const SizedBox(height: 8),
            Text(
              'Hit@K / Recall / MRR / Context Precision 均为 DERIVED 指标；每个候选命中与排名来自真实 FTS5 / Embedding 运行。临时 Golden 语料只在本次评估期间存在。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) =>
      Row(
        children: [
          SizedBox(width: 120, child: Text(label)),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: running ? null : onChanged,
            ),
          ),
          SizedBox(width: 52, child: Text(value.toStringAsFixed(3))),
        ],
      );

  Widget _metricsCard(RetrievalStrategy strategy, RetrievalMetrics? value) {
    final comparison = strategy == RetrievalStrategy.alternateHybrid
        ? _alternateComparison()
        : null;
    return Card(
      child: InkWell(
        onTap: value == null ? null : () => _openCaseResults(strategy),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Row(
              children: [
                Expanded(
                  child: Text(_label(strategy),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Text(value == null ? '未运行' : '${value.caseCount} cases'),
              ],
            ),
            const SizedBox(height: 8),
            if (value == null)
              const Text('—')
            else
              ...[
                if (strategy == RetrievalStrategy.hybrid ||
                    strategy == RetrievalStrategy.alternateHybrid) ...[
                  Text(
                    _hybridParameterSummary(strategy),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _metric('Hit@1', value.hitAt1),
                    _metric('Hit@3', value.hitAt3),
                    _metric('Recall@5', value.recallAt5),
                    _metric('MRR', value.mrr),
                    _metric('Context Precision', value.contextPrecision),
                    _optionalMetric('Router Accuracy', value.routerAccuracy),
                    _optionalMetric(
                      'Citation Grounding',
                      value.citationGroundingRate,
                    ),
                  ],
                ),
                if (comparison != null) ...[
                  const SizedBox(height: 8),
                  Text(comparison.summary),
                  if (comparison.rankingChangedCases == 0)
                    Text(
                      '当前 cases 未产生排序差异；不代表两组参数相同。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openCaseResults(RetrievalStrategy strategy) async {
    final data = _selectedDataset;
    final strategyResults = results[strategy];
    if (data == null || strategyResults == null || strategyResults.isEmpty) {
      return;
    }
    final selectedId = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('选择 Benchmark Case')),
            for (final benchmark in data.cases)
              ListTile(
                title: Text(benchmark.question),
                subtitle: Text(benchmark.id),
                onTap: () => Navigator.of(sheetContext).pop(benchmark.id),
              ),
          ],
        ),
      ),
    );
    if (selectedId == null || !mounted) return;
    RetrievalBenchmarkCase? benchmark;
    BenchmarkCaseResult? result;
    BenchmarkCaseResult? baseline;
    for (final item in data.cases) {
      if (item.id == selectedId) benchmark = item;
    }
    for (final item in strategyResults) {
      if (item.caseId == selectedId) result = item;
    }
    for (final item in results[RetrievalStrategy.ftsOnly] ??
        const <BenchmarkCaseResult>[]) {
      if (item.caseId == selectedId) baseline = item;
    }
    if (benchmark == null || result == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BenchmarkCaseDetailPage(
        benchmark: benchmark!,
        result: result!,
        baseline: strategy == RetrievalStrategy.ftsOnly ? null : baseline,
      ),
    ));
  }

  Widget _metric(String label, double value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text((value * 100).toStringAsFixed(1),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(fontSize: 10)),
          ],
        ),
      );

  Widget _optionalMetric(String label, double? value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value == null ? '不可用' : (value * 100).toStringAsFixed(1),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(label, style: const TextStyle(fontSize: 10)),
          ],
        ),
      );

  RetrievalRankingComparison? _alternateComparison() {
    final current = results[RetrievalStrategy.hybrid];
    final alternate = results[RetrievalStrategy.alternateHybrid];
    if (current == null || alternate == null) return null;
    return const RetrievalEvaluator().compareRankings(current, alternate);
  }

  String _hybridParameterSummary(RetrievalStrategy strategy) {
    final ranker = strategy == RetrievalStrategy.hybrid
        ? lastCurrentHybrid
        : lastAlternateHybrid;
    if (ranker == null) return '参数未运行';
    return 'RRF k=${ranker.rrfK} · lexical '
        '${ranker.lexicalWeight.toStringAsFixed(3)} · semantic '
        '${ranker.semanticWeight.toStringAsFixed(3)} · dual '
        '${ranker.dualChannelBonus.toStringAsFixed(3)}';
  }

  String _label(RetrievalStrategy strategy) => switch (strategy) {
        RetrievalStrategy.ftsOnly => 'A · FTS5 only',
        RetrievalStrategy.embeddingOnly => 'B · Embedding only',
        RetrievalStrategy.hybrid => 'C · Current Hybrid',
        RetrievalStrategy.alternateHybrid => 'D · Alternate Hybrid',
      };
}
