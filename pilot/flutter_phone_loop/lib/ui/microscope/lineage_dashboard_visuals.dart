import 'package:flutter/material.dart';

import '../../lineage/lineage_models.dart';
import '../../lineage/trace_snapshot.dart';
import 'lineage_formatters.dart';

class TraceWaterfallEntry {
  const TraceWaterfallEntry({
    required this.stage,
    required this.kind,
    required this.durationUs,
    required this.fractionOfKnownDuration,
  });

  final String stage;
  final String kind;
  final int? durationUs;
  final double? fractionOfKnownDuration;

  String get durationLabel => formatDurationUs(durationUs);
}

class TraceWaterfallModel {
  const TraceWaterfallModel({
    required this.entries,
    required this.totalKnownDurationUs,
  });

  final List<TraceWaterfallEntry> entries;
  final int totalKnownDurationUs;

  factory TraceWaterfallModel.fromEvents(List<TraceEventRecord> events) {
    final timed = events
        .where(
          (event) =>
              event.kind != 'trace.started' &&
              event.kind != 'trace.completed' &&
              event.kind != 'trace.failed',
        )
        .toList(growable: false);
    final total = timed.fold<int>(
      0,
      (sum, event) => sum + (event.durationUs ?? 0),
    );
    return TraceWaterfallModel(
      entries: <TraceWaterfallEntry>[
        for (final event in timed)
          TraceWaterfallEntry(
            stage: event.stage,
            kind: event.kind,
            durationUs: event.durationUs,
            fractionOfKnownDuration: event.durationUs == null || total == 0
                ? null
                : event.durationUs! / total,
          ),
      ],
      totalKnownDurationUs: total,
    );
  }
}

class TraceWaterfallCard extends StatelessWidget {
  const TraceWaterfallCard({super.key, required this.events});

  final List<TraceEventRecord> events;

  @override
  Widget build(BuildContext context) {
    final model = TraceWaterfallModel.fromEvents(events);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Trace 时间瀑布',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (model.entries.isEmpty)
              const Text('当前 Trace 没有可展示的阶段事件。')
            else
              for (final entry in model.entries) ...[
                Row(
                  children: [
                    SizedBox(
                      width: 78,
                      child: Text(
                        entry.stage,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      child: entry.fractionOfKnownDuration == null
                          ? const Align(
                              alignment: Alignment.centerLeft,
                              child: Text('时延未捕获'),
                            )
                          : FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: entry.fractionOfKnownDuration!
                                  .clamp(0.04, 1)
                                  .toDouble(),
                              child: Container(
                                height: 12,
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(width: 72, child: Text(entry.durationLabel)),
                  ],
                ),
                const SizedBox(height: 7),
              ],
            Text(
              model.totalKnownDurationUs == 0
                  ? '已捕获阶段总时延：未捕获'
                  : '已捕获阶段总时延：${formatDurationUs(model.totalKnownDurationUs)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class LineageGraphCard extends StatelessWidget {
  const LineageGraphCard({super.key, required this.snapshot});

  final TraceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final hasSource = snapshot.documentsById.isNotEmpty;
    final hasChunk = snapshot.chunksById.isNotEmpty;
    final hasEmbedding = snapshot.queryEmbedding != null ||
        snapshot.candidates.any((candidate) => candidate.embeddingId != null);
    final nodes = <({String label, bool captured})>[
      (label: '文档/页', captured: hasSource),
      (label: 'Chunk', captured: hasChunk),
      (label: 'Embedding', captured: hasEmbedding),
      (label: '候选', captured: snapshot.candidates.isNotEmpty),
      (label: 'Evidence', captured: snapshot.evidence.isNotEmpty),
      (label: 'Gemma', captured: snapshot.generation != null),
      (label: 'Citation', captured: snapshot.citations.isNotEmpty),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Lineage 血缘图',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var index = 0; index < nodes.length; index++) ...[
                    Chip(
                      avatar: Icon(
                        nodes[index].captured
                            ? Icons.check_circle_outline
                            : Icons.help_outline,
                        size: 17,
                      ),
                      label: Text(nodes[index].label),
                    ),
                    if (index + 1 < nodes.length)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.arrow_forward, size: 17),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 6),
            const Text('对象关系：Chunk → Embedding；二者不是同一个对象。'),
          ],
        ),
      ),
    );
  }
}

class ActiveShadowSummaryCard extends StatelessWidget {
  const ActiveShadowSummaryCard({super.key, required this.snapshot});

  final TraceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final active = snapshot.candidates
        .where((candidate) => candidate.lane == RetrievalLane.active)
        .length;
    final shadow = snapshot.candidates
        .where((candidate) => candidate.lane == RetrievalLane.shadow)
        .length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ACTIVE vs SHADOW',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('ACTIVE candidates $active')),
                Chip(label: Text('SHADOW candidates $shadow')),
                Chip(
                  label: Text(
                    'experiment runs ${snapshot.experimentRuns.length}',
                  ),
                ),
              ],
            ),
            if (snapshot.experimentRuns.isEmpty)
              const Text('尚未按需运行 SHADOW；普通聊天路径不会自动执行实验。'),
          ],
        ),
      ),
    );
  }
}
