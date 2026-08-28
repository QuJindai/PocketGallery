import 'package:flutter/material.dart';

import '../../core/hybrid_ranker.dart';
import '../../eval/retrieval_benchmark.dart';
import '../../eval/retrieval_evaluator.dart';
import '../../services/knowledge_engine.dart';

class RetrievalBenchmarkPage extends StatefulWidget {
  const RetrievalBenchmarkPage({super.key, required this.engine});

  final KnowledgeEngine engine;

  @override
  State<RetrievalBenchmarkPage> createState() => _RetrievalBenchmarkPageState();
}

class _RetrievalBenchmarkPageState extends State<RetrievalBenchmarkPage> {
  RetrievalBenchmarkDataset? dataset;
  final Map<RetrievalStrategy, RetrievalMetrics?> metrics = {};
  bool loading = true;
  bool running = false;
  Object? error;
  double alternateLexicalWeight = 1.15;
  double alternateSemanticWeight = 1.0;
  double alternateDualBonus = 0.02;
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
      if (!mounted) return;
      setState(() {
        dataset = value;
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

  Future<void> _run() async {
    final data = dataset;
    if (data == null || running) return;
    setState(() {
      running = true;
      error = null;
      status = '运行检索基准…';
      metrics.clear();
    });
    try {
      final runner = RetrievalBenchmarkRunner(
        lexicalStore: widget.engine.lexicalStore,
        semanticStore: widget.engine.semanticStore,
        currentHybrid: widget.engine.ranker,
        alternateHybrid: HybridRanker(
          lexicalWeight: alternateLexicalWeight,
          semanticWeight: alternateSemanticWeight,
          dualChannelBonus: alternateDualBonus,
        ),
      );
      const evaluator = RetrievalEvaluator();
      for (final strategy in RetrievalStrategy.values) {
        if (!mounted) return;
        setState(() => status = '运行 ${_label(strategy)}…');
        final results = await runner.runDataset(data, strategy);
        metrics[strategy] = evaluator.aggregate(data.cases, results);
      }
      if (!mounted) return;
      setState(() => status = '完成 · ${data.cases.length} cases');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e;
        status = '运行失败';
      });
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('检索基准 / A-B Lab')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (loading) const LinearProgressIndicator(),
            if (dataset != null) ...[
              Text(dataset!.name,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                '${dataset!.cases.length} 个带人工期望来源的本地 Golden cases · 指标只在真实运行后显示',
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
                      onPressed: dataset == null || running ? null : _run,
                      icon: const Icon(Icons.science_outlined),
                      label: Text(running ? status : '运行 A/B 检索基准'),
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
              'Hit@K / Recall / MRR / Context Precision 均为 DERIVED 指标；每个候选命中与排名来自真实 FTS5 / Embedding 运行。未运行时不显示占位百分比。',
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
    return Card(
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
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _metric('Hit@1', value.hitAt1),
                  _metric('Hit@3', value.hitAt3),
                  _metric('Recall@5', value.recallAt5),
                  _metric('MRR', value.mrr),
                  _metric('Context Precision', value.contextPrecision),
                ],
              ),
          ],
        ),
      ),
    );
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

  String _label(RetrievalStrategy strategy) => switch (strategy) {
        RetrievalStrategy.ftsOnly => 'A · FTS5 only',
        RetrievalStrategy.embeddingOnly => 'B · Embedding only',
        RetrievalStrategy.hybrid => 'C · Current Hybrid',
        RetrievalStrategy.alternateHybrid => 'D · Alternate Hybrid',
      };
}
