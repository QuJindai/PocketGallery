import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../../okf/okf_af_benchmark.dart';
import '../../okf/okf_af_runner.dart';
import '../../services/knowledge_engine.dart';

class OkfAfBenchmarkPage extends StatefulWidget {
  const OkfAfBenchmarkPage({
    super.key,
    required this.engine,
  });

  final KnowledgeEngine engine;

  @override
  State<OkfAfBenchmarkPage> createState() => _OkfAfBenchmarkPageState();
}

class _OkfAfBenchmarkPageState extends State<OkfAfBenchmarkPage> {
  late final OkfAfRetriever retriever;
  late final OkfAfRunner runner;
  final Map<String, Map<OkfAfLane, OkfAfRunResult>> results =
      <String, Map<OkfAfLane, OkfAfRunResult>>{};
  int caseIndex = 0;
  OkfAfLane? runningLane;
  bool runningCurrent = false;
  bool runningFull = false;
  int fullCompleted = 0;
  String status = 'READY · 选择问题后运行 A–F';

  @override
  void initState() {
    super.initState();
    retriever = OkfAfRetriever(
      corpus: OkfAfCorpus.syntheticFrTest(),
      now: () => DateTime.utc(2026, 9, 5),
    );
    runner = OkfAfRunner(
      retriever: retriever,
      gemma: widget.engine.gemma,
      citationResolver: widget.engine.citationResolver,
    );
  }

  OkfAfBenchmarkCase get benchmark => okfAfBenchmarkCases[caseIndex];
  bool get busy => runningLane != null || runningCurrent || runningFull;

  Future<void> _runLane(OkfAfLane lane) async {
    if (runningLane != null || !FlutterGemma.hasActiveModel()) {
      if (!FlutterGemma.hasActiveModel() && mounted) {
        setState(() => status = '本地生成模型尚未 READY；检索预览仍可查看。');
      }
      return;
    }
    final currentCase = benchmark;
    setState(() {
      runningLane = lane;
      status = '${lane.code} ${lane.label} · 本地模型运行中';
    });
    try {
      final result = await runner.run(
        benchmarkCase: currentCase,
        lane: lane,
      );
      if (!mounted) return;
      setState(() {
        results.putIfAbsent(currentCase.id, () => <OkfAfLane, OkfAfRunResult>{})[lane] = result;
        status = '${lane.code} 完成 · '
            '${result.answerPass ? '答案 PASS' : '答案 FAIL'}'
            '${result.sourcePass == null ? '' : result.sourcePass! ? ' · 来源 PASS' : ' · 来源 FAIL'}';
      });
    } catch (error) {
      if (mounted) setState(() => status = '${lane.code} 运行失败：$error');
    } finally {
      if (mounted) setState(() => runningLane = null);
    }
  }

  Future<void> _runCurrent() async {
    if (busy || !FlutterGemma.hasActiveModel()) {
      if (!FlutterGemma.hasActiveModel()) {
        setState(() => status = '本地生成模型尚未 READY，不能运行生成对照。');
      }
      return;
    }
    setState(() {
      runningCurrent = true;
      status = '当前问题 A–F · 0/6';
    });
    try {
      for (var index = 0; index < OkfAfLane.values.length; index++) {
        final lane = OkfAfLane.values[index];
        final result = await runner.run(
          benchmarkCase: benchmark,
          lane: lane,
        );
        if (!mounted) return;
        setState(() {
          results.putIfAbsent(benchmark.id, () => <OkfAfLane, OkfAfRunResult>{})[lane] = result;
          status = '当前问题 A–F · ${index + 1}/6';
        });
      }
      if (mounted) setState(() => status = '当前问题 A–F 完成 · 可直接比较 B→C→D→E→F 增益');
    } catch (error) {
      if (mounted) setState(() => status = 'A–F 运行中断：$error');
    } finally {
      if (mounted) setState(() => runningCurrent = false);
    }
  }

  Future<void> _runFull() async {
    if (busy || !FlutterGemma.hasActiveModel()) {
      if (!FlutterGemma.hasActiveModel()) {
        setState(() => status = '本地生成模型尚未 READY，不能运行完整基准。');
      }
      return;
    }
    setState(() {
      runningFull = true;
      fullCompleted = 0;
      status = '完整基准 · 0/24';
    });
    try {
      for (final currentCase in okfAfBenchmarkCases) {
        for (final lane in OkfAfLane.values) {
          final result = await runner.run(
            benchmarkCase: currentCase,
            lane: lane,
          );
          if (!mounted) return;
          setState(() {
            results.putIfAbsent(currentCase.id, () => <OkfAfLane, OkfAfRunResult>{})[lane] = result;
            fullCompleted += 1;
            status = '完整基准 · $fullCompleted/24';
          });
        }
      }
      if (mounted) setState(() => status = '完整基准完成 · 4题 × 6 lane');
    } catch (error) {
      if (mounted) setState(() => status = '完整基准中断：$error');
    } finally {
      if (mounted) setState(() => runningFull = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final modelReady = FlutterGemma.hasActiveModel();
    return Scaffold(
      key: const ValueKey<String>('okf-af-benchmark-page'),
      appBar: AppBar(title: const Text('OKF A–F 能力验证')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '同一模型 · 同一事实 · 只改变知识层',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '内置 FR-Test-20260901 虚构产线，避免把模型预训练知识误判成 OKF 增益。'
                      'A→B 测知识库收益；B→C→D→E→F 才是 OKF 的增量收益。',
                    ),
                    const SizedBox(height: 6),
                    Text(modelReady ? '本地模型 · READY' : '本地模型 · NOT READY'),
                    Text(status),
                    if (runningFull)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(value: fullCompleted / 24),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            _benchmarkSelector(context),
            const SizedBox(height: 8),
            _summaryCard(context),
            const SizedBox(height: 8),
            for (final lane in OkfAfLane.values) ...[
              _laneCard(context, lane),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _benchmarkSelector(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Benchmark', style: Theme.of(context).textTheme.titleSmall),
              DropdownButton<int>(
                isExpanded: true,
                value: caseIndex,
                items: [
                  for (var index = 0; index < okfAfBenchmarkCases.length; index++)
                    DropdownMenuItem<int>(
                      value: index,
                      child: Text(
                        okfAfBenchmarkCases[index].question,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: busy
                    ? null
                    : (value) {
                        if (value != null) setState(() => caseIndex = value);
                      },
              ),
              Text('${benchmark.category} · ${benchmark.note}'),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const ValueKey<String>('okf-af-run-current'),
                onPressed: busy ? null : _runCurrent,
                icon: const Icon(Icons.play_circle_outline),
                label: Text(runningCurrent ? 'A–F 运行中…' : '运行当前问题 A–F'),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                key: const ValueKey<String>('okf-af-run-full'),
                onPressed: busy ? null : _runFull,
                icon: const Icon(Icons.speed_outlined),
                label: Text(runningFull ? '完整基准运行中…' : '完整基准 · 4题 × A–F'),
              ),
              const SizedBox(height: 4),
              const Text(
                '完整基准会连续进行24次本地生成，适合最终定量；首次验证建议先跑“当前问题 A–F”。',
              ),
            ],
          ),
        ),
      );

  Widget _summaryCard(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('能力跃迁总表', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              const Text('答案率 / 来源率越高越好；Context / TTFT 越低越好。'),
              const SizedBox(height: 8),
              for (final lane in OkfAfLane.values) _summaryRow(lane),
            ],
          ),
        ),
      );

  Widget _summaryRow(OkfAfLane lane) {
    final laneResults = <OkfAfRunResult>[
      for (final caseResults in results.values)
        if (caseResults[lane] != null) caseResults[lane]!,
    ];
    if (laneResults.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text('${lane.code} ${lane.label} · 未运行'),
      );
    }
    final answerPass = laneResults.where((item) => item.answerPass).length;
    final sourceMeasured = laneResults.where((item) => item.sourcePass != null).toList();
    final sourcePass = sourceMeasured.where((item) => item.sourcePass == true).length;
    final avgContext = laneResults.fold<int>(0, (sum, item) => sum + item.contextTokens) ~/ laneResults.length;
    final ttfts = laneResults.map((item) => item.generation.ttftMs).whereType<int>().toList();
    final avgTtft = ttfts.isEmpty ? null : ttfts.reduce((a, b) => a + b) ~/ ttfts.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(
        '${lane.code} ${lane.label} · 答案 $answerPass/${laneResults.length} · '
        '来源 ${sourceMeasured.isEmpty ? 'N/A' : '$sourcePass/${sourceMeasured.length}'} · '
        'Context $avgContext tok · TTFT ${avgTtft == null ? 'N/A' : '${avgTtft}ms'}',
      ),
    );
  }

  Widget _laneCard(BuildContext context, OkfAfLane lane) {
    final preview = retriever.retrieve(benchmark.question, lane: lane, limit: 8);
    final result = results[benchmark.id]?[lane];
    final laneRunning = runningLane == lane;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(radius: 16, child: Text(lane.code)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(lane.label, style: Theme.of(context).textTheme.titleSmall),
                ),
                if (lane == OkfAfLane.okfTrustFreshness)
                  const Chip(label: Text('FULL OKF')),
              ],
            ),
            const SizedBox(height: 5),
            Text(lane.hypothesis),
            const SizedBox(height: 6),
            if (preview.isEmpty)
              const Text('Evidence preview · 0（裸模型）')
            else ...[
              Text('Evidence preview · ${preview.length} candidates'),
              for (final item in preview.take(4))
                Text(
                  '• ${item.conceptId} · ${item.graphExpanded ? 'GRAPH' : 'DIRECT'} · '
                  '${item.trustLabel}/${item.freshnessLabel} · ${item.score.toStringAsFixed(2)}',
                ),
            ],
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              key: ValueKey<String>('okf-af-run-${lane.code}'),
              onPressed: busy ? null : () => _runLane(lane),
              icon: const Icon(Icons.smart_toy_outlined),
              label: Text(laneRunning ? '本地模型运行中…' : '运行 ${lane.code}'),
            ),
            if (result != null) ...[
              const Divider(height: 20),
              SelectableText(result.answer),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Chip(label: Text(result.answerPass ? '答案 PASS' : '答案 FAIL')),
                  if (result.sourcePass != null)
                    Chip(label: Text(result.sourcePass! ? '来源 PASS' : '来源 FAIL')),
                  Chip(label: Text('检索 ${result.retrievalUs}µs')),
                  Chip(label: Text('Context ${result.contextTokens} tok')),
                  Chip(label: Text('TTFT ${result.generation.ttftMs ?? -1}ms')),
                  Chip(label: Text('生成 ${result.generation.generationMs}ms')),
                  if (result.generation.decodeTokensPerSecond != null)
                    Chip(
                      label: Text(
                        '${result.generation.decodeTokensPerSecond!.toStringAsFixed(1)} tok/s',
                      ),
                    ),
                ],
              ),
              if (result.citedAnchors.isNotEmpty)
                Text('Citations · ${result.citedAnchors.join(', ')}'),
              if (result.retrieved.isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('查看实际送入模型的证据'),
                  children: [
                    for (var index = 0; index < result.retrieved.length && index < 4; index++)
                      ListTile(
                        dense: true,
                        title: Text('[E${index + 1}] ${result.retrieved[index].chunk.sourceName}'),
                        subtitle: Text(result.retrieved[index].chunk.text),
                      ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}
