import 'package:flutter/material.dart';

import '../../observability/retrieval_trace.dart';

class HybridRankLabPage extends StatelessWidget {
  const HybridRankLabPage({super.key, required this.trace});

  final RetrievalTrace trace;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hybrid 排名对照')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Text(trace.query, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Wrap(
              spacing: 8,
              children: [
                Chip(label: Text('REAL · FTS / Vector rank')),
                Chip(label: Text('DERIVED · RRF / Final score')),
              ],
            ),
            const SizedBox(height: 8),
            if (trace.hybridHits.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('本次 Trace 没有 Hybrid 候选。'),
                ),
              )
            else
              for (final hit in trace.hybridHits) _hitCard(context, hit),
          ],
        ),
      ),
    );
  }

  Widget _hitCard(BuildContext context, TraceHit hit) {
    final total = hit.rawScore ?? hit.normalizedScore;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  child: Text('${hit.rank}'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hit.sourceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text('${hit.locator} · ${hit.chunkId}'),
                    ],
                  ),
                ),
                Text(total.toStringAsFixed(5)),
              ],
            ),
            const Divider(),
            _row('FTS rank', hit.lexicalRank?.toString() ?? '—', 'REAL'),
            _row('Vector rank', hit.semanticRank?.toString() ?? '—', 'REAL'),
            _row(
              'Lexical contribution',
              _n(hit.lexicalContribution),
              'DERIVED',
            ),
            _row(
              'Semantic contribution',
              _n(hit.semanticContribution),
              'DERIVED',
            ),
            _row('Dual-channel bonus', _n(hit.dualChannelBonus), 'DERIVED'),
            _row('Exact-term bonus', _n(hit.exactTermBonus), 'DERIVED'),
            _row('Final score', total.toStringAsFixed(6), 'DERIVED'),
            const SizedBox(height: 6),
            Text('channels · ${hit.channel}'),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, String truth) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(value, style: const TextStyle(fontFeatures: [])),
            const SizedBox(width: 8),
            Text(truth, style: const TextStyle(fontSize: 11)),
          ],
        ),
      );

  String _n(double? value) => value == null ? '—' : value.toStringAsFixed(6);
}
