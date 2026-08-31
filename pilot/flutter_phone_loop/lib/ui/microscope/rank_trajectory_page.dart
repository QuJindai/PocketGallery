import 'package:flutter/material.dart';

import '../../lineage/lineage_models.dart';
import '../../lineage/trace_snapshot.dart';
import 'lineage_formatters.dart';
import 'lineage_stage_widgets.dart';

class RankTrajectoryPage extends StatelessWidget {
  const RankTrajectoryPage({
    super.key,
    required this.snapshot,
    this.strategyId,
    this.lane,
  });

  final TraceSnapshot snapshot;
  final String? strategyId;
  final RetrievalLane? lane;

  @override
  Widget build(BuildContext context) {
    final candidates = snapshot.candidates
        .where(
          (candidate) =>
              (strategyId == null || candidate.strategyId == strategyId) &&
              (lane == null || candidate.lane == lane),
        )
        .toList(growable: false);
    final evidenceByCandidate = <String, EvidenceRecord>{
      for (final evidence in snapshot.evidence)
        if ((strategyId == null || evidence.strategyId == strategyId) &&
            (lane == null || evidence.lane == lane))
          evidence.candidateId: evidence,
    };
    return LineageDetailScaffold(
      pageKey: 'rank-trajectory-page',
      title: '融合 / 重排轨迹',
      snapshot: snapshot,
      truthKinds: const <TruthKind>{TruthKind.real, TruthKind.derived},
      lane: lane ?? RetrievalLane.active,
      children: [
        const LineageSectionCard(
          title: 'Rank Flow · DERIVED from captured ranks',
          child: Text('FTS / Vector → Fusion → Rerank → Evidence'),
        ),
        LineageSectionCard(
          title: '候选排名移动',
          child: candidates.isEmpty
              ? const EmptyFact('没有候选排名可绘制。')
              : Column(
                  children: [
                    if (candidates
                        .every((candidate) => candidate.rerankRank == null))
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('重排未运行'),
                      ),
                    for (final candidate in candidates)
                      Card.outlined(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                candidate.chunkId,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'FTS #${candidate.ftsRank ?? '—'} · '
                                'Vector #${candidate.vectorRank ?? '—'} → '
                                'Fusion #${candidate.fusionRank ?? '—'} → '
                                'Rerank #${candidate.rerankRank ?? '—'} → '
                                '${evidenceByCandidate[candidate.candidateId]?.anchor == null ? '未进入 Evidence' : 'Evidence ${evidenceByCandidate[candidate.candidateId]!.anchor}'}',
                              ),
                              Text(
                                'BM25 ${formatNumber(candidate.rawBm25)} · '
                                'cos ${formatNumber(candidate.rawCosine)} · '
                                'fusion ${formatNumber(candidate.fusionScore)} · '
                                'rerank ${formatNumber(candidate.rerankScore)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
