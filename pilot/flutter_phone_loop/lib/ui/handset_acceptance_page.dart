import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../acceptance/frame_timing_sampler.dart';
import '../acceptance/handset_acceptance_composition.dart';
import '../acceptance/handset_acceptance_models.dart';
import '../acceptance/handset_acceptance_runner.dart';
import '../acceptance/handset_report_exporter.dart';
import '../acceptance/vector_acceptance.dart';
import '../chat/chat_session_store.dart';
import '../services/knowledge_engine.dart';
import 'handset_acceptance_widgets.dart';
import 'handset_vector_interaction_page.dart';

typedef HandsetAcceptanceRunnerFactory =
    Future<HandsetAcceptanceController> Function();
typedef HandsetReportSaver = Future<Uri?> Function(
  Uint8List bytes,
  String fileName,
);

class HandsetAcceptancePage extends StatefulWidget {
  const HandsetAcceptancePage({
    super.key,
    required this.engine,
    required this.store,
    this.runnerFactory,
    this.reportSaver,
    this.now,
  });

  final KnowledgeEngine engine;
  final ChatSessionStore store;
  final HandsetAcceptanceRunnerFactory? runnerFactory;
  final HandsetReportSaver? reportSaver;
  final DateTime? now;

  @override
  State<HandsetAcceptancePage> createState() => _HandsetAcceptancePageState();
}

class _HandsetAcceptancePageState extends State<HandsetAcceptancePage>
    with WidgetsBindingObserver {
  HandsetAcceptanceController? _controller;
  HandsetAcceptanceSnapshot? _snapshot;
  bool _initializing = true;
  bool _active = false;
  bool _showEvidence = false;
  bool _exporting = false;
  bool _cancelling = false;
  bool _initializationFailed = false;
  bool _runFailed = false;
  String? _exportStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final factory = widget.runnerFactory;
      final controller = factory == null
          ? HandsetAcceptanceComposition.create(
              widget.engine,
              widget.store,
            ).runner
          : await factory();
      final recovered = await controller.recoverInterruptedCheckpoint();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _snapshot = recovered;
        _initializing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _initializationFailed = true;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed || !_active) return;
    final controller = _controller;
    if (controller == null) return;
    unawaited(_interruptSafely(controller, 'APP_BACKGROUND_INTERRUPTION'));
  }

  Future<void> _interruptSafely(
    HandsetAcceptanceController controller,
    String reasonCode,
  ) async {
    try {
      await controller.interrupt(reasonCode);
    } catch (_) {
      // The runner owns interruption evidence; lifecycle callbacks never leak.
    }
  }

  Future<void> _cancelRun() async {
    final controller = _controller;
    if (!_active ||
        _cancelling ||
        controller == null ||
        controller.interruption.value != null) {
      return;
    }
    setState(() => _cancelling = true);
    try {
      await _interruptSafely(controller, 'USER_CANCELLED');
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  Future<void> _startRun() async {
    final controller = _controller;
    if (_active || controller == null) return;
    setState(() {
      _active = true;
      _showEvidence = false;
      _exportStatus = null;
      _runFailed = false;
      if (_snapshot?.phase == HandsetRunPhase.completed) _snapshot = null;
    });
    try {
      final result = await controller.run(
        onProgress: (snapshot) {
          if (!mounted) return;
          setState(() => _snapshot = snapshot);
        },
        runInteraction: _runPhysicalInteraction,
      );
      if (!mounted) return;
      setState(() => _snapshot = result);
    } catch (_) {
      if (!mounted) return;
      setState(() => _runFailed = true);
    } finally {
      if (mounted) setState(() => _active = false);
    }
  }

  Future<VectorInteractionResult> _runPhysicalInteraction(
    VectorAcceptanceArtifact artifact,
  ) async {
    final controller = _controller;
    if (!mounted || controller == null) {
      return const VectorInteractionResult.blocked(
        'APP_BACKGROUND_INTERRUPTION',
      );
    }
    final result = await Navigator.of(context).push<VectorInteractionResult>(
      MaterialPageRoute<VectorInteractionResult>(
        fullscreenDialog: true,
        builder: (context) => HandsetVectorInteractionPage(
          artifact: artifact,
          frameTimingSampler: FrameTimingSampler(),
          interruption: controller.interruption,
        ),
      ),
    );
    return result ??
        const VectorInteractionResult.blocked('USER_ACTION_INCOMPLETE');
  }

  Future<void> _exportReport() async {
    final snapshot = _snapshot;
    if (_exporting || snapshot == null) return;
    setState(() {
      _exporting = true;
      _exportStatus = null;
    });
    try {
      final bytes = HandsetReportExporter.encodeRedacted(snapshot);
      final fileName =
          'PG_HANDSET_ACCEPTANCE_${_safeRunId(snapshot.runId)}.json';
      final saver = widget.reportSaver ?? HandsetReportExporter.saveWithPicker;
      final uri = await saver(bytes, fileName);
      if (!mounted) return;
      setState(() {
        _exportStatus = uri == null ? '用户取消导出' : '已导出：$uri';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _exportStatus = '导出失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final terminal = snapshot?.phase == HandsetRunPhase.completed && !_active;
    return PopScope<Object?>(
      canPop: !_active,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _active) unawaited(_cancelRun());
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('手机一键验收')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: <Widget>[
              if (_initializing)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Column(
                      children: <Widget>[
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('正在恢复本机验收检查点…'),
                      ],
                    ),
                  ),
                )
              else if (_initializationFailed)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('本机验收检查点暂时不可读取，请重新进入此页面。'),
                  ),
                )
              else ...<Widget>[
                if (snapshot == null && !_active)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        '一次运行完成 H1–H10：目标设备、同提交构建身份、真实模型闭环、'
                        '高维向量到三维真值、实体旋转/缩放/点选、帧时序、内存温控、'
                        '升级数据保全与脱敏报告。模型就绪状态只会在开始后检查。',
                      ),
                    ),
                  ),
                if (!terminal) ...<Widget>[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const ValueKey<String>('handset-acceptance-start'),
                      onPressed: _active ? null : _startRun,
                      icon: _active
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow),
                      label: Text(_active ? '验收运行中…' : '开始手机一键验收'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_active) ...<Widget>[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        key: const ValueKey<String>(
                          'handset-acceptance-cancel',
                        ),
                        onPressed:
                            _cancelling ||
                                _controller?.interruption.value != null
                            ? null
                            : _cancelRun,
                        icon: _cancelling
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.stop_circle_outlined),
                        label: Text(_cancelling ? '正在取消并清理…' : '取消并清理'),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
                if (_active && snapshot == null)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: LinearProgressIndicator(),
                    ),
                  ),
                if (snapshot != null && !terminal)
                  HandsetAcceptanceProgressPanel(
                    snapshot: snapshot,
                    now: widget.now,
                  ),
                if (_runFailed)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('验收运行未能完成；未显示未经审核的内部错误。请重新进入后完整重跑。'),
                    ),
                  ),
                if (terminal && snapshot != null) ...<Widget>[
                  HandsetAcceptanceTerminalCard(snapshot: snapshot),
                  const SizedBox(height: 10),
                  Column(
                    key: const ValueKey<String>('handset-terminal-actions'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      OutlinedButton.icon(
                        onPressed: () =>
                            setState(() => _showEvidence = !_showEvidence),
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text('查看证据'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _exporting ? null : _exportReport,
                        icon: _exporting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_alt),
                        label: const Text('导出脱敏报告'),
                      ),
                      FilledButton.icon(
                        onPressed: _startRun,
                        icon: const Icon(Icons.replay),
                        label: const Text('完整重跑'),
                      ),
                    ],
                  ),
                  if (_exportStatus != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(_exportStatus!),
                  ],
                  if (_showEvidence) ...<Widget>[
                    const SizedBox(height: 10),
                    HandsetAcceptanceProgressPanel(
                      snapshot: snapshot,
                      now: widget.now,
                    ),
                  ],
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _safeRunId(String value) {
    final normalized = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return normalized.isEmpty ? 'run' : normalized;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;
    if (_active &&
        controller != null &&
        controller.interruption.value == null) {
      unawaited(_interruptSafely(controller, 'USER_CANCELLED'));
    }
    super.dispose();
  }
}
