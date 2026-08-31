import 'package:flutter/material.dart';

import '../../eval/retrieval_benchmark.dart';

class BenchmarkCaseDetailPage extends StatelessWidget {
  const BenchmarkCaseDetailPage({
    super.key,
    required this.benchmark,
    required this.result,
    this.baseline,
  });

  final RetrievalBenchmarkCase benchmark;
  final BenchmarkCaseResult result;
  final BenchmarkCaseResult? baseline;

  @override
  Widget build(BuildContext context) {
    final firstRelevant = result.hits.indexWhere(benchmark.isRelevant);
    final expectedRouter = benchmark.expectedUseKnowledge;
    final actualRouter = result.routerUseKnowledge;
    final cited = result.citedChunkIds;
    final baselineIds = baseline?.hits.map((hit) => hit.chunkId).toList();
    final actualIds = result.hits.map((hit) => hit.chunkId).toList();
    final rankingDiffers = baselineIds != null &&
        !_sameRanking(baselineIds, actualIds);
    return Scaffold(
      key: const ValueKey<String>('benchmark-case-detail-page'),
      appBar: AppBar(title: const Text('Benchmark Case 详情')),
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
                    Text(benchmark.question,
                        style: Theme.of(context).textTheme.titleMedium),
                    SelectableText(benchmark.id),
                    Text('tags · ${benchmark.tags.join(', ')}'),
                  ],
                ),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Expected · 人工标签',
                        style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      'documents · '
                      '${benchmark.expectedDocumentIds.isEmpty ? '未设置' : benchmark.expectedDocumentIds.join(', ')}',
                    ),
                    Text(
                      'chunks · '
                      '${benchmark.expectedChunkIds.isEmpty ? '未设置' : benchmark.expectedChunkIds.join(', ')}',
                    ),
                    if (benchmark.expectedSourceNames.isNotEmpty)
                      Text(
                        'sources · ${benchmark.expectedSourceNames.join(', ')}',
                      ),
                  ],
                ),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Actual ranks · REAL',
                        style: Theme.of(context).textTheme.titleSmall),
                    if (result.hits.isEmpty)
                      const Text('没有实际候选。')
                    else
                      for (var index = 0;
                          index < result.hits.length;
                          index++)
                        Text(
                          '#${index + 1} · ${result.hits[index].chunkId} · '
                          '${result.hits[index].documentId} · '
                          '${result.hits[index].sourceName}',
                        ),
                    Text(
                      'first relevant rank · '
                      '${firstRelevant < 0 ? '未命中' : firstRelevant + 1}',
                    ),
                    if (result.failureCode != null)
                      Text('failure · ${result.failureCode}'),
                    if (baseline != null)
                      Text(
                        rankingDiffers
                            ? 'ranking differs from ${baseline!.strategy.name}'
                            : 'ranking unchanged from ${baseline!.strategy.name}',
                      ),
                  ],
                ),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Optional observations',
                        style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      expectedRouter == null || actualRouter == null
                          ? 'Router Accuracy · 不可用'
                          : 'Router Accuracy · '
                              '${expectedRouter == actualRouter ? 'PASS' : 'FAIL'}',
                    ),
                    Text(
                      benchmark.expectedChunkIds.isEmpty || cited == null
                          ? 'Citation Grounding · 不可用'
                          : 'Citation Grounding · '
                              '${_grounding(cited).toStringAsFixed(1)}%',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _grounding(Set<String> cited) {
    if (cited.isEmpty) return 0;
    return cited.where(benchmark.expectedChunkIds.contains).length /
        cited.length *
        100;
  }

  bool _sameRanking(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
