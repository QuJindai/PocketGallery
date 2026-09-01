import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../../chat/chat_models.dart';
import '../../observability/retrieval_trace.dart';
import '../../observability/vector_microscope_service.dart';
import '../../services/knowledge_engine.dart';
import 'vector_space_3d.dart';

class VectorMicroscopePage extends StatefulWidget {
  const VectorMicroscopePage({
    super.key,
    required this.engine,
    required this.trace,
  });

  final KnowledgeEngine engine;
  final RetrievalTrace trace;

  @override
  State<VectorMicroscopePage> createState() => _VectorMicroscopePageState();
}

class _VectorMicroscopePageState extends State<VectorMicroscopePage> {
  VectorMicroscopeSnapshot? snapshot;
  Object? error;
  bool loading = true;
  bool rebuilding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  KnowledgeScope get _scope => widget.trace.scopeDocumentIds.isEmpty
      ? const KnowledgeScope.all()
      : KnowledgeScope.documents(widget.trace.scopeDocumentIds);

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (!FlutterGemma.hasActiveEmbedder()) {
        throw StateError('EmbeddingGemma 尚未 READY');
      }
      final service = VectorMicroscopeService(
        semanticStore: widget.engine.semanticStore,
        lexicalStore: widget.engine.lexicalStore,
      );
      final result = await service.build(
        widget.trace.query,
        scope: _scope,
        preferredChunkIds: widget.trace.semanticHits.map((hit) => hit.chunkId),
      );
      if (!mounted) return;
      setState(() => snapshot = result);
    } catch (exception) {
      if (!mounted) return;
      setState(() => error = exception);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _rebuildObservations() async {
    if (rebuilding) return;
    setState(() => rebuilding = true);
    try {
      await widget.engine.syncSemanticIndex();
      await _load();
    } finally {
      if (mounted) setState(() => rebuilding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = snapshot;
    return Scaffold(
      appBar: AppBar(title: const Text('向量显微镜')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: <Widget>[
            Text(
              widget.trace.query,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                Chip(label: Text('REAL · Embedding / cosine / norm')),
                Chip(label: Text('DERIVED · 3D PCA projection')),
                Chip(label: Text('UMAP · 未启用')),
                Chip(label: Text('t-SNE · 未启用')),
              ],
            ),
            if (loading) ...<Widget>[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            if (error != null) ...<Widget>[
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('向量观测失败：$error'),
                      const SizedBox(height: 8),
                      FilledButton.tonalIcon(
                        onPressed: rebuilding ? null : _rebuildObservations,
                        icon: const Icon(Icons.sync),
                        label: Text(rebuilding ? '补建中…' : '补齐向量观测并重试'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (data != null) ...<Widget>[
              const SizedBox(height: 10),
              _metadataCard(data),
              const SizedBox(height: 8),
              VectorMicroscopePlotSection(data: data),
              const SizedBox(height: 8),
              Text(
                'PCA 仅是高维向量的有损投影，空间靠近不等于“语义真相”；排序仍以 REAL cosine / 检索结果为准。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Text(
                '最近邻 · REAL cosine',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              if (data.neighbors.isEmpty)
                const Text('当前没有已观测 Chunk 向量。')
              else
                for (var index = 0; index < data.neighbors.length; index++)
                  ListTile(
                    dense: true,
                    leading: Text('#${index + 1}'),
                    title: Text(
                      data.neighbors[index].chunk.sourceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${data.neighbors[index].chunk.locator} · '
                      'norm ${data.neighbors[index].norm.toStringAsFixed(4)}',
                    ),
                    trailing: Text(
                      data.neighbors[index].cosine.toStringAsFixed(5),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metadataCard(VectorMicroscopeSnapshot data) {
    final ratios = data.explainedVarianceRatios;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              data.modelIdentity,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: <Widget>[
                Text('REAL dimension · ${data.dimension}D'),
                Text('REAL query norm · ${data.queryNorm.toStringAsFixed(5)}'),
                Text('points · ${data.points.length}'),
              ],
            ),
            const SizedBox(height: 6),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('开发者详情'),
              children: <Widget>[
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    data.queryFingerprint,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
            if (ratios.isNotEmpty)
              Text(
                'DERIVED explained variance · ${[for (final ratio in ratios.take(3)) '${(ratio * 100).toStringAsFixed(1)}%'].join(' / ')}',
              ),
          ],
        ),
      ),
    );
  }
}

class VectorMicroscopePlotSection extends StatefulWidget {
  const VectorMicroscopePlotSection({super.key, required this.data});

  final VectorMicroscopeSnapshot data;

  @override
  State<VectorMicroscopePlotSection> createState() =>
      _VectorMicroscopePlotSectionState();
}

class _VectorMicroscopePlotSectionState
    extends State<VectorMicroscopePlotSection> {
  String? selectedId;

  @override
  void initState() {
    super.initState();
    selectedId = widget.data.neighbors.isNotEmpty
        ? widget.data.neighbors.first.chunk.id
        : _queryPoint(widget.data.points)?.id;
  }

  @override
  void didUpdateWidget(covariant VectorMicroscopePlotSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (selectedId == null ||
        !widget.data.points.any((point) => point.id == selectedId)) {
      selectedId = widget.data.neighbors.isNotEmpty
          ? widget.data.neighbors.first.chunk.id
          : _queryPoint(widget.data.points)?.id;
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final neighborIds = data.neighbors.map((row) => row.chunk.id).toSet();
    final selected =
        _pointById(data.points, selectedId) ??
        _queryPoint(data.points) ??
        data.points.firstOrNull;
    final neighbor = selected == null
        ? null
        : _neighborById(data.neighbors, selected.id);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('即时观测，不是历史 Trace 的精确查询向量；用于检查当前知识库的局部关系。'),
            ),
            const SizedBox(height: 10),
            Text(
              '${data.dimension}D → 3D PCA',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            InteractiveVectorPlot(
              points: <VectorPlotPoint>[
                for (final point in data.points)
                  VectorPlotPoint(
                    id: point.id,
                    x: point.x,
                    y: point.y,
                    z: point.z,
                    kind: point.isQuery
                        ? VectorPlotKind.query
                        : neighborIds.contains(point.id)
                        ? VectorPlotKind.candidate
                        : VectorPlotKind.context,
                    label: point.isQuery ? 'Query' : null,
                  ),
              ],
              explainedVarianceRatios: data.explainedVarianceRatios,
              initialSelectedId: selected?.id,
              onPointSelected: (id) => setState(() => selectedId = id),
            ),
            if (selected != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                selected.isQuery ? '当前即时查询' : selected.sourceName,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                selected.isQuery
                    ? data.query
                    : '${selected.locator} · cosine '
                          '${selected.cosineToQuery?.toStringAsFixed(4) ?? '未捕获'}',
              ),
              if (neighbor != null) ...<Widget>[
                const SizedBox(height: 4),
                SelectableText(neighbor.chunk.text),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

VectorMapPoint? _queryPoint(List<VectorMapPoint> points) {
  for (final point in points) {
    if (point.isQuery) return point;
  }
  return null;
}

VectorMapPoint? _pointById(List<VectorMapPoint> points, String? id) {
  for (final point in points) {
    if (point.id == id) return point;
  }
  return null;
}

VectorNeighbor? _neighborById(List<VectorNeighbor> neighbors, String id) {
  for (final neighbor in neighbors) {
    if (neighbor.chunk.id == id) return neighbor;
  }
  return null;
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
