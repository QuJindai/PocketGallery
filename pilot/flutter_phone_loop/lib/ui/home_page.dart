import 'package:flutter/material.dart';

import '../core/models.dart';
import '../services/golden_test_runner.dart';
import '../services/knowledge_engine.dart';
import '../services/model_setup_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.engine});
  final KnowledgeEngine engine;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final setup = ModelSetupService();
  final query = TextEditingController(
    text: '31 03 51 01 获取标定结果时，为什么 DSA 可能一直等待？',
  );
  String? gemmaPath;
  String? embeddingPath;
  String? tokenizerPath;
  String status = '未配置模型';
  bool busy = false;
  KnowledgeAnswer? answer;
  GoldenTestReport? report;
  final List<String> imported = [];

  Future<void> _run(Future<void> Function() fn) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await fn();
    } catch (e) {
      setState(() => status = 'ERROR: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PocketGallery · Phone Pilot')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'FTS5 + EmbeddingGemma + Hybrid RAG + Local Gemma',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(status),
          const Divider(height: 28),
          _pathRow(
            'Gemma 4 .litertlm',
            gemmaPath,
            () => _run(() async {
              gemmaPath = await setup.pickFile(const ['litertlm']);
              setState(() {});
            }),
          ),
          _pathRow(
            'EmbeddingGemma .tflite',
            embeddingPath,
            () => _run(() async {
              embeddingPath = await setup.pickFile(const ['tflite']);
              setState(() {});
            }),
          ),
          _pathRow(
            'Tokenizer sentencepiece.model',
            tokenizerPath,
            () => _run(() async {
              tokenizerPath = await setup.pickFile(const ['model', 'json']);
              setState(() {});
            }),
          ),
          FilledButton.icon(
            onPressed: busy || gemmaPath == null || embeddingPath == null || tokenizerPath == null
                ? null
                : () => _run(() async {
                    setState(() => status = '安装/加载本机模型…');
                    await setup.installGemma4FromFile(gemmaPath!);
                    await setup.installEmbedderFromFiles(
                      modelPath: embeddingPath!,
                      tokenizerPath: tokenizerPath!,
                    );
                    await widget.engine.initialize();
                    await widget.engine.gemma.ensureLoaded();
                    setState(() => status = '模型与检索引擎 READY');
                  }),
            icon: const Icon(Icons.memory),
            label: const Text('初始化本机模型'),
          ),
          const Divider(height: 28),
          FilledButton.tonalIcon(
            onPressed: busy
                ? null
                : () => _run(() async {
                    final paths = await widget.engine.importer.pickDocumentPaths();
                    for (final path in paths) {
                      setState(() => status = '索引 ${path.split('/').last}…');
                      final doc = await widget.engine.importPath(path);
                      imported.add('${doc.sourceName} · ${doc.chunks.length} chunks');
                    }
                    setState(() => status = '文档索引完成');
                  }),
            icon: const Icon(Icons.library_add),
            label: const Text('导入 TXT / MD / PDF'),
          ),
          if (imported.isNotEmpty)
            ...imported.map((x) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.description_outlined),
                  title: Text(x),
                )),
          const SizedBox(height: 12),
          TextField(
            controller: query,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: '本地知识提问',
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: busy
                ? null
                : () => _run(() async {
                    setState(() => status = 'FTS5 + Embedding + Hybrid → Gemma…');
                    final r = await widget.engine.ask(query.text);
                    setState(() {
                      answer = r;
                      status = '完成';
                    });
                  }),
            icon: const Icon(Icons.search),
            label: const Text('检索并回答'),
          ),
          if (answer != null) _answerCard(answer!),
          const Divider(height: 28),
          FilledButton.icon(
            onPressed: busy
                ? null
                : () => _run(() async {
                    setState(() => status = '自动 Golden Test…');
                    final r = await GoldenTestRunner(widget.engine).run();
                    setState(() {
                      report = r;
                      status = r.passed ? 'PHONE_FUNCTION_LOOP = PASS' : 'PHONE_FUNCTION_LOOP = FAIL';
                    });
                  }),
            icon: const Icon(Icons.verified),
            label: const Text('Run Phone Golden Test'),
          ),
          if (report != null) _reportCard(report!),
          if (busy) const Padding(
            padding: EdgeInsets.only(top: 16),
            child: LinearProgressIndicator(),
          ),
        ],
      ),
    );
  }

  Widget _pathRow(String label, String? path, VoidCallback onPick) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(path ?? '未选择', maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: OutlinedButton(onPressed: busy ? null : onPick, child: const Text('选择')),
    );
  }

  Widget _answerCard(KnowledgeAnswer a) {
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Answer', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SelectableText(a.answer),
            const SizedBox(height: 12),
            Text(
              'Retrieval: FTS5=${a.lexicalHits.length} · '
              'Embedding=${a.semanticHits.length} · Hybrid=${a.hybridHits.length}',
            ),
            const Divider(),
            ...a.evidence.map((e) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(child: Text(e.anchor)),
                  title: Text(e.chunk.sourceName),
                  subtitle: Text(
                    '${e.chunk.locator} · ${e.chunk.id}\n${e.chunk.text}',
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _reportCard(GoldenTestReport r) {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            ListTile(
              leading: Icon(r.passed ? Icons.check_circle : Icons.cancel),
              title: Text(r.passed ? 'PHONE_FUNCTION_LOOP = PASS' : 'PHONE_FUNCTION_LOOP = FAIL'),
            ),
            ...r.results.map((g) => ListTile(
                  dense: true,
                  leading: Icon(g.passed ? Icons.check : Icons.close),
                  title: Text(g.name),
                  subtitle: Text(g.detail, maxLines: 3, overflow: TextOverflow.ellipsis),
                )),
          ],
        ),
      ),
    );
  }
}
