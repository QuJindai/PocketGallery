import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../../chat/chat_models.dart';
import '../../observability/retrieval_trace.dart';
import '../../observability/vector_microscope_service.dart';
import '../../services/knowledge_engine.dart';
import 'vector_map_painter.dart';

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
  bool show3d = false;
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
        preferredChunkIds: widget.trace.semanticHits.map((e) => e.chunkId),
      );
      if (!mounted) return;
      setState(() => snapshot = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => error = e);
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
          children: [
            Text(widget.trace.query,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Chip(label: Text('REAL · Embedding / cosine / norm')),
                Chip(label: Text('DERIVED · PCA projection')),
                Chip(label: Text('UMAP · 未启用')),
                Chip(label: Text('t-SNE · 未启用')),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('2D PCA')),
                ButtonSegment(value: true, label: Text('3D PCA 投影')),
              ],
              selected: {show3d},
              onSelectionChanged: (s) => setState(() => show3d = s.first),
            ),
            if (loading) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            if (error != null) ...[
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
            if (data != null) ...[
              const SizedBox(height: 10),
              _metadataCard(data),
              const SizedBox(height: 8),
              Card(
                child: SizedBox(
                  height: 330,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: CustomPaint(
                      painter: VectorMapPainter(
                        points: data.points,
                        show3d: show3d,
                        queryColor: Theme.of(context).colorScheme.error,
                        lineColor: Theme.of(context).colorScheme.primary,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'PCA 仅是高维向量的有损投影，空间靠近不等于“语义真相”；排序仍以 REAL cosine / 检索结果为准。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Text('最近邻 · REAL cosine',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              if (data.neighbors.isEmpty)
                const Text('当前没有已观测 Chunk 向量。')
              else
                for (var i = 0; i < data.neighbors.length; i++)
                  ListTile(
                    dense: true,
                    leading: Text('#${i + 1}'),
                    title: Text(data.neighbors[i].chunk.sourceName,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${data.neighbors[i].chunk.locator} · norm ${data.neighbors[i].norm.toStringAsFixed(4)}',
                    ),
                    trailing: Text(
                      data.neighbors[i].cosine.toStringAsFixed(5),
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
          children: [
            Text(data.modelIdentity,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                Text('REAL dimension · ${data.dimension}D'),
                Text('REAL query norm · ${data.queryNorm.toStringAsFixed(5)}'),
                Text('points · ${data.points.length}'),
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(
              data.queryFingerprint,
              style: const TextStyle(fontSize: 11),
            ),
            if (ratios.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'DERIVED explained variance · ${[
                  for (final v in ratios.take(3)) '${(v * 100).toStringAsFixed(1)}%'
                ].join(' / ')}',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
