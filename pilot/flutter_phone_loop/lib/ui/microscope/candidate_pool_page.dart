import 'package:flutter/material.dart';

import '../../lineage/lineage_models.dart';
import '../../lineage/trace_snapshot.dart';
import 'lineage_formatters.dart';
import 'lineage_stage_widgets.dart';

class CandidatePoolPage extends StatelessWidget {
  const CandidatePoolPage({super.key, required this.snapshot});

  final TraceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final candidates = snapshot.candidates;
    final ftsOnly = candidates
        .where((candidate) => candidate.ftsRank != null && candidate.vectorRank == null)
        .length;
    final vectorOnly = candidates
        .where((candidate) => candidate.ftsRank == null && candidate.vectorRank != null)
        .length;
    final dual = candidates
        .where((candidate) => candidate.ftsRank != null && candidate.vectorRank != null)
        .length;
    final parentChild = candidates
        .where((candidate) => candidate.sourceChannels.contains('parent-child'))
        .length;
    final selected = candidates.where((candidate) => candidate.selectedForEvidence).length;
    final dropped = candidates.where((candidate) => candidate.dropReason != null).length;
    return LineageDetailScaffold(
      pageKey: 'candidate-pool-page',
      title: '候选池 / Candidate Pool',
      snapshot: snapshot,
      children: [
        LineageSectionCard(
          title: '通道交集',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FTS-only $ftsOnly · vector-only $vectorOnly · '
                'dual-channel $dual · parent-child $parentChild · '
                'selected $selected · dropped $dropped',
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  LineageMetric('FTS only', '$ftsOnly'),
                  LineageMetric('Vector only', '$vectorOnly'),
                  LineageMetric('双通道', '$dual'),
                  LineageMetric('父子提升', '$parentChild'),
                ],
              ),
            ],
          ),
        ),
        LineageSectionCard(
          title: '候选明细 · REAL',
          child: candidates.isEmpty
              ? const EmptyFact('候选记录未捕获。')
              : Column(
                  children: [
                    for (final candidate in candidates)
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(candidate.chunkId),
                        subtitle: Text(
                          '${candidate.lane.dbValue} · '
                          '${candidate.sourceChannels} · '
                          'final #${candidate.finalRank ?? '未捕获'} · '
                          '${candidate.selectedForEvidence ? 'selected' : 'not selected'}',
                        ),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'FTS #${candidate.ftsRank ?? '—'} '
                              'BM25 ${formatNumber(candidate.rawBm25)} · '
                              'Vector #${candidate.vectorRank ?? '—'} '
                              'cos ${formatNumber(candidate.rawCosine)}\n'
                              'embedding ${candidate.embeddingId ?? '未关联'} · '
                              'drop ${candidate.dropReason ?? '未丢弃'}',
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
