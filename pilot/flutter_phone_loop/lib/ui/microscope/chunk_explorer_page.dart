import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../../core/models.dart';
import '../../eval/retrieval_benchmark_fixture.dart';
import '../../observability/index_health_service.dart';
import '../../services/knowledge_engine.dart';
import '../../services/semantic_store.dart';

class ChunkExplorerPage extends StatefulWidget {
  const ChunkExplorerPage({
    super.key,
    required this.engine,
    this.initialDocumentId,
  });

  final KnowledgeEngine engine;
  final String? initialDocumentId;

  @override
  State<ChunkExplorerPage> createState() => _ChunkExplorerPageState();
}

class _ChunkExplorerPageState extends State<ChunkExplorerPage> {
  late final IndexHealthService healthService;
  IndexHealthSnapshot? health;
  List<KnowledgeDocument> documents = const [];
  List<ChunkInspection> chunks = const [];
  String? selectedDocumentId;
  bool loading = true;
  bool rebuilding = false;
  SemanticSyncProgress? repairProgress;
  Object? error;

  @override
  void initState() {
    super.initState();
    healthService = IndexHealthService(
      lexicalStore: widget.engine.lexicalStore,
      vectorStore: widget.engine.semanticStore.observationStore,
      activeModelIdentity: () => FlutterGemma.hasActiveEmbedder()
          ? SemanticStore.embeddingModelIdentity
          : '',
    );
    selectedDocumentId = widget.initialDocumentId;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      // R4.3 could leave built-in pg_golden_* diagnostics visible if native
      // vector cleanup failed. These names are reserved by PocketGallery and
      // are never user documents, so remove stale fixtures before presenting
      // real index health.
      await RetrievalBenchmarkFixture.cleanupReservedGoldenDocuments(
        widget.engine,
      );

      final docs = await widget.engine.listDocuments();
      final docIds = docs.map((e) => e.documentId).toSet();
      if (selectedDocumentId != null && !docIds.contains(selectedDocumentId)) {
        selectedDocumentId = null;
      }
      final snapshot = await healthService.snapshot();
      final selected = selectedDocumentId;
      final inspected = selected == null
          ? const <ChunkInspection>[]
          : await healthService.inspectDocument(selected);
      if (!mounted) return;
      setState(() {
        documents = docs;
        health = snapshot;
        chunks = inspected;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => error = e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _selectDocument(String documentId) async {
    setState(() {
      selectedDocumentId = documentId;
      loading = true;
    });
    try {
      final inspected = await healthService.inspectDocument(documentId);
      if (!mounted) return;
      setState(() => chunks = inspected);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _rebuildMissing() async {
    if (rebuilding || !FlutterGemma.hasActiveEmbedder()) return;
    setState(() {
      rebuilding = true;
      repairProgress = null;
      error = null;
    });
    try {
      await widget.engine.syncMissingSemanticIndex(
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => repairProgress = progress);
        },
      );
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '向量补建中断：$e。已完成部分已经保存，可再次点击继续。';
        });
      }
    } finally {
      if (mounted) setState(() => rebuilding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chunk Explorer / 索引健康'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: loading || rebuilding ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (loading) const LinearProgressIndicator(),
            if (error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('索引健康检查失败：$error'),
                ),
              ),
            if (health != null) _healthCard(context, health!),
            const SizedBox(height: 10),
            Text('文档', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            if (documents.isEmpty)
              const Text('知识库为空。')
            else
              for (final document in documents)
                Card(
                  child: ListTile(
                    selected: document.documentId == selectedDocumentId,
                    leading: Icon(document.chunkCount == 0
                        ? Icons.warning_amber
                        : Icons.description_outlined),
                    title: Text(document.sourceName,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${document.chunkCount} chunks · SHA ${_short(document.sha256)}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: rebuilding
                        ? null
                        : () => _selectDocument(document.documentId),
                  ),
                ),
            if (selectedDocumentId != null) ...[
              const Divider(height: 28),
              Text('Chunk 明细', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              if (chunks.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Text('该文档没有可检索 Chunk。可能是扫描件、图片型 PDF 或解析失败。'),
                  ),
                )
              else
                for (final inspection in chunks) _chunkCard(context, inspection),
            ],
          ],
        ),
      ),
    );
  }

  Widget _healthCard(BuildContext context, IndexHealthSnapshot h) {
    final p = repairProgress;
    final needsRepair = h.missingVectorCount > 0 || h.staleVectorCount > 0;
    final progressLabel = p == null
        ? '补建中…'
        : '补建 ${p.completed}/${p.total} · ${(p.percent * 100).toStringAsFixed(1)}%';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.monitor_heart_outlined),
                const SizedBox(width: 8),
                Text('索引健康', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _metric('Documents', '${h.documentCount}'),
                _metric('Chunks', '${h.chunkCount}'),
                _metric('FTS', '${h.ftsIndexedCount}/${h.chunkCount}'),
                _metric('Vector', '${h.vectorIndexedCount}/${h.chunkCount}'),
                _metric('Missing Vector', '${h.missingVectorCount}'),
                _metric('Stale', '${h.staleVectorCount}'),
                _metric('0-chunk', '${h.zeroChunkDocuments}'),
                _metric('Duplicate SHA', '${h.duplicateShaGroups}'),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'REAL index coverage · FTS ${(h.ftsCoverage * 100).toStringAsFixed(1)}% · Vector ${(h.vectorCoverage * 100).toStringAsFixed(1)}%',
            ),
            if (h.ftsDbBytes != null || h.vectorDbBytes != null) ...[
              const SizedBox(height: 4),
              Text(
                'DB · FTS ${_bytes(h.ftsDbBytes)} · Vector ${_bytes(h.vectorDbBytes)} · Observatory ${_bytes(h.observabilityDbBytes)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (rebuilding && p != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: p.percent.clamp(0.0, 1.0)),
              const SizedBox(height: 6),
              Text(progressLabel),
              if (p.currentSource != null)
                Text(
                  '当前：${p.currentSource}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
            if (needsRepair || rebuilding) ...[
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: rebuilding || !FlutterGemma.hasActiveEmbedder()
                    ? null
                    : _rebuildMissing,
                icon: const Icon(Icons.sync),
                label: Text(rebuilding ? progressLabel : '仅补齐缺失/过期向量'),
              ),
              const SizedBox(height: 4),
              Text(
                rebuilding
                    ? '已完成项即时落盘；中断后再次运行会从剩余项继续。'
                    : '不会重算已经健康的向量。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metric(String name, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(name, style: const TextStyle(fontSize: 11)),
          ],
        ),
      );

  Widget _chunkCard(BuildContext context, ChunkInspection item) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '#${item.chunk.ordinal + 1} · ${item.chunk.locator}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(item.vectorReady ? 'Vector ✓' : 'Vector —'),
                  ),
                ],
              ),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text('chars ${item.characterCount}'),
                  Text('overlap ${item.overlapChars}'),
                  Text('FTS ${item.ftsReady ? '✓' : '—'}'),
                  if (item.vectorDimension != null)
                    Text('${item.vectorDimension}D'),
                  if (item.vectorNorm != null)
                    Text('norm ${item.vectorNorm!.toStringAsFixed(4)}'),
                ],
              ),
              if (item.vectorModelIdentity != null) ...[
                const SizedBox(height: 4),
                Text(
                  item.vectorModelIdentity!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const Divider(),
              SelectableText(
                item.chunk.text,
                maxLines: 8,
              ),
            ],
          ),
        ),
      );

  String _short(String value) =>
      value.length <= 10 ? value : '${value.substring(0, 10)}…';

  String _bytes(int? value) {
    if (value == null) return '—';
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
    return '${(value / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
