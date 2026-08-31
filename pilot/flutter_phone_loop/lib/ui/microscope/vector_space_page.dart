import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../lineage/lineage_models.dart';
import '../../lineage/trace_snapshot.dart';
import '../../observability/trace_vector_space_service.dart';
import '../../services/knowledge_engine.dart';
import 'lineage_formatters.dart';
import 'lineage_stage_widgets.dart';

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
  bool use3d = false;

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
        children: [
          FutureBuilder(
            future: future,
            builder: (context, value) {
              if (value.hasError) {
                return LineageSectionCard(
                  title: '精确查询向量',
                  child: Text('不可用：${value.error}'),
                );
              }
              if (!value.hasData) return const LinearProgressIndicator();
              final data = value.data!;
              final top1 = data.neighbors.firstOrNull?.cosineToQuery;
              final top2 = data.neighbors.length > 1
                  ? data.neighbors[1].cosineToQuery
                  : null;
              return Column(
                children: [
                  LineageSectionCard(
                    title: '精确查询向量 · REAL · ACTIVE',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(data.queryEmbeddingId),
                        Text('sha256 ${data.queryVectorSha256}'),
                        const Text('本页只读取 Trace 捕获向量；不会重新调用 Embedding。'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
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
                      ],
                    ),
                  ),
                  LineageSectionCard(
                    title: 'PCA 投影 · DERIVED',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: false, label: Text('2D PCA')),
                            ButtonSegment(value: true, label: Text('3D PCA')),
                          ],
                          selected: <bool>{use3d},
                          onSelectionChanged: (selection) {
                            setState(() => use3d = selection.single);
                          },
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 250,
                          child: CustomPaint(
                            painter: _TraceVectorPainter(
                              data.points,
                              use3d: use3d,
                            ),
                          ),
                        ),
                        Text(
                          '${data.points.length - 1}/${data.totalPersistentBodyCount} '
                          'corpus representations sampled · ${data.samplePolicy}',
                        ),
                        const Text('PCA 是 DERIVED 投影；真实排序以 cosine 检索结果为准。'),
                        const SizedBox(height: 8),
                        const Wrap(
                          spacing: 8,
                          children: [
                            Chip(label: Text('UMAP · 未启用')),
                            Chip(label: Text('t-SNE · 未启用')),
                          ],
                        ),
                      ],
                    ),
                  ),
                  LineageSectionCard(
                    title: 'Top 邻居 · REAL cosine',
                    child: Column(
                      children: [
                        for (var index = 0;
                            index < data.neighbors.length;
                            index++)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(child: Text('${index + 1}')),
                            title: Text(data.neighbors[index].chunkId ?? 'unknown'),
                            subtitle: Text(
                              '${data.neighbors[index].sourceName} · '
                              '${data.neighbors[index].representation.name} · '
                              '${data.neighbors[index].lane?.dbValue ?? 'SAMPLE'}',
                            ),
                            trailing: Text(
                              data.neighbors[index].cosineToQuery
                                  .toStringAsFixed(4),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      );
}

class _TraceVectorPainter extends CustomPainter {
  const _TraceVectorPainter(this.points, {required this.use3d});

  final List<TraceVectorPoint> points;
  final bool use3d;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    double projectedX(TraceVectorPoint point) =>
        point.x + (use3d ? point.z * 0.32 : 0);
    double projectedY(TraceVectorPoint point) =>
        point.y - (use3d ? point.z * 0.18 : 0);
    final xs = points.map(projectedX).toList();
    final ys = points.map(projectedY).toList();
    final minX = xs.reduce(math.min);
    final maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min);
    final maxY = ys.reduce(math.max);
    final spanX = (maxX - minX).abs() < 1e-9 ? 1.0 : maxX - minX;
    final spanY = (maxY - minY).abs() < 1e-9 ? 1.0 : maxY - minY;
    for (final point in points) {
      final x = 12 + (projectedX(point) - minX) / spanX * (size.width - 24);
      final y = 12 + (projectedY(point) - minY) / spanY * (size.height - 24);
      final color = point.isQuery
          ? Colors.red
          : point.lane == RetrievalLane.active
              ? Colors.indigo
              : point.lane == RetrievalLane.shadow
                  ? Colors.teal
                  : Colors.grey;
      canvas.drawCircle(
        Offset(x, y),
        point.isQuery ? 7 : 4,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TraceVectorPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.use3d != use3d;
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
