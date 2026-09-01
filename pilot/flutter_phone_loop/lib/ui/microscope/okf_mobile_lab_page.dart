import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../../core/models.dart';
import '../../okf/okf_lab_corpus.dart';
import '../../okf/okf_models.dart';
import '../../okf/okf_retriever.dart';
import '../../services/knowledge_engine.dart';

class OkfMobileLabPage extends StatefulWidget {
  const OkfMobileLabPage({
    super.key,
    required this.engine,
  });

  final KnowledgeEngine engine;

  @override
  State<OkfMobileLabPage> createState() => _OkfMobileLabPageState();
}

class _OkfMobileLabPageState extends State<OkfMobileLabPage> {
  late final OkfLabRetriever retriever;
  int caseIndex = 0;
  final Map<OkfLabLane, _LaneRun> runs = <OkfLabLane, _LaneRun>{};
  final Set<OkfLabLane> running = <OkfLabLane>{};
  bool runningAll = false;

  @override
  void initState() {
    super.initState();
    retriever = OkfLabRetriever(
      bundle: buildFrTestOkfBundle(),
      ordinaryChunks: buildFrTestOrdinaryChunks(),
    );
  }

  OkfBenchmarkCase get benchmark => frTestBenchmarkCases[caseIndex];

  Future<void> _runLane(OkfLabLane lane) async {
    if (running.contains(lane)) return;
    setState(() {
      running.add(lane);
      runs.remove(lane);
    });

    final retrievalWatch = Stopwatch()..start();
    final retrieved = retriever.retrieve(
      benchmark.question,
      lane: lane,
      limit: 8,
    );
    retrievalWatch.stop();

    final evidence = <EvidenceItem>[
      for (var index = 0; index < retrieved.length && index < 4; index++)
        EvidenceItem(
          anchor: 'E${index + 1}',
          chunk: retrieved[index].chunk,
          score: retrieved[index].score,
        ),
    ];

    String answer;
    int? generationMs;
    bool? answerPass;
    bool? sourcePass;
    List<String> citedAnchors = const <String>[];

    if (!FlutterGemma.hasActiveModel()) {
      answer = '本地生成模型未 READY；检索证据已经计算完成。模型就绪后重新运行此 lane。';
    } else {
      final generationWatch = Stopwatch()..start();
      try {
        answer = await widget.engine.gemma.experimentalAnswer(
          question: benchmark.question,
          evidence: evidence,
          groundedOnly: lane != OkfLabLane.bareModel,
        );
        generationWatch.stop();
        generationMs = generationWatch.elapsedMilliseconds;
        answerPass = benchmark.answerPasses(answer);
        citedAnchors =
            widget.engine.citationResolver.extract(answer, evidence);
        if (lane != OkfLabLane.bareModel) {
          final citedSourceIds = <String>{};
          for (final anchor in citedAnchors) {
            final index = int.tryParse(anchor.substring(1));
            if (index == null || index <= 0 || index > retrieved.length) {
              continue;
            }
            citedSourceIds.addAll(retrieved[index - 1].sourceIds);
          }
          sourcePass = benchmark.expectedSourceIds.isEmpty ||
              benchmark.expectedSourceIds
                  .every((sourceId) => citedSourceIds.contains(sourceId));
        }
      } catch (error) {
        if (generationWatch.isRunning) generationWatch.stop();
        answer = '本地模型运行失败：$error';
      }
    }

    if (!mounted) return;
    setState(() {
      runs[lane] = _LaneRun(
        answer: answer,
        retrieved: retrieved,
        retrievalUs: retrievalWatch.elapsedMicroseconds,
        generationMs: generationMs,
        answerPass: answerPass,
        sourcePass: sourcePass,
        citedAnchors: citedAnchors,
        contextChars:
            evidence.fold<int>(0, (sum, item) => sum + item.chunk.text.length),
      );
      running.remove(lane);
    });
  }

  Future<void> _runAll() async {
    if (runningAll) return;
    setState(() => runningAll = true);
    try {
      for (final lane in OkfLabLane.values) {
        if (!mounted) return;
        await _runLane(lane);
      }
    } finally {
      if (mounted) setState(() => runningAll = false);
    }
  }

  void _selectCase(int value) {
    if (value == caseIndex || running.isNotEmpty || runningAll) return;
    setState(() {
      caseIndex = value;
      runs.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final modelReady = FlutterGemma.hasActiveModel();
    return Scaffold(
      key: const ValueKey<String>('okf-mobile-lab-page'),
      appBar: AppBar(
        title: const Text('OKF Mobile Lab'),
      ),
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
                      '单变量验证：模型固定，只改变知识层',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'A–F 全部调用同一个手机本地模型实例。内置 FR-Test-20260901 '
                      '为虚构专有语料，避免把预训练知识误判成 OKF 增益。',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      modelReady
                          ? '本地生成模型 · READY'
                          : '本地生成模型 · NOT READY（仍可检查检索证据）',
                    ),
                    const Text(
                      '注意：运行全部 A–F 会连续进行 6 次本地生成，可能明显增加发热；'
                      '也可以逐 lane 运行。',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Benchmark',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    DropdownButton<int>(
                      isExpanded: true,
                      value: caseIndex,
                      items: [
                        for (var index = 0;
                            index < frTestBenchmarkCases.length;
                            index++)
                          DropdownMenuItem<int>(
                            value: index,
                            child: Text(
                              frTestBenchmarkCases[index].question,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: running.isEmpty && !runningAll
                          ? (value) {
                              if (value != null) _selectCase(value);
                            }
                          : null,
                    ),
                    Text(benchmark.note),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      key: const ValueKey<String>('okf-run-all'),
                      onPressed: running.isEmpty && !runningAll
                          ? _runAll
                          : null,
                      icon: const Icon(Icons.play_circle_outline),
                      label: Text(runningAll ? 'A–F 运行中…' : '运行全部 A–F'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final lane in OkfLabLane.values) ...[
              _laneCard(context, lane),
              const SizedBox(height: 8),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '实现复用：OKF v0.2 字段/图/信任语义对齐 Google 官方规范；'
                  '读侧架构参考 W4G1/okf-core、okfctl、serradura/okf 与 OpenWiki。'
                  '首版不引入 Rust/Go/Node/Ruby runtime，避免改变现有 Android 推理栈。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _laneCard(BuildContext context, OkfLabLane lane) {
    final preview = retriever.retrieve(
      benchmark.question,
      lane: lane,
      limit: 8,
    );
    final run = runs[lane];
    final isRunning = running.contains(lane);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  child: Text(lane.code),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    lane.label,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (lane == OkfLabLane.okfTrustFreshness)
                  const Chip(label: Text('FULL OKF')),
              ],
            ),
            const SizedBox(height: 4),
            Text(lane.detail),
            const SizedBox(height: 8),
            if (preview.isEmpty)
              const Text('Evidence preview · 无外部证据')
            else ...[
              Text('Evidence preview · ${preview.length} candidates'),
              const SizedBox(height: 4),
              for (final item in preview.take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '• ${item.conceptId} · '
                    '${item.graphExpanded ? 'GRAPH' : 'DIRECT'} · '
                    '${_trustLabel(item.trustTier)} · '
                    'score=${item.score.toStringAsFixed(2)}',
                  ),
                ),
            ],
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              key: ValueKey<String>('okf-run-${lane.code}'),
              onPressed: isRunning || runningAll ? null : () => _runLane(lane),
              icon: const Icon(Icons.smart_toy_outlined),
              label: Text(isRunning ? '本地模型运行中…' : '运行 ${lane.code}'),
            ),
            if (run != null) ...[
              const Divider(height: 20),
              SelectableText(run.answer),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Chip(label: Text('检索 ${run.retrievalUs} µs')),
                  Chip(label: Text('Context ${run.contextChars} chars')),
                  if (run.generationMs != null)
                    Chip(label: Text('总生成 ${run.generationMs} ms')),
                  if (run.answerPass != null)
                    Chip(
                      label: Text(
                        run.answerPass! ? '答案 PASS' : '答案 FAIL',
                      ),
                    ),
                  if (run.sourcePass != null)
                    Chip(
                      label: Text(
                        run.sourcePass! ? '来源 PASS' : '来源 FAIL',
                      ),
                    ),
                ],
              ),
              if (run.citedAnchors.isNotEmpty)
                Text('Citations · ${run.citedAnchors.join(', ')}'),
              if (run.retrieved.isNotEmpty) ...[
                const SizedBox(height: 6),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('查看实际送入模型的证据'),
                  children: [
                    for (var index = 0;
                        index < run.retrieved.length && index < 4;
                        index++)
                      ListTile(
                        dense: true,
                        title: Text(
                          '[E${index + 1}] ${run.retrieved[index].chunk.sourceName}',
                        ),
                        subtitle: Text(run.retrieved[index].chunk.text),
                      ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _trustLabel(OkfTrustTier? value) => switch (value) {
        OkfTrustTier.humanReviewed => 'human-reviewed',
        OkfTrustTier.machineConfirmed => 'machine-confirmed',
        OkfTrustTier.unverified => 'unverified',
        null => 'no-okf-metadata',
      };
}

class _LaneRun {
  const _LaneRun({
    required this.answer,
    required this.retrieved,
    required this.retrievalUs,
    required this.generationMs,
    required this.answerPass,
    required this.sourcePass,
    required this.citedAnchors,
    required this.contextChars,
  });

  final String answer;
  final List<OkfLabRetrievalResult> retrieved;
  final int retrievalUs;
  final int? generationMs;
  final bool? answerPass;
  final bool? sourcePass;
  final List<String> citedAnchors;
  final int contextChars;
}
