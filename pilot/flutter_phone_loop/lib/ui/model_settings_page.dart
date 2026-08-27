import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../services/golden_test_runner.dart';
import '../services/knowledge_engine.dart';
import '../services/model_setup_service.dart';

class ModelSettingsPage extends StatefulWidget {
  const ModelSettingsPage({super.key, required this.engine});

  final KnowledgeEngine engine;

  @override
  State<ModelSettingsPage> createState() => _ModelSettingsPageState();
}

class _ModelSettingsPageState extends State<ModelSettingsPage>
    with WidgetsBindingObserver {
  final setup = ModelSetupService();

  ModelSetupSnapshot modelState = const ModelSetupSnapshot(
    phase: ModelSetupPhase.checking,
    message: '检查本机模型资产…',
  );
  bool modelBusy = false;
  bool diagnosticBusy = false;
  bool _licensePageAutoOpened = false;
  GoldenTestReport? report;
  String diagnosticStatus = '诊断未运行';

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
        _resumeAfterExternalBrowser,
      );
    }
  }

  Future<void> _resumeAfterExternalBrowser() async {
    if (!mounted || modelBusy || modelState.ready) return;

    // Returning from the official Gemma license page is different from
    // returning from Device OAuth. The OAuth token is already stored, so retry
    // the gated file request directly and never start a second authorization.
    if (modelState.phase == ModelSetupPhase.licenseRequired) {
      await _prepare();
      return;
    }

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
      void progress(ModelSetupSnapshot state) {
        if (mounted) setState(() => modelState = state);
      }

      final ModelSetupSnapshot result;
      if (resumePendingAuthorization) {
        result = await setup.resumePendingAuthorizationAndPrepare(
          onProgress: progress,
        );
      } else if (continueAfterLicense) {
        result = await setup.continueAfterLicense(onProgress: progress);
      } else if (authorize) {
        result = await setup.authorizeAndPrepare(onProgress: progress);
      } else {
        result = await setup.prepareAutomatically(onProgress: progress);
      }
      if (!mounted) return;
      setState(() => modelState = result);
      if (result.ready) {
        _licensePageAutoOpened = false;
        await widget.engine.syncSemanticIndex();
      } else if (result.licenseRequired && !_licensePageAutoOpened) {
        // OAuth succeeded, but Hugging Face reports that gated model access is
        // still unavailable. Open the official terms page once so the user can
        // perform the one legal action the app cannot do on their behalf.
        _licensePageAutoOpened = true;
        await _openLicense();
      }
    } finally {
      if (mounted) setState(() => modelBusy = false);
    }
  }

  Future<void> _openLicense() async {
    try {
      await setup.openEmbeddingLicensePage();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开官方许可页：$e')),
      );
    }
  }

  Future<void> _runGolden() async {
    if (diagnosticBusy ||
        !FlutterGemma.hasActiveModel() ||
        !FlutterGemma.hasActiveEmbedder()) {
      return;
    }
    setState(() {
      diagnosticBusy = true;
      diagnosticStatus = 'Phone Golden Test 运行中…';
    });
    try {
      final result = await GoldenTestRunner(widget.engine).run();
      if (!mounted) return;
      setState(() {
        report = result;
        diagnosticStatus = result.passed
            ? 'PHONE_FUNCTION_LOOP = PASS'
            : 'PHONE_FUNCTION_LOOP = FAIL';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => diagnosticStatus = 'Golden Test 失败：$e');
    } finally {
      if (mounted) setState(() => diagnosticBusy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gemmaReady = FlutterGemma.hasActiveModel();
    final embeddingReady = FlutterGemma.hasActiveEmbedder();
    final authorizing = modelState.phase == ModelSetupPhase.authorizing;
    final failed = modelState.phase == ModelSetupPhase.failed;
    final licenseRequired = modelState.phase == ModelSetupPhase.licenseRequired;

    return Scaffold(
      appBar: AppBar(title: const Text('模型 / 设置')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _statusRow(
                      'Gemma 4',
                      gemmaReady ? 'READY' : _gemmaPhaseLabel(),
                      gemmaReady,
                    ),
                    const Divider(),
                    _statusRow(
                      'EmbeddingGemma',
                      embeddingReady ? 'READY' : _embeddingPhaseLabel(),
                      embeddingReady,
                    ),
                    const Divider(),
                    _statusRow(
                      '本地知识索引',
                      embeddingReady
                          ? 'FTS5 + Embedding READY'
                          : 'FTS5 READY · lexical-only',
                      true,
                    ),
                    const SizedBox(height: 12),
                    Text(modelState.message),
                    if (modelState.progress != null) ...[
                      const SizedBox(height: 10),
                      LinearProgressIndicator(value: modelState.progress! / 100),
                    ],
                    if (modelBusy) ...[
                      const SizedBox(height: 10),
                      const LinearProgressIndicator(),
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
                        onPressed: () =>
                            _prepare(resumePendingAuthorization: true),
                        icon: const Icon(Icons.sync),
                        label: const Text('检查授权状态并继续'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (modelState.authorizationRequired) ...[
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Hugging Face Device OAuth',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '当前还没有可用 OAuth 凭据。无需填写 Token；完成一次官方 Device OAuth 后凭据会安全保存并自动刷新。',
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed:
                            modelBusy ? null : () => _prepare(authorize: true),
                        icon: const Icon(Icons.verified_user),
                        label: const Text('使用 Hugging Face 官方授权'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (licenseRequired) ...[
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'EmbeddingGemma 官方许可',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'OAuth 已完成。现在只差一次 EmbeddingGemma / Gemma License 接受。这是 Hugging Face 与 Google 的官方要求，App 不能代替用户同意条款。接受后返回 PocketGallery，会使用现有 OAuth token 自动继续下载，不会再次授权。',
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: modelBusy ? null : _openLicense,
                        icon: const Icon(Icons.gavel_outlined),
                        label: const Text('打开 EmbeddingGemma 官方许可页'),
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: modelBusy ? null : _prepare,
                        child: const Text('已接受许可，自动继续下载'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            ExpansionTile(
              title: const Text('高级 / 诊断'),
              subtitle: const Text('功能闭环验证与索引维护'),
              children: [
                ListTile(
                  leading: const Icon(Icons.verified_outlined),
                  title: const Text('Run Phone Golden Test'),
                  subtitle: Text(diagnosticStatus),
                  trailing: diagnosticBusy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  enabled: gemmaReady && embeddingReady && !diagnosticBusy,
                  onTap: _runGolden,
                ),
                ListTile(
                  leading: const Icon(Icons.sync),
                  title: const Text('重建全部 Embedding 索引'),
                  subtitle: const Text('仅在诊断或索引修复时执行'),
                  enabled: embeddingReady && !diagnosticBusy,
                  onTap: () async {
                    setState(() => diagnosticStatus = '重建全部 Embedding…');
                    try {
                      await widget.engine.rebuildAllEmbeddings();
                      if (mounted) {
                        setState(() => diagnosticStatus = 'Embedding 索引重建完成');
                      }
                    } catch (e) {
                      if (mounted) {
                        setState(() => diagnosticStatus = '重建失败：$e');
                      }
                    }
                  },
                ),
                if (report != null)
                  for (final gate in report!.results)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        gate.passed ? Icons.check_circle : Icons.cancel,
                      ),
                      title: Text(gate.name),
                      subtitle: Text(
                        gate.detail,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusRow(String title, String state, bool ready) => Row(
        children: [
          Icon(ready ? Icons.check_circle : Icons.hourglass_top, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(title)),
          Text(state, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      );

  String _gemmaPhaseLabel() => switch (modelState.phase) {
        ModelSetupPhase.downloadingGemma => '下载中',
        ModelSetupPhase.failed => 'ERROR',
        _ => '准备中',
      };

  String _embeddingPhaseLabel() => switch (modelState.phase) {
        ModelSetupPhase.authorizationRequired => '需要 OAuth',
        ModelSetupPhase.licenseRequired => '需要许可',
        ModelSetupPhase.authorizing => '授权中',
        ModelSetupPhase.downloadingEmbedding => '下载中',
        ModelSetupPhase.downloadingTokenizer => 'Tokenizer 下载中',
        ModelSetupPhase.failed => 'ERROR',
        _ => '准备中',
      };
}
