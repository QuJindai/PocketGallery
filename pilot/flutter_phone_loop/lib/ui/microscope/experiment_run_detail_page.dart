import 'dart:convert';

import 'package:flutter/material.dart';

import '../../lineage/lineage_models.dart';
import '../../lineage/lineage_store.dart';
import '../../lineage/trace_snapshot.dart';
import 'candidate_pool_page.dart';
import 'evidence_context_page.dart';
import 'rank_trajectory_page.dart';

class ExperimentRunDetailPage extends StatefulWidget {
  const ExperimentRunDetailPage({
    super.key,
    required this.store,
    required this.traceId,
    required this.strategyId,
    required this.experimentRunId,
  });

  final LineageStore store;
  final String traceId;
  final String strategyId;
  final String experimentRunId;

  @override
  State<ExperimentRunDetailPage> createState() =>
      _ExperimentRunDetailPageState();
}

class _ExperimentRunDetailPageState extends State<ExperimentRunDetailPage> {
  TraceSnapshot? snapshot;
  ExperimentRunRecord? run;
  List<RerankFeatureRecord> features = const <RerankFeatureRecord>[];
  bool loading = true;
  Object? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final loadedSnapshot = await TraceSnapshot.load(
        widget.store,
        widget.traceId,
      );
      final loadedRun = await widget.store.experimentRunById(
        widget.experimentRunId,
      );
      final loadedFeatures = await widget.store.rerankFeaturesForTrace(
        widget.traceId,
        strategyId: widget.strategyId,
        lane: RetrievalLane.shadow,
      );
      if (!mounted) return;
      setState(() {
        snapshot = loadedSnapshot;
        run = loadedRun;
        features = loadedFeatures;
      });
    } catch (caught) {
      if (mounted) setState(() => error = caught);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = snapshot;
    final record = run;
    return Scaffold(
      key: const ValueKey<String>('experiment-run-detail-page'),
      appBar: AppBar(title: const Text('ACTIVE / SHADOW 对照')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (loading) const LinearProgressIndicator(),
              if (error != null) Text('实验详情读取失败：$error'),
              if (!loading && record == null)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('指定实验运行不存在。'),
                  ),
                ),
              if (data != null && record != null) ...[
                _runCard(context, record),
                _comparisonCard(context, data),
                _evidenceCard(context, data),
                _featureCard(context),
                _drillDownCard(context, data),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _runCard(BuildContext context, ExperimentRunRecord record) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Chip(label: Text('ACTIVE')),
              const SizedBox(width: 6),
              const Chip(label: Text('SHADOW')),
              const Spacer(),
              Text('${record.completedItems}/${record.totalItems}'),
            ],
          ),
          SelectableText(record.experimentRunId),
          Text(widget.strategyId),
          Text(
            record.status == ExperimentRunStatus.failed
                ? 'SHADOW FAILED · ${record.failureCode ?? '原因未捕获'}'
                : 'SHADOW ${record.status.name.toUpperCase()}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (record.failureDetail != null) Text(record.failureDetail!),
          if (record.metricJson != null)
            Text('metrics · ${_pretty(record.metricJson!)}'),
        ],
      ),
    ),
  );

  Widget _comparisonCard(BuildContext context, TraceSnapshot data) {
    final active = data.candidatesFor(
      strategyId: data.trace.activeStrategyId,
      lane: RetrievalLane.active,
    );
    final shadow = data.candidatesFor(
      strategyId: widget.strategyId,
      lane: RetrievalLane.shadow,
    );
    final activeById = <String, CandidateRecord>{
      for (final candidate in active) candidate.chunkId: candidate,
    };
    final shadowById = <String, CandidateRecord>{
      for (final candidate in shadow) candidate.chunkId: candidate,
    };
    final added =
        shadowById.keys.toSet().difference(activeById.keys.toSet()).toList()
          ..sort();
    final removed =
        activeById.keys.toSet().difference(shadowById.keys.toSet()).toList()
          ..sort();
    final changed =
        activeById.keys
            .where(
              (id) =>
                  shadowById.containsKey(id) &&
                  activeById[id]!.finalRank != shadowById[id]!.finalRank,
            )
            .toList()
          ..sort();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Candidate delta · DERIVED',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(
              'added ${added.length} · removed ${removed.length} · '
              'rank changed ${changed.length}',
            ),
            if (added.isNotEmpty) Text('added · ${added.join(', ')}'),
            if (removed.isNotEmpty) Text('removed · ${removed.join(', ')}'),
            for (final id in changed)
              Text(
                '$id · ACTIVE #${activeById[id]!.finalRank ?? '—'} → '
                'SHADOW #${shadowById[id]!.finalRank ?? '—'}',
              ),
          ],
        ),
      ),
    );
  }

  Widget _evidenceCard(BuildContext context, TraceSnapshot data) {
    final active = data
        .evidenceFor(
          strategyId: data.trace.activeStrategyId,
          lane: RetrievalLane.active,
        )
        .map((item) => item.chunkId)
        .toSet();
    final shadow = data
        .evidenceFor(strategyId: widget.strategyId, lane: RetrievalLane.shadow)
        .map((item) => item.chunkId)
        .toSet();
    final changed =
        active.difference(shadow).isNotEmpty ||
        shadow.difference(active).isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Evidence delta · DERIVED',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(changed ? 'Evidence changed' : 'Evidence unchanged'),
            Text('ACTIVE · ${active.join(', ')}'),
            Text('SHADOW · ${shadow.join(', ')}'),
            const Text('SHADOW Evidence 不进入回答 Prompt。'),
          ],
        ),
      ),
    );
  }

  Widget _featureCard(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rerank contributions · DERIVED',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (features.isEmpty)
            const Text('该策略未持久化特征重排贡献。')
          else
            for (final feature in features)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(feature.chunkId),
                subtitle: Text(_pretty(feature.contributionJson)),
                trailing: Text(feature.rerankScore.toStringAsFixed(3)),
              ),
        ],
      ),
    ),
  );

  Widget _drillDownCard(BuildContext context, TraceSnapshot data) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SHADOW 下钻', style: Theme.of(context).textTheme.titleSmall),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                key: const ValueKey<String>('experiment-candidates'),
                onPressed: () => _push(
                  CandidatePoolPage(
                    snapshot: data,
                    strategyId: widget.strategyId,
                    lane: RetrievalLane.shadow,
                  ),
                ),
                child: const Text('候选池'),
              ),
              OutlinedButton(
                key: const ValueKey<String>('experiment-ranks'),
                onPressed: () => _push(
                  RankTrajectoryPage(
                    snapshot: data,
                    strategyId: widget.strategyId,
                    lane: RetrievalLane.shadow,
                  ),
                ),
                child: const Text('排名轨迹'),
              ),
              OutlinedButton(
                key: const ValueKey<String>('experiment-evidence'),
                onPressed: () => _push(
                  EvidenceContextPage(
                    snapshot: data,
                    strategyId: widget.strategyId,
                    lane: RetrievalLane.shadow,
                  ),
                ),
                child: const Text('Evidence'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Future<void> _push(Widget page) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
  }

  String _pretty(String value) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(value));
    } catch (_) {
      return value;
    }
  }
}
