import 'dart:convert';

import 'package:flutter/material.dart';

import '../../lineage/trace_snapshot.dart';
import 'lineage_formatters.dart';
import 'lineage_stage_widgets.dart';

class FtsLineagePage extends StatelessWidget {
  const FtsLineagePage({super.key, required this.snapshot});

  final TraceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final events = snapshot.events
        .where((event) => event.stage == 'fts')
        .toList(growable: false);
    final candidates = snapshot.candidates
        .where((candidate) => candidate.ftsRank != null)
        .toList(growable: false);
    return LineageDetailScaffold(
      pageKey: 'fts-lineage-page',
      title: 'FTS5 词法 / BM25',
      snapshot: snapshot,
      children: [
        LineageSectionCard(
          title: '查询规范化',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('raw query · ${snapshot.trace.queryText}'),
              for (final event in events) ...[
                const SizedBox(height: 6),
                Text('${event.kind} · ${formatDurationUs(event.durationUs)}'),
                SelectableText(_prettyPayload(event.payloadJson)),
              ],
              if (events.isEmpty)
                const Text('本 Trace 未捕获 FTS 事件；不会重跑查询后标为 REAL。'),
            ],
          ),
        ),
        LineageSectionCard(
          title: '真实 BM25 排名',
          child: candidates.isEmpty
              ? const EmptyFact('没有 FTS 候选或 FTS 未运行。')
              : Column(
                  children: [
                    for (final candidate in candidates)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          child: Text('${candidate.ftsRank}'),
                        ),
                        title: Text(candidate.chunkId),
                        subtitle: Text(
                          'raw SQLite BM25 ${formatNumber(candidate.rawBm25)} · '
                          '${candidate.sourceChannels}',
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  String _prettyPayload(String value) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(value));
    } catch (_) {
      return 'payload 无法解析';
    }
  }
}
