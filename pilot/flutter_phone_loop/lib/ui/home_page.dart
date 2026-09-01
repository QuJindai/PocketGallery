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

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
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
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapModelState());
  }

  Future<void> _bootstrapModelState() async {
    if (await setup.hasPendingAuthorization()) {
      await _prepare(resumePendingAuthorization: true);
    } else {
      await _prepare();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Future<void>.delayed(
        const Duration(milliseconds: 400),
        _resumeOAuthAfterExternalBrowser,
      );
    }
  }

  Future<void> _resumeOAuthAfterExternalBrowser() async {
    if (!mounted || modelBusy || modelState.ready) return;
    if (!await setup.hasPendingAuthorization()) return;
    if (!mounted) return;
    await _prepare(resumePendingAuthorization: true);
  }

  Future<void> _prepare({
    bool authorize = false,
    bool continueAfterLicense = false,
    bool resumePendingAuthorization = false,
  }) async {
    if (modelBusy) return;
    setState(() => modelBusy = true);
    try {
      void progress(ModelSetupSnapshot s) {
        if (mounted) setState(() => modelState = s);
      }

      final ModelSetupSnapshot r;
      if (resumePendingAuthorization) {
        r = await setup.resumePendingAuthorizationAndPrepare(
          onProgress: progress,
        );
      } else if (continueAfterLicense) {
        r = await setup.continueAfterLicense(onProgress: progress);
      } else if (authorize) {
        r = await setup.authorizeAndPrepare(onProgress: progress);
      } else {
        r = await setup.prepareAutomatically(onProgress: progress);
      }
      if (!mounted) return;
      setState(() => modelState = r);
      if (r.ready) {
        await widget.engine.syncSemanticIndex();
        if (mounted) {
          setState(() => status = '模型 READY · 已自动补建 Embedding 索引');
        }
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PocketGallery · Phone Pilot R3.3')),
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
          ...imported.map(
            (x) => ListTile(
              dense: true,
              leading: const Icon(Icons.description_outlined),
              title: Text(x),
            ),
          ),
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
    var textlessFiles = 0;
    for (final path in paths) {
      if (mounted) setState(() => status = '索引 ${path.split('/').last}…');
      final doc = await widget.engine.importPath(path);
      if (doc.chunks.isEmpty) {
        textlessFiles++;
        imported.add(
          '${doc.sourceName} · 0 chunks · 未提取到可检索文本（可能是扫描件/图片型 PDF）',
        );
      } else {
        imported.add('${doc.sourceName} · ${doc.chunks.length} chunks');
      }
    }
    if (!mounted) return;
    setState(() {
      if (textlessFiles > 0) {
        status = '文档导入完成 · $textlessFiles 个文件未提取到可检索文本；可能是扫描件/图片型 PDF';
      } else {
        status = modelState.ready
            ? '文档索引完成 · FTS5 + Embedding'
            : '文档索引完成 · FTS5 已可用，Embedding 将在模型就绪后自动补建';
      }
    });
  }

  Future<void> _ask() async {
    if (mounted) {
      setState(
        () => status = modelState.ready
            ? 'FTS5 + Embedding + Hybrid/Rerank → Gemma 4…'
            : 'FTS5 / Evidence 检索…',
      );
    }
    final r = await widget.engine.ask(query.text);
    if (!mounted) return;
    setState(() {
      answer = r;
      status = modelState.ready ? '完成' : '检索完成 · Embedding 尚未就绪（FTS5 可用）';
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
    final authorizing = modelState.phase == ModelSetupPhase.authorizing;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  modelState.ready
                      ? Icons.check_circle
                      : failed
                      ? Icons.error_outline
                      : authorizing
                      ? Icons.verified_user_outlined
                      : Icons.downloading,
                ),
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
              ],
            ),
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
            if (authorizing && !modelBusy) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _prepare(resumePendingAuthorization: true),
                icon: const Icon(Icons.sync),
                label: const Text('检查授权状态并继续'),
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
              '不再填写 Token。使用 Hugging Face 官方授权；授权事务会先保存到本机，切换浏览器或 App 被系统暂停后也能自动恢复。模型下载成功后永久复用，不重复下载。',
            ),
            const SizedBox(height: 8),
            const Text(
              'Hugging Face 的 Device OAuth 页面有时会显示 8 位授权码输入框。授权码已自动复制到剪贴板，页面打开后只需粘贴并继续；无需记码，也无需手工创建 Token。',
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: modelBusy ? null : () => _prepare(authorize: true),
              icon: const Icon(Icons.verified_user),
              label: const Text('使用 Hugging Face 官方授权'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () => _run(setup.openEmbeddingLicensePage),
              icon: const Icon(Icons.open_in_browser),
              label: const Text('打开 EmbeddingGemma 官方许可页'),
            ),
            const SizedBox(height: 4),
            const Text(
              '如果刚刚只在许可页接受了条款，点下面按钮会启动官方 OAuth；浏览器完成后返回 App，即会自动领取令牌并继续下载。',
            ),
            TextButton(
              onPressed: modelBusy
                  ? null
                  : () => _prepare(continueAfterLicense: true),
              child: const Text('已完成许可，继续官方授权并下载'),
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
            ...a.evidence.map(
              (e) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(child: Text(e.anchor)),
                title: Text(e.chunk.sourceName),
                subtitle: Text(
                  '${e.chunk.locator} · ${e.chunk.id}\n${e.chunk.text}',
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reportCard(GoldenTestReport r) {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          ListTile(
            leading: Icon(r.passed ? Icons.check_circle : Icons.cancel),
            title: Text(
              r.passed
                  ? 'PHONE_FUNCTION_LOOP = PASS'
                  : 'PHONE_FUNCTION_LOOP = FAIL',
            ),
          ),
          ...r.results.map(
            (g) => ListTile(
              dense: true,
              leading: Icon(g.passed ? Icons.check : Icons.close),
              title: Text(g.name),
              subtitle: Text(
                g.detail,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
