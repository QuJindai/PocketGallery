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
  final hfToken = TextEditingController();

  ModelSetupSnapshot modelState = const ModelSetupSnapshot(
    phase: ModelSetupPhase.checking,
    message: '自动准备模型即将开始…',
  );
  bool modelBusy = false;
  bool busy = false;
  String status = 'FTS5 本地检索 READY';
  KnowledgeAnswer? answer;
  GoldenTestReport? report;
  final List<String> imported = [];

  String? advancedGemmaPath;
  String? advancedEmbeddingPath;
  String? advancedTokenizerPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoPrepareModels());
  }

  Future<void> _autoPrepareModels({String? token}) async {
    if (modelBusy) return;
    setState(() => modelBusy = true);
    try {
      final result = await setup.prepareAutomatically(
        huggingFaceToken: token,
        onProgress: (state) {
          if (mounted) setState(() => modelState = state);
        },
      );
      if (!mounted) return;
      setState(() => modelState = result);
      if (result.ready) {
        await widget.engine.syncSemanticIndex();
        hfToken.clear();
      }
    } finally {
      if (mounted) setState(() => modelBusy = false);
    }
  }

  Future<void> _run(Future<void> Function() fn) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await fn();
    } catch (e) {
      if (mounted) setState(() => status = '操作失败：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _installAdvancedFiles() async {
    if (advancedGemmaPath == null ||
        advancedEmbeddingPath == null ||
        advancedTokenizerPath == null) return;
    setState(() => modelBusy = true);
    try {
      await setup.installGemma4FromFile(advancedGemmaPath!);
      await setup.installEmbedderFromFiles(
        modelPath: advancedEmbeddingPath!,
        tokenizerPath: advancedTokenizerPath!,
      );
      await widget.engine.syncSemanticIndex();
      if (mounted) {
        setState(() {
          modelState = const ModelSetupSnapshot(
            phase: ModelSetupPhase.ready,
            message: '本机模型 READY · 本地文件备用路径',
            progress: 100,
          );
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          modelState = ModelSetupSnapshot(
            phase: ModelSetupPhase.failed,
            message: '本地模型安装失败：$e',
          );
        });
      }
    } finally {
      if (mounted) setState(() => modelBusy = false);
    }
  }

  @override
  void dispose() {
    query.dispose();
    hfToken.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PocketGallery · Phone Pilot R2')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'FTS5 + EmbeddingGemma + Hybrid RAG + Local Gemma',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          _modelCard(),
          if (modelState.authorizationRequired) _authorizationCard(),
          _advancedModelFiles(),
          const Divider(height: 28),
          Text(status),
          const SizedBox(height: 8),
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
                    setState(() {
                      status = modelState.ready
                          ? '文档索引完成 · FTS5 + Embedding'
                          : '文档索引完成 · FTS5 已可用，Embedding 将在模型就绪后自动补建';
                    });
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
                    setState(() => status = modelState.ready
                        ? 'FTS5 + Embedding + Hybrid → Gemma…'
                        : 'FTS5 / Evidence 检索…');
                    final r = await widget.engine.ask(query.text);
                    setState(() {
                      answer = r;
                      status = modelState.ready ? '完成' : '检索完成 · 模型仍在自动准备';
                    });
                  }),
            icon: const Icon(Icons.search),
            label: const Text('检索并回答'),
          ),
          if (answer != null) _answerCard(answer!),
          const Divider(height: 28),
          FilledButton.icon(
            onPressed: busy || !modelState.ready
                ? null
                : () => _run(() async {
                    setState(() => status = '自动 Golden Test…');
                    final r = await GoldenTestRunner(widget.engine).run();
                    setState(() {
                      report = r;
                      status = r.passed
                          ? 'PHONE_FUNCTION_LOOP = PASS'
                          : 'PHONE_FUNCTION_LOOP = FAIL';
                    });
                  }),
            icon: const Icon(Icons.verified),
            label: const Text('Run Phone Golden Test'),
          ),
          if (!modelState.ready)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Golden Test 会在 Gemma 4 与 EmbeddingGemma 均就绪后开放。'),
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

  Widget _modelCard() {
    final progress = modelState.progress;
    final failed = modelState.phase == ModelSetupPhase.failed;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(modelState.ready
                    ? Icons.check_circle
                    : failed
                        ? Icons.error_outline
                        : Icons.downloading),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '自动准备模型',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (modelBusy) const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(modelState.message),
            if (progress != null) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(value: progress / 100),
            ],
            if (failed) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: modelBusy ? null : () => _autoPrepareModels(),
                icon: const Icon(Icons.refresh),
                label: const Text('自动重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _authorizationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'EmbeddingGemma 官方许可',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'EmbeddingGemma 是受许可控制的官方模型。接受官方使用许可后，只需填一次 Hugging Face 只读 Token；App 会自动下载 .tflite 和 Tokenizer，不再手工找文件。Token 不会被 App 持久保存。',
            ),
            const SizedBox(height: 10),
            TextField(
              controller: hfToken,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Hugging Face Read Token',
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: modelBusy
                  ? null
                  : () => _autoPrepareModels(token: hfToken.text),
              icon: const Icon(Icons.lock_open),
              label: const Text('授权后自动继续'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _advancedModelFiles() {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('高级：本地模型文件（备用）'),
      children: [
        _advancedPathRow(
          '备用 Gemma 4 .litertlm',
          advancedGemmaPath,
          () => _run(() async {
            advancedGemmaPath = await setup.pickFile(const ['litertlm']);
            if (mounted) setState(() {});
          }),
        ),
        _advancedPathRow(
          '备用 EmbeddingGemma .tflite',
          advancedEmbeddingPath,
          () => _run(() async {
            advancedEmbeddingPath = await setup.pickFile(const ['tflite']);
            if (mounted) setState(() {});
          }),
        ),
        _advancedPathRow(
          '备用 Tokenizer sentencepiece.model',
          advancedTokenizerPath,
          () => _run(() async {
            advancedTokenizerPath = await setup.pickFile(const ['model', 'json']);
            if (mounted) setState(() {});
          }),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: modelBusy ||
                    advancedGemmaPath == null ||
                    advancedEmbeddingPath == null ||
                    advancedTokenizerPath == null
                ? null
                : _installAdvancedFiles,
            child: const Text('从本地备用文件安装'),
          ),
        ),
      ],
    );
  }

  Widget _advancedPathRow(String label, String? path, VoidCallback onPick) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(path ?? '未选择', maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: OutlinedButton(
        onPressed: busy ? null : onPick,
        child: const Text('选择'),
      ),
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
              title: Text(r.passed
                  ? 'PHONE_FUNCTION_LOOP = PASS'
                  : 'PHONE_FUNCTION_LOOP = FAIL'),
            ),
            ...r.results.map((g) => ListTile(
                  dense: true,
                  leading: Icon(g.passed ? Icons.check : Icons.close),
                  title: Text(g.name),
                  subtitle: Text(
                    g.detail,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
