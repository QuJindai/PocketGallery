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

  ModelSetupSnapshot modelState = const ModelSetupSnapshot(
    phase: ModelSetupPhase.checking,
    message: '自动准备模型即将开始…',
  );
  bool modelBusy = false;
  bool busy = false;
  String status = 'FTS5 本地检索 READY';
  KnowledgeAnswer? answer;
  GoldenTestReport? report;
  final imported = <String>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  Future<void> _prepare({bool authorize = false}) async {
    if (modelBusy) return;
    setState(() => modelBusy = true);
    try {
      final progress = (ModelSetupSnapshot s) {
        if (mounted) setState(() => modelState = s);
      };
      final r = authorize
          ? await setup.authorizeAndPrepare(onProgress: progress)
          : await setup.prepareAutomatically(onProgress: progress);
      if (!mounted) return;
      setState(() => modelState = r);
      if (r.ready) await widget.engine.syncSemanticIndex();
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

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PocketGallery · Phone Pilot R3')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'FTS5 + EmbeddingGemma + Hybrid/Rerank + Evidence + Gemma 4 + Citation',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          _modelCard(),
          if (modelState.authorizationRequired) _authorizationCard(),
          const Divider(height: 28),
          Text(status),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: busy ? null : () => _run(_importDocuments),
            icon: const Icon(Icons.library_add),
            label: const Text('导入 TXT / MD / PDF'),
          ),
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
            onPressed: busy ? null : () => _run(_ask),
            icon: const Icon(Icons.search),
            label: const Text('检索并回答'),
          ),
          if (answer != null) _answerCard(answer!),
          const Divider(height: 28),
          FilledButton.icon(
            onPressed: busy || !modelState.ready ? null : () => _run(_golden),
            icon: const Icon(Icons.verified),
            label: const Text('Run Phone Golden Test'),
          ),
          if (!modelState.ready)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Golden Test 会在 Gemma 4 与 EmbeddingGemma 均就绪后开放。'),
            ),
          if (report != null) _reportCard(report!),
          if (busy)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Future<void> _importDocuments() async {
    final paths = await widget.engine.importer.pickDocumentPaths();
    for (final path in paths) {
      if (mounted) setState(() => status = '索引 ${path.split('/').last}…');
      final doc = await widget.engine.importPath(path);
      imported.add('${doc.sourceName} · ${doc.chunks.length} chunks');
    }
    if (!mounted) return;
    setState(() => status = modelState.ready
        ? '文档索引完成 · FTS5 + Embedding'
        : '文档索引完成 · FTS5 已可用，Embedding 将在模型就绪后自动补建');
  }

  Future<void> _ask() async {
    if (mounted) {
      setState(() => status = modelState.ready
          ? 'FTS5 + Embedding + Hybrid/Rerank → Gemma 4…'
          : 'FTS5 / Evidence 检索…');
    }
    final r = await widget.engine.ask(query.text);
    if (!mounted) return;
    setState(() {
      answer = r;
      status = modelState.ready ? '完成' : '检索完成 · 模型仍在自动准备';
    });
  }

  Future<void> _golden() async {
    if (mounted) setState(() => status = '自动 Golden Test…');
    final r = await GoldenTestRunner(widget.engine).run();
    if (!mounted) return;
    setState(() {
      report = r;
      status = r.passed
          ? 'PHONE_FUNCTION_LOOP = PASS'
          : 'PHONE_FUNCTION_LOOP = FAIL';
    });
  }

  Widget _modelCard() {
    final failed = modelState.phase == ModelSetupPhase.failed;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
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
              if (modelBusy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ]),
            const SizedBox(height: 8),
            Text(modelState.message),
            if (modelState.progress != null) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(value: modelState.progress! / 100),
            ],
            if (failed) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: modelBusy ? null : _prepare,
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
              '不再填写 Token。使用 Hugging Face 官方授权，浏览器登录后 App 自动取得 gated-repos OAuth 权限并安全保存/刷新凭据。模型下载成功后永久复用，不重复下载。',
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: modelBusy ? null : () => _prepare(authorize: true),
              icon: const Icon(Icons.verified_user),
              label: const Text('使用 Hugging Face 官方授权'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed:
                  busy ? null : () => _run(setup.openEmbeddingLicensePage),
              icon: const Icon(Icons.open_in_browser),
              label: const Text('打开 EmbeddingGemma 官方许可页'),
            ),
            TextButton(
              onPressed: modelBusy ? null : _prepare,
              child: const Text('已完成许可，自动继续'),
            ),
          ],
        ),
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
      child: Column(children: [
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
      ]),
    );
  }
}
