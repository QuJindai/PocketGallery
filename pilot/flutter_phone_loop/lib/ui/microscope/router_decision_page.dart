import 'package:flutter/material.dart';

import '../../lineage/trace_snapshot.dart';
import 'lineage_formatters.dart';
import 'lineage_stage_widgets.dart';

class RouterDecisionPage extends StatelessWidget {
  const RouterDecisionPage({super.key, required this.snapshot});

  final TraceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final router = snapshot.activeRouter;
    return LineageDetailScaffold(
      pageKey: 'router-decision-page',
      title: '路由决策 / Auto Router',
      snapshot: snapshot,
      children: [
        LineageSectionCard(
          title: '最终决策',
          child: router == null
              ? const EmptyFact('路由决策未捕获。')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      router.finalUseKnowledge
                          ? 'Auto → Knowledge'
                          : 'Auto → Model',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text('${router.decisionReason} · ${router.ruleProfile}'),
                  ],
                ),
        ),
        if (router != null)
          LineageSectionCard(
            title: '规则评估表 · REAL',
            child: Table(
              columnWidths: const <int, TableColumnWidth>{
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(1.4),
                2: FlexColumnWidth(1),
              },
              children: [
                _row(
                  'FTS hit count',
                  '${router.ftsHitCount}',
                  router.lexicalGatePass,
                ),
                _row(
                  'Top1 cosine',
                  formatNumber(router.top1Cosine),
                  router.semanticStrengthGatePass,
                ),
                _row(
                  'Top1–Top2 gap',
                  formatNumber(router.top1Top2Gap),
                  router.semanticGapGatePass,
                ),
                _row(
                  'dual-channel',
                  '${router.dualChannel}',
                  router.dualChannel,
                ),
              ],
            ),
          ),
        const LineageSectionCard(
          title: '阈值说明',
          child: Text(
            '本页展示运行时捕获值与 PASS/FAIL。阈值由已记录 rule profile 定义；'
            '若事件未单独暴露阈值，不会在这里补造数字。',
          ),
        ),
      ],
    );
  }

  TableRow _row(String name, String value, bool pass) => TableRow(
    children: [
      Padding(padding: const EdgeInsets.all(6), child: Text(name)),
      Padding(padding: const EdgeInsets.all(6), child: Text(value)),
      Padding(
        padding: const EdgeInsets.all(6),
        child: Text(pass ? 'PASS' : 'FAIL'),
      ),
    ],
  );
}
