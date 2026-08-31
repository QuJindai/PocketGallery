import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../chat/chat_orchestrator.dart';
import '../core/models.dart';
import '../services/knowledge_engine.dart';
import 'microscope/chunk_explorer_page.dart';
import 'microscope/rag_lineage_dashboard_page.dart';
import 'microscope/retrieval_benchmark_page.dart';
import 'microscope/retrieval_experiment_center_page.dart';

class KnowledgePage extends StatefulWidget {
  const KnowledgePage({
    super.key,
    required this.engine,
    this.orchestrator,
  });

  final KnowledgeEngine engine;
  final ChatOrchestrator? orchestrator;

  @override
  State<KnowledgePage> createState() => _KnowledgePageState();
}

class _KnowledgePageState extends State<KnowledgePage> {
  List<KnowledgeDocument> documents = const [];
  bool busy = false;
  String status = 'FTS5 READY';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => status = '操作失败：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _reload() async {
    final docs = await widget.engine.listDocuments();
    if (!mounted) return;
    setState(() => documents = docs);
  }

  Future<void> _import() async {
    final paths = await widget.engine.importer.pickDocumentPaths();
    var textless = 0;
    for (final path in paths) {
      if (mounted) {
        setState(() => status = '导入 ${path.split('/').last}…');
      }
      final doc = await widget.engine.importPath(path);
      if (doc.chunks.isEmpty) textless++;
    }
    await _reload();
    if (!mounted) return;
    setState(() {
      status = textless == 0
          ? '导入完成 · FTS5 READY'
          : '导入完成 · $textless 个文件为 0 chunks，可能是扫描件/图片型 PDF';
    });
  }

  Future<void> _delete(KnowledgeDocument doc) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('删除文档'),
            content: Text('从本地知识库删除“${doc.sourceName}”及其索引？模型文件不会被删除。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('删除文档'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await widget.engine.removeDocument(doc.documentId);
    await _reload();
    if (mounted) setState(() => status = '已删除 ${doc.sourceName}');
  }

  Future<void> _rebuild(KnowledgeDocument doc) async {
    if (!FlutterGemma.hasActiveEmbedder()) {
      setState(() => status = 'EmbeddingGemma 尚未 READY；FTS5 不受影响。');
      return;
    }
    setState(() => status = '重建 Embedding · ${doc.sourceName}…');
    await widget.engine.rebuildDocumentEmbedding(doc.documentId);
    if (mounted) setState(() => status = '重建 Embedding 完成 · ${doc.sourceName}');
  }

  Future<void> _rebuildAll() async {
    if (!FlutterGemma.hasActiveEmbedder()) {
      setState(() => status = 'EmbeddingGemma 尚未 READY；FTS5 不受影响。');
      return;
    }
    setState(() => status = '重建全部 Embedding…');
    await widget.engine.rebuildAllEmbeddings();
    if (mounted) setState(() => status = '全部 Embedding 索引已重建');
  }

  Future<void> _openHealth({String? documentId}) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChunkExplorerPage(
        engine: widget.engine,
        initialDocumentId: documentId,
      ),
    ));
    await _reload();
  }

  Future<void> _openBenchmark() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => RetrievalBenchmarkPage(engine: widget.engine),
    ));
  }

  Future<void> _openLineage() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => RagLineageDashboardPage(
        engine: widget.engine,
        lineageStore: widget.engine.lineageStore,
        orchestrator: widget.orchestrator,
      ),
    ));
  }

  Future<void> _openExperiments() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => RetrievalExperimentCenterPage(
        store: widget.engine.lineageStore,
        experimentEngine: widget.engine.experimentEngine,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('知识库'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: busy ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.storage_outlined, size: 18),
                      const SizedBox(width: 6),
                      Expanded(child: Text(status)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: busy ? null : () => _run(_import),
                    icon: const Icon(Icons.library_add),
                    label: const Text('导入 TXT / MD / PDF'),
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => _run(_rebuildAll),
                    icon: const Icon(Icons.sync),
                    label: const Text('重建全部 Embedding'),
                  ),
                  const SizedBox(height: 6),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.biotech_outlined, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'RAG 显微镜',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            '查看真实 RAG Lineage、FTS5、向量、Chunk、索引健康与检索基准。',
                          ),
                          const SizedBox(height: 8),
                          FilledButton.tonalIcon(
                            onPressed: busy ? null : _openLineage,
                            icon: const Icon(Icons.account_tree_outlined),
                            label: const Text('RAG Lineage'),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.tonalIcon(
                                  onPressed: busy ? null : () => _openHealth(),
                                  icon: const Icon(Icons.monitor_heart_outlined),
                                  label: const Text('索引健康'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton.tonalIcon(
                                  onPressed: busy ? null : _openBenchmark,
                                  icon: const Icon(Icons.science_outlined),
                                  label: const Text('检索基准'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          FilledButton.tonalIcon(
                            key: const ValueKey<String>(
                              'open-retrieval-experiment-center',
                            ),
                            onPressed: busy ? null : _openExperiments,
                            icon: const Icon(Icons.science_outlined),
                            label: const Text('Experiment Center'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: documents.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(28),
                        child: Text(
                          '本地知识库为空。导入 TXT、MD 或 PDF 后即可在聊天中外挂使用。',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: documents.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final doc = documents[index];
                        final chunkText = doc.chunkCount == 0
                            ? '0 chunks · 未提取到文本（可能是扫描件/图片型 PDF）'
                            : '${doc.chunkCount} chunks · FTS5 READY';
                        final embedding = FlutterGemma.hasActiveEmbedder()
                            ? 'Embedding READY'
                            : 'Embedding 待补建';
                        return ListTile(
                          onTap: () => _openHealth(documentId: doc.documentId),
                          leading: Icon(doc.chunkCount == 0
                              ? Icons.image_not_supported_outlined
                              : Icons.description_outlined),
                          title: Text(doc.sourceName),
                          subtitle: Text('$chunkText\n$embedding'),
                          isThreeLine: true,
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'inspect') {
                                _openHealth(documentId: doc.documentId);
                              } else if (value == 'embedding') {
                                _run(() => _rebuild(doc));
                              } else if (value == 'delete') {
                                _run(() => _delete(doc));
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'inspect',
                                child: Text('Chunk Explorer'),
                              ),
                              PopupMenuItem(
                                value: 'embedding',
                                child: Text('重建 Embedding'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('删除文档'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            if (busy) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
