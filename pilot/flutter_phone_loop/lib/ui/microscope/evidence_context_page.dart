import 'dart:convert';

import 'package:flutter/material.dart';

import '../../lineage/lineage_models.dart';
import '../../lineage/trace_snapshot.dart';
import 'lineage_formatters.dart';
import 'lineage_stage_widgets.dart';

class EvidenceContextPage extends StatelessWidget {
  const EvidenceContextPage({super.key, required this.snapshot});

  final TraceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final activeEvidence = snapshot.evidence
        .where((item) => item.lane == RetrievalLane.active)
        .toList(growable: false);
    final selectedCandidateIds = activeEvidence
        .map((item) => item.candidateId)
        .toSet();
    final dropped = snapshot.candidates
        .where(
          (candidate) =>
              candidate.lane == RetrievalLane.active &&
              !selectedCandidateIds.contains(candidate.candidateId),
        )
        .toList(growable: false);
    final budget = snapshot.budget;
    return LineageDetailScaffold(
      pageKey: 'evidence-context-page',
      title: '证据与上下文 / Evidence & Context',
      snapshot: snapshot,
      truthKinds: const <TruthKind>{TruthKind.real, TruthKind.derived},
      children: [
        LineageSectionCard(
          title: '选择的 Evidence',
          child: activeEvidence.isEmpty
              ? const EmptyFact('没有 ACTIVE Evidence。')
              : Column(
                  children: [
                    for (final evidence in activeEvidence)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          child: Text(evidence.anchor ?? '—'),
                        ),
                        title: Text(evidence.chunkId),
                        subtitle: Text(
                          '${evidence.tokenCount} tokens · '
                          '${evidence.selectionReason}',
                        ),
                        trailing: Text(formatNumber(evidence.score)),
                      ),
                  ],
                ),
        ),
        LineageSectionCard(
          title: '未进入 / 被裁剪候选',
          child: dropped.isEmpty
              ? const EmptyFact('没有被拒绝的持久化候选。')
              : Column(
                  children: [
                    for (final candidate in dropped)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(candidate.chunkId),
                        subtitle: Text(
                          candidate.dropReason ??
                              '未选入 Evidence；具体 drop reason 未捕获',
                        ),
                      ),
                  ],
                ),
        ),
        LineageSectionCard(
          title: 'Context Budget',
          child: budget == null
              ? const EmptyFact('Prompt budget 未捕获。')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        LineageMetric('System', '${budget.systemTokens}'),
                        LineageMetric('History', '${budget.historyTokens}'),
                        LineageMetric('Evidence', '${budget.evidenceTokens}'),
                        LineageMetric('Query', '${budget.queryTokens}'),
                        LineageMetric(
                          'Output Reserve',
                          '${budget.outputReserveTokens}',
                        ),
                        LineageMetric(
                          'Remaining',
                          '${budget.remainingTokens}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: budget.totalPrefillTokens / budget.modelContextLimit,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'prefill ${budget.totalPrefillTokens}/'
                      '${budget.modelContextLimit} · '
                      'trimmed history ${budget.trimmedHistoryMessages} · '
                      'trimmed evidence ${budget.trimmedEvidenceItems}',
                    ),
                    Text('trim detail · ${_prettyJson(budget.trimDetailJson)}'),
                  ],
                ),
        ),
      ],
    );
  }

  String _prettyJson(String value) {
    try {
      return jsonEncode(jsonDecode(value));
    } catch (_) {
      return '无法解析';
    }
  }
}
