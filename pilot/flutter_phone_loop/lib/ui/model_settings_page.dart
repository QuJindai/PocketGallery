import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../acceptance/handset_acceptance_composition.dart';
import '../acceptance/handset_acceptance_models.dart';
import '../chat/chat_session_store.dart';
import '../services/golden_test_runner.dart';
import '../services/golden_test_state.dart';
import '../services/knowledge_engine.dart';
import '../services/model_setup_service.dart';
import 'handset_acceptance_page.dart';
import 'handset_acceptance_widgets.dart';

class ModelSettingsPage extends StatefulWidget {
  const ModelSettingsPage({
    super.key,
    required this.engine,
    required this.store,
    this.setupService,
    this.acceptanceSnapshotLoader,
    this.acceptancePageBuilder,
  });

  final KnowledgeEngine engine;
  final ChatSessionStore store;
  final ModelSetupService? setupService;
  final HandsetAcceptanceSnapshotLoader? acceptanceSnapshotLoader;
  final WidgetBuilder? acceptancePageBuilder;

  @override
  State<ModelSettingsPage> createState() => _ModelSettingsPageState();
}

class _ModelSettingsPageState extends State<ModelSettingsPage>
    with WidgetsBindingObserver {
  late final ModelSetupService setup;

  ModelSetupSnapshot modelState = const ModelSetupSnapshot(
    phase: ModelSetupPhase.checking,
    message: '检查本机模型资产…',
  );
  bool modelBusy = false;
  bool diagnosticBusy = false;
  bool _licensePageAutoOpened = false;
  GoldenTestReport? report;
  GoldenTestSnapshot? diagnosticSnapshot;
  String diagnosticStatus = '诊断未运行';
  int acceptanceGeneration = 0;

  @override
  void initState() {
    super.initState();
    setup = widget.setupService ?? ModelSetupService();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapModelState());
  }

  Future<HandsetAcceptanceSnapshot?> _loadAcceptanceSnapshot() {
    final loader = widget.acceptanceSnapshotLoader;
    if (loader != null) return loader();
    return HandsetAcceptanceComposition.create(
      widget.engine,
      widget.store,
    ).runner.recoverInterruptedCheckpoint();
  }

  Future<void> _openHandsetAcceptance() async {
    final customBuilder = widget.acceptancePageBuilder;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: customBuilder ??
            (context) => HandsetAcceptancePage(
                  engine: widget.engine,
                  store: widget.store,
                ),
      ),
    );
    if (!mounted) return;
    setState(() => acceptanceGeneration += 1);
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
      report = null;
      diagnosticSnapshot = null;
      diagnosticStatus = 'Phone Golden Test 运行中…';
    });
    try {
      final result = await GoldenTestRunner(widget.engine).run(
        onProgress: (snapshot) {
          if (!mounted) return;
          setState(() {
            diagnosticSnapshot = snapshot;
            diagnosticStatus = 'Phone Golden Test · ${snapshot.percent}%';
          });
        },
      );
      if (!mounted) return;
      setState(() {
        report = result;
        diagnosticSnapshot = result.snapshot;
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
            const SizedBox(height: 10),
            HandsetAcceptanceEntryCard(
              key: ValueKey<String>(
                'handset-acceptance-entry-generation-$acceptanceGeneration',
              ),
              recoverLatest: _loadAcceptanceSnapshot,
              onOpen: () => unawaited(_openHandsetAcceptance()),
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
                if (diagnosticSnapshot != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: GoldenTestProgressPanel(
                      snapshot: diagnosticSnapshot!,
                    ),
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
                if (report != null && diagnosticSnapshot == null)
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
          Expanded(flex: 4, child: Text(title)),
          const SizedBox(width: 8),
          Flexible(
            flex: 5,
            child: Text(
              state,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
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

class GoldenTestProgressPanel extends StatefulWidget {
  const GoldenTestProgressPanel({
    super.key,
    required this.snapshot,
    this.now,
  });

  final GoldenTestSnapshot snapshot;

  /// Fixed wall clock for deterministic widget tests. Production callers leave
  /// this null so elapsed time refreshes once per second during a run.
  final DateTime? now;

  @override
  State<GoldenTestProgressPanel> createState() =>
      _GoldenTestProgressPanelState();
}

class _GoldenTestProgressPanelState extends State<GoldenTestProgressPanel> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant GoldenTestProgressPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  void _syncTicker() {
    _ticker?.cancel();
    _ticker = null;
    if (widget.now != null ||
        widget.snapshot.phase == GoldenRunPhase.completed) {
      return;
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final gateCount = snapshot.gates.length;
    final current = snapshot.currentGate;
    final currentIndex = current == null
        ? -1
        : snapshot.gates.indexWhere((gate) => gate.name == current.name);
    final elapsedEnd = snapshot.phase == GoldenRunPhase.completed
        ? snapshot.updatedAt
        : widget.now ?? DateTime.now();
    final elapsed = elapsedEnd.isBefore(snapshot.startedAt)
        ? Duration.zero
        : elapsedEnd.difference(snapshot.startedAt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Phone Golden Test · F1–F10',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Text(
              '${snapshot.percent}%',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: snapshot.percent / 100),
        const SizedBox(height: 8),
        Text(_currentLabel(snapshot, current, currentIndex, gateCount)),
        Text('已完成：${snapshot.completedCount}/$gateCount'),
        Text('已用时：${_formatDuration(elapsed)}'),
        const Text('检查点：PG_GOLDEN_LAST.json · 已保存'),
        const SizedBox(height: 6),
        const Text(
          'F6/F7 需在实体手机使用已激活的 Gemma 4 与 EmbeddingGemma 执行；F8–F10 校验其持久化血缘。',
          style: TextStyle(fontSize: 12),
        ),
        const Divider(),
        for (final gate in snapshot.gates) _gateRow(gate),
        if (snapshot.phase == GoldenRunPhase.completed) ...[
          const Divider(),
          Text(
            snapshot.passed
                ? 'PHONE_FUNCTION_LOOP = PASS'
                : 'PHONE_FUNCTION_LOOP = FAIL',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: snapshot.passed ? Colors.green : Colors.red,
            ),
          ),
          if (snapshot.cleanupError != null)
            Text(
              '清理失败：${snapshot.cleanupError}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ],
    );
  }

  String _currentLabel(
    GoldenTestSnapshot snapshot,
    GoldenGateSnapshot? current,
    int currentIndex,
    int gateCount,
  ) {
    if (current != null) {
      return '当前：F${currentIndex + 1}/$gateCount · ${current.label}';
    }
    if (snapshot.phase == GoldenRunPhase.cleaningUp) return '当前：清理阶段';
    return '当前：已完成';
  }

  Widget _gateRow(GoldenGateSnapshot gate) {
    final presentation = _gatePresentation(gate.status);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(presentation.icon, size: 20, color: presentation.color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${gate.name} · ${gate.label}'),
                if (gate.detail.isNotEmpty)
                  Text(
                    gate.detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(presentation.label),
        ],
      ),
    );
  }
}

_GoldenGatePresentation _gatePresentation(GoldenGateStatus status) {
  return switch (status) {
    GoldenGateStatus.pending => const _GoldenGatePresentation(
        Icons.schedule_outlined,
        '等待',
        Colors.grey,
      ),
    GoldenGateStatus.running => const _GoldenGatePresentation(
        Icons.sync,
        '运行中',
        Colors.blue,
      ),
    GoldenGateStatus.passed => const _GoldenGatePresentation(
        Icons.check_circle,
        '通过',
        Colors.green,
      ),
    GoldenGateStatus.failed => const _GoldenGatePresentation(
        Icons.cancel,
        '失败',
        Colors.red,
      ),
    GoldenGateStatus.timedOut => const _GoldenGatePresentation(
        Icons.timer_off,
        '超时',
        Colors.orange,
      ),
    GoldenGateStatus.blocked => const _GoldenGatePresentation(
        Icons.block,
        '已阻断',
        Colors.deepOrange,
      ),
  };
}

class _GoldenGatePresentation {
  const _GoldenGatePresentation(this.icon, this.label, this.color);

  final IconData icon;
  final String label;
  final Color color;
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
  return '$minutes:$seconds';
}
