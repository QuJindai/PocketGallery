import 'package:flutter/material.dart';

import '../../lineage/lineage_models.dart';
import '../../lineage/trace_snapshot.dart';
import '../../observability/trace_vector_space_service.dart';
import '../../services/knowledge_engine.dart';
import 'lineage_formatters.dart';
import 'lineage_stage_widgets.dart';
import 'vector_space_3d.dart';

class VectorSpacePage extends StatefulWidget {
  const VectorSpacePage({
    super.key,
    required this.engine,
    required this.snapshot,
  });

  final KnowledgeEngine engine;
  final TraceSnapshot snapshot;

  @override
  State<VectorSpacePage> createState() => _VectorSpacePageState();
}

class _VectorSpacePageState extends State<VectorSpacePage> {
  late final Future<TraceVectorSpaceSnapshot> future;

  @override
  void initState() {
    super.initState();
    future = TraceVectorSpaceService(
      lineageStore: widget.engine.lineageStore,
      lexicalStore: widget.engine.lexicalStore,
    ).build(widget.snapshot);
  }

  @override
  Widget build(BuildContext context) => LineageDetailScaffold(
    pageKey: 'vector-space-page',
    title: '向量空间 / Vector Space',
    snapshot: widget.snapshot,
    truthKinds: const <TruthKind>{TruthKind.real, TruthKind.derived},
    children: <Widget>[
      FutureBuilder<TraceVectorSpaceSnapshot>(
        future: future,
        builder: (context, value) {
          if (value.hasError) {
            return LineageSectionCard(
              title: '真实高维向量 → 三维 PCA',
              child: Text('不可用：${value.error}'),
            );
          }
          if (!value.hasData) return const LinearProgressIndicator();
          return TraceVectorSpaceView(data: value.data!);
        },
      ),
    ],
  );
}

class TraceVectorSpaceView extends StatefulWidget {
  const TraceVectorSpaceView({
    super.key,
    required this.data,
    this.onInteraction,
  });

  final TraceVectorSpaceSnapshot data;
  final ValueChanged<VectorInteractionEvent>? onInteraction;

  @override
  State<TraceVectorSpaceView> createState() => _TraceVectorSpaceViewState();
}

class _TraceVectorSpaceViewState extends State<TraceVectorSpaceView> {
  String? selectedId;

  TraceVectorSpaceSnapshot get data => widget.data;

  @override
  void initState() {
    super.initState();
    selectedId = _defaultSelectedId(data.points);
  }

  @override
  void didUpdateWidget(covariant TraceVectorSpaceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (selectedId == null ||
        !data.points.any((point) => point.embeddingId == selectedId)) {
      selectedId = _defaultSelectedId(data.points);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _firstWhereOrNull(data.points, (point) => point.isQuery);
    final selected =
        _firstWhereOrNull(
          data.points,
          (point) => point.embeddingId == selectedId,
        ) ??
        query ??
        data.points.firstOrNull;
    final top1 = data.neighbors.firstOrNull?.cosineToQuery;
    final top2 = data.neighbors.length > 1
        ? data.neighbors[1].cosineToQuery
        : null;
    final plotPoints = <VectorPlotPoint>[
      for (final point in data.points)
        VectorPlotPoint(
          id: point.embeddingId,
          x: point.x,
          y: point.y,
          z: point.z,
          kind: _plotKind(point),
          label: point.isQuery
              ? 'Query'
              : point.selectedForEvidence
              ? 'Evidence'
              : null,
        ),
    ];
    return Column(
      children: <Widget>[
        LineageSectionCard(
          title: '本轮查询 · REAL · ACTIVE',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SelectableText(query?.text ?? '查询文本未捕获'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  LineageMetric('Top1 cosine', formatNumber(top1)),
                  LineageMetric('Top2 cosine', formatNumber(top2)),
                  LineageMetric(
                    'Gap',
                    top1 == null || top2 == null
                        ? '未捕获'
                        : formatNumber(top1 - top2),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                data.usedCapturedQuery
                    ? '使用本轮已持久化 Query vector；没有重新调用 Embedding。'
                    : '本轮 Query vector 身份未能确认。',
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('开发者详情'),
                children: <Widget>[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      'embedding ${data.queryEmbeddingId}\n'
                      'sha256 ${data.queryVectorSha256}',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        LineageSectionCard(
          title: '真实高维向量 → 三维 PCA · DERIVED',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                '${data.originalDimension}D → 3D PCA',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 5),
              Text('解释方差 · ${_varianceSummary(data.explainedVarianceRatios)}'),
              const SizedBox(height: 3),
              Text('有效主成分 ${data.effectiveComponentCount}/3'),
              if (data.effectiveComponentCount < 3) ...<Widget>[
                const SizedBox(height: 8),
                _ProjectionWarning(
                  effectiveComponentCount: data.effectiveComponentCount,
                ),
              ],
              const SizedBox(height: 10),
              InteractiveVectorPlot(
                points: plotPoints,
                explainedVarianceRatios: data.explainedVarianceRatios,
                initialSelectedId: selected?.embeddingId,
                onPointSelected: (id) => setState(() => selectedId = id),
                onInteraction: widget.onInteraction,
              ),
              const SizedBox(height: 8),
              Text(
                '本轮真实向量 ${data.points.where((point) => !point.isQuery).length}/'
                '${data.totalPersistentBodyCount} · '
                '优先本轮候选，再按文档分层确定性补齐。',
              ),
              const SizedBox(height: 4),
              const Text('PCA 是高维关系的有损投影；真实检索顺序仍以 REAL cosine 和捕获排名为准。'),
              const SizedBox(height: 8),
              const Wrap(
                spacing: 8,
                runSpacing: 6,
                children: <Widget>[
                  Chip(label: Text('UMAP · 未启用')),
                  Chip(label: Text('t-SNE · 未启用')),
                ],
              ),
            ],
          ),
        ),
        if (selected != null) _TracePointDetail(point: selected),
        LineageSectionCard(
          title: '最近邻 · REAL cosine',
          child: data.neighbors.isEmpty
              ? const EmptyFact('本轮没有可显示的持久化邻居。')
              : Column(
                  children: <Widget>[
                    for (var index = 0; index < data.neighbors.length; index++)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(child: Text('${index + 1}')),
                        title: Text(data.neighbors[index].sourceName),
                        subtitle: Text(
                          '${data.neighbors[index].locator.isEmpty ? '位置未捕获' : data.neighbors[index].locator}\n'
                          '${_compactText(data.neighbors[index].text)}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          data.neighbors[index].cosineToQuery.toStringAsFixed(
                            4,
                          ),
                        ),
                        onTap: () => setState(
                          () => selectedId = data.neighbors[index].embeddingId,
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _TracePointDetail extends StatelessWidget {
  const _TracePointDetail({required this.point});

  final TraceVectorPoint point;

  @override
  Widget build(BuildContext context) {
    final role = point.isQuery
        ? '当前查询'
        : point.selectedForEvidence
        ? '已选 Evidence'
        : point.candidateId != null
        ? '检索候选'
        : '邻域语料';
    final reasonTitle = point.isQuery
        ? '投影角色'
        : point.selectedForEvidence
        ? '为何入选'
        : point.candidateId != null
        ? '为何未入选'
        : '为何显示';
    return LineageSectionCard(
      title: '点选详情 · $role',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            point.isQuery ? '本轮查询' : point.sourceName,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (!point.isQuery) ...<Widget>[
            const SizedBox(height: 3),
            Text(point.locator.isEmpty ? '位置未捕获' : point.locator),
          ],
          const SizedBox(height: 10),
          Text(
            point.isQuery ? '查询原文' : '切片原文',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          SelectableText(point.text.isEmpty ? '原文未捕获' : point.text),
          const SizedBox(height: 10),
          Text(reasonTitle, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 3),
          Text(_humanReason(point)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              LineageMetric(
                'REAL cosine',
                point.cosineToQuery.toStringAsFixed(4),
              ),
              LineageMetric('最终排名', _rank(point.finalRank)),
              LineageMetric('Vector 排名', _rank(point.vectorRank)),
              LineageMetric('FTS 排名', _rank(point.ftsRank)),
            ],
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('开发者详情'),
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  'embedding ${point.embeddingId}\n'
                  'chunk ${point.chunkId ?? '不适用'}\n'
                  'document ${point.documentId ?? '不适用'}\n'
                  'representation ${point.representation.name}\n'
                  'lane ${point.lane?.dbValue ?? 'SAMPLE'}\n'
                  'channels ${point.sourceChannels ?? '不适用'}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProjectionWarning extends StatelessWidget {
  const _ProjectionWarning({required this.effectiveComponentCount});

  final int effectiveComponentCount;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      effectiveComponentCount == 0
          ? '当前样本没有可解释方差，散点只表示同一退化位置。'
          : '当前数据只支撑 $effectiveComponentCount 维有效结构；其余主轴方差为零。',
    ),
  );
}

VectorPlotKind _plotKind(TraceVectorPoint point) {
  if (point.isQuery) return VectorPlotKind.query;
  if (point.selectedForEvidence) return VectorPlotKind.evidence;
  if (point.candidateId != null) return VectorPlotKind.candidate;
  return VectorPlotKind.context;
}

String? _defaultSelectedId(List<TraceVectorPoint> points) =>
    _firstWhereOrNull(
      points,
      (point) => point.selectedForEvidence,
    )?.embeddingId ??
    _firstWhereOrNull(points, (point) => point.isQuery)?.embeddingId ??
    points.firstOrNull?.embeddingId;

T? _firstWhereOrNull<T>(Iterable<T> values, bool Function(T) predicate) {
  for (final value in values) {
    if (predicate(value)) return value;
  }
  return null;
}

String _varianceSummary(List<double> ratios) {
  if (ratios.isEmpty) return '未捕获';
  return <String>[
    for (var index = 0; index < ratios.length && index < 3; index++)
      'PC${index + 1} ${(ratios[index] * 100).toStringAsFixed(1)}%',
  ].join(' · ');
}

String _humanReason(TraceVectorPoint point) {
  if (point.isQuery) {
    return '本轮持久化 Query vector，是整个三维投影的参照点。';
  }
  if (point.selectedForEvidence) {
    return switch (point.selectionReason) {
      'direct_support' => '直接支撑答案',
      'context_token_allocation' => '已分配回答上下文预算',
      'dynamic_evidence' => '通过动态证据选择',
      final String reason when reason.isNotEmpty => '运行时记录：$reason',
      _ => '已进入 Evidence；具体入选原因未捕获。',
    };
  }
  if (point.candidateId == null) {
    return '作为文档分层样本显示，用于理解查询附近的局部语义结构。';
  }
  return switch (point.dropReason) {
    'max_evidence' => '证据数量已达上限',
    'token_budget' => '超出回答上下文预算',
    'relative_score_cutoff' => '相关度低于动态阈值',
    'near_neighbor_duplicate' => '与已选证据过于重复',
    final String reason when reason.isNotEmpty => '运行时记录：$reason',
    _ => '本轮未选入 Evidence；具体拒绝原因未捕获。',
  };
}

String _rank(int? rank) => rank == null ? '未捕获' : '#$rank';

String _compactText(String text) {
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length <= 90) return normalized;
  return '${normalized.substring(0, 90)}…';
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
