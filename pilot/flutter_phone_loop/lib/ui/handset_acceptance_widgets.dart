import 'dart:async';

import 'package:flutter/material.dart';

import '../acceptance/handset_acceptance_models.dart';
import '../services/golden_test_state.dart';

typedef HandsetAcceptanceSnapshotLoader =
    Future<HandsetAcceptanceSnapshot?> Function();

class HandsetAcceptanceEntryCard extends StatefulWidget {
  const HandsetAcceptanceEntryCard({
    super.key,
    required this.recoverLatest,
    required this.onOpen,
  });

  final HandsetAcceptanceSnapshotLoader recoverLatest;
  final VoidCallback onOpen;

  @override
  State<HandsetAcceptanceEntryCard> createState() =>
      _HandsetAcceptanceEntryCardState();
}

class _HandsetAcceptanceEntryCardState
    extends State<HandsetAcceptanceEntryCard> {
  HandsetAcceptanceSnapshot? _latest;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _recover();
  }

  Future<void> _recover() async {
    HandsetAcceptanceSnapshot? latest;
    try {
      latest = await widget.recoverLatest();
    } catch (_) {
      // The entry remains usable even when the local checkpoint is unreadable.
    }
    if (!mounted) return;
    setState(() {
      _latest = latest;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final latest = _latest;
    final colors = Theme.of(context).colorScheme;
    return Card(
      key: const ValueKey<String>('handset-acceptance-entry'),
      color: colors.primaryContainer,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.phonelink_setup, color: colors.onPrimaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '手机一键验收',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text('S24 Ultra · H1–H10 · 高维关系 3D 实体交互'),
                    const SizedBox(height: 8),
                    if (_loading)
                      const Text('正在恢复上次验收…')
                    else ...<Widget>[
                      Text(_latestLabel(latest)),
                      Text(_baselineLabel(latest)),
                      if (_wasRecoveredAfterInterruption(latest))
                        const Text('上次验收已安全恢复：进程中断'),
                    ],
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 18),
                child: Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _latestLabel(HandsetAcceptanceSnapshot? snapshot) {
    if (snapshot == null) return '最近结果：未运行';
    return switch (snapshot.verdict) {
      AcceptanceVerdict.pass => '最近结果：PASS · 通过',
      AcceptanceVerdict.fail => '最近结果：FAIL · 失败',
      AcceptanceVerdict.blocked => '最近结果：BLOCKED · 受阻',
    };
  }

  String _baselineLabel(HandsetAcceptanceSnapshot? snapshot) {
    final version = snapshot?.baselineVersionCode;
    return version == null ? '升级基线：待建立' : '升级基线：版本 $version';
  }

  bool _wasRecoveredAfterInterruption(HandsetAcceptanceSnapshot? snapshot) {
    return snapshot?.gates.any(
          (gate) => gate.detail.split('|').contains('PROCESS_INTERRUPTED'),
        ) ??
        false;
  }
}

class HandsetAcceptanceProgressPanel extends StatefulWidget {
  const HandsetAcceptanceProgressPanel({
    super.key,
    required this.snapshot,
    this.now,
  });

  final HandsetAcceptanceSnapshot snapshot;
  final DateTime? now;

  @override
  State<HandsetAcceptanceProgressPanel> createState() =>
      _HandsetAcceptanceProgressPanelState();
}

class _HandsetAcceptanceProgressPanelState
    extends State<HandsetAcceptanceProgressPanel> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant HandsetAcceptanceProgressPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  void _syncTicker() {
    _ticker?.cancel();
    _ticker = null;
    if (widget.now != null ||
        widget.snapshot.phase == HandsetRunPhase.completed) {
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
    final current = _currentGate(snapshot);
    final currentIndex = current == null
        ? -1
        : snapshot.gates.indexWhere((gate) => gate.name == current.name);
    final elapsedEnd = snapshot.phase == HandsetRunPhase.completed
        ? snapshot.updatedAt
        : widget.now ?? DateTime.now();
    final elapsed = elapsedEnd.isBefore(snapshot.startedAt)
        ? Duration.zero
        : elapsedEnd.difference(snapshot.startedAt);
    final metrics = _metricLabels(snapshot);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    '实体手机验收 · H1–H10',
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
            Text(_currentLabel(snapshot, current, currentIndex)),
            Text('已用时：${_formatDuration(elapsed)}'),
            const Text('检查点：PG_HANDSET_ACCEPTANCE_LAST.json · 已保存'),
            if (metrics.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 5,
                children: <Widget>[for (final metric in metrics) Text(metric)],
              ),
            ],
            const Divider(),
            for (final gate in snapshot.gates) _HandsetGateRow(gate: gate),
            if (snapshot.nestedGolden != null) ...<Widget>[
              const Divider(),
              _NestedGoldenProgress(snapshot: snapshot.nestedGolden!),
            ],
          ],
        ),
      ),
    );
  }

  HandsetGateSnapshot? _currentGate(HandsetAcceptanceSnapshot snapshot) {
    for (final gate in snapshot.gates) {
      if (gate.status == HandsetGateStatus.running) return gate;
    }
    for (final gate in snapshot.gates) {
      if (gate.status == HandsetGateStatus.pending) return gate;
    }
    return null;
  }

  String _currentLabel(
    HandsetAcceptanceSnapshot snapshot,
    HandsetGateSnapshot? current,
    int currentIndex,
  ) {
    if (current != null) {
      return '当前：H${currentIndex + 1}/${snapshot.gates.length} · '
          '${handsetGateChineseLabel(current.name)}';
    }
    if (snapshot.phase == HandsetRunPhase.cleaningUp) return '当前：清理阶段';
    return '当前：已完成';
  }
}

class _HandsetGateRow extends StatelessWidget {
  const _HandsetGateRow({required this.gate});

  final HandsetGateSnapshot gate;

  @override
  Widget build(BuildContext context) {
    final presentation = _gatePresentation(gate.status);
    final reason = _humanReason(gate.detail);
    final children = <Widget>[
      if (reason != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('说明：$reason'),
          ),
        ),
      for (final evidence in gate.evidence)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(_evidenceLabel(evidence)),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '开发者详情：${gate.name}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ),
    ];
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      leading: Icon(presentation.icon, color: presentation.color, size: 20),
      title: Text(
        '${gate.name.substring(0, gate.name.indexOf('_'))} · '
        '${handsetGateChineseLabel(gate.name)}',
      ),
      trailing: Text(presentation.label),
      children: children,
    );
  }
}

class _NestedGoldenProgress extends StatelessWidget {
  const _NestedGoldenProgress({required this.snapshot});

  final GoldenTestSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: const ValueKey<String>('nested-golden-progress'),
      tilePadding: EdgeInsets.zero,
      title: const Text('Phone Golden Test · F1–F10'),
      subtitle: Text('${snapshot.percent}% · ${snapshot.completedCount}/10'),
      children: <Widget>[
        for (final gate in snapshot.gates)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: Icon(
              _goldenPresentation(gate.status).icon,
              color: _goldenPresentation(gate.status).color,
              size: 19,
            ),
            title: Text('${gate.name} · ${gate.label}'),
            trailing: Text(_goldenPresentation(gate.status).label),
          ),
      ],
    );
  }
}

class HandsetAcceptanceTerminalCard extends StatelessWidget {
  const HandsetAcceptanceTerminalCard({super.key, required this.snapshot});

  final HandsetAcceptanceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final verdict = snapshot.verdict;
    final colors = Theme.of(context).colorScheme;
    final presentation = switch (verdict) {
      AcceptanceVerdict.pass => (
        key: const ValueKey<String>('handset-terminal-pass'),
        title: '验收通过',
        code: 'DEVICE_ACCEPTANCE = PASS',
        icon: Icons.verified,
        color: colors.tertiaryContainer,
        foreground: colors.onTertiaryContainer,
      ),
      AcceptanceVerdict.fail => (
        key: const ValueKey<String>('handset-terminal-fail'),
        title: '验收失败',
        code: 'DEVICE_ACCEPTANCE = FAIL',
        icon: Icons.cancel,
        color: colors.errorContainer,
        foreground: colors.onErrorContainer,
      ),
      AcceptanceVerdict.blocked => (
        key: const ValueKey<String>('handset-terminal-blocked'),
        title: '验收受阻',
        code: 'DEVICE_ACCEPTANCE = BLOCKED',
        icon: Icons.warning_amber_rounded,
        color: colors.secondaryContainer,
        foreground: colors.onSecondaryContainer,
      ),
    };
    final problemCode = _terminalProblemCode(snapshot);
    return Card(
      key: presentation.key,
      color: presentation.color,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(presentation.icon, color: presentation.foreground),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    presentation.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: presentation.foreground,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              presentation.code,
              style: TextStyle(
                color: presentation.foreground,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (verdict == AcceptanceVerdict.pass) ...<Widget>[
              const Text('原因：H1–H10 全部通过，实体交互与设备证据完整。'),
              const Text('建议：导出脱敏报告，用于同提交最终裁决。'),
            ] else ...<Widget>[
              Text('原因：${_terminalReason(problemCode)}'),
              Text('建议：${_terminalRemediation(problemCode)}'),
            ],
          ],
        ),
      ),
    );
  }
}

String handsetGateChineseLabel(String name) => switch (name) {
  'H1_TARGET_DEVICE' => '目标设备',
  'H2_BUILD_IDENTITY' => '构建身份',
  'H3_UPGRADE_BASELINE' => '升级基线',
  'H4_PHONE_FUNCTION_LOOP' => '手机功能闭环',
  'H5_VECTOR_3D_TRUTH' => '高维向量 → 三维真值',
  'H6_VECTOR_INTERACTION' => '实体 3D 交互',
  'H7_RENDER_PERFORMANCE' => '渲染性能',
  'H8_MEMORY_THERMAL' => '内存与温控',
  'H9_DATA_PRESERVATION' => '数据保全',
  'H10_REPORT_INTEGRITY' => '报告完整性',
  _ => '未知验收门',
};

List<String> _metricLabels(HandsetAcceptanceSnapshot snapshot) {
  final labels = <String>[];
  void add(String code, String label) {
    final evidence = _findEvidence(snapshot, code);
    if (evidence == null || !evidence.available) return;
    final value = _safeEvidenceValue(evidence);
    if (value == null) return;
    labels.add('$label：$value');
  }

  add('FRAME_P95_MS', '帧 P95');
  add('BASELINE_PSS_KIB', '基线 PSS');
  add('FINAL_PSS_GROWTH_KIB', 'PSS 增长');
  add('MIN_AVAILABLE_MEMORY_BYTES', '最低可用内存');
  add('PEAK_BATTERY_TEMPERATURE_C', '电池温度峰值');
  add('MAX_THERMAL_STATUS', '最高热状态');
  return labels;
}

AcceptanceEvidence? _findEvidence(
  HandsetAcceptanceSnapshot snapshot,
  String code,
) {
  for (final gate in snapshot.gates) {
    for (final evidence in gate.evidence) {
      if (evidence.code == code) return evidence;
    }
  }
  return null;
}

String _evidenceLabel(AcceptanceEvidence evidence) {
  final label = _evidenceChineseLabel(evidence.code);
  final actual = _safeEvidenceValue(evidence) ?? '不可用或已隐藏';
  final threshold = _safeThreshold(evidence.threshold);
  return threshold == null
      ? '$label：$actual'
      : '$label：$actual · 门槛 $threshold';
}

String _evidenceChineseLabel(String code) => switch (code) {
  'TARGET_MANUFACTURER' => '制造商',
  'TARGET_MODEL' => '机型',
  'PACKAGE_NAME' => '包名',
  'VERSION_CODE' => '版本码',
  'SIGNER_SHA256' => '签名摘要',
  'APK_SHA256' => 'APK 摘要',
  'SOURCE_COMMIT' => '源码提交',
  'FRAME_P95_MS' => '帧 P95',
  'BASELINE_PSS_KIB' => '基线 PSS',
  'FINAL_PSS_GROWTH_KIB' => 'PSS 增长',
  'MIN_AVAILABLE_MEMORY_BYTES' => '最低可用内存',
  'MAX_THERMAL_STATUS' => '最高热状态',
  'PEAK_BATTERY_TEMPERATURE_C' => '电池温度峰值',
  _ => '已记录证据',
};

String? _safeEvidenceValue(AcceptanceEvidence evidence) {
  final actual = evidence.actual;
  if (actual == null) return null;
  final scalar = switch (actual) {
    num value => value.toString(),
    bool value => value ? '是' : '否',
    String value => _approvedEvidenceString(evidence.code, value),
    _ => null,
  };
  if (scalar == null) return null;
  final unit = _approvedUnit(evidence.unit);
  return unit == null ? scalar : '$scalar $unit';
}

String? _approvedEvidenceString(String code, String value) {
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.length > 128) return null;
  if (RegExp(
    r'(authorization|credential|password|secret|token|bearer\s+|hf_[a-z0-9])',
    caseSensitive: false,
  ).hasMatch(normalized)) {
    return null;
  }
  return switch (code) {
    'TARGET_MANUFACTURER' =>
      normalized.toLowerCase() == 'samsung' ? normalized : null,
    'TARGET_MODEL' =>
      RegExp(r'^SM-S928[A-Z0-9]*$', caseSensitive: false).hasMatch(normalized)
          ? normalized
          : null,
    'PACKAGE_NAME' =>
      RegExp(r'^[a-z0-9._]+$').hasMatch(normalized) ? normalized : null,
    'SIGNER_SHA256' || 'APK_SHA256' =>
      RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(normalized)
          ? normalized.toLowerCase()
          : null,
    'SOURCE_COMMIT' =>
      RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(normalized)
          ? normalized.toLowerCase()
          : null,
    _ => null,
  };
}

String? _approvedUnit(String? unit) {
  const allowed = <String>{
    'ms',
    'Hz',
    'KiB',
    'MiB',
    'bytes',
    '°C',
    '%',
    'frames',
    'count',
  };
  return allowed.contains(unit) ? unit : null;
}

String? _safeThreshold(Object? threshold) {
  if (threshold == null) return null;
  if (threshold is num) return threshold.toString();
  if (threshold is bool) return threshold ? '是' : '否';
  if (threshold is! String || threshold.length > 128) return null;
  if (RegExp(
    r'(authorization|credential|password|secret|token|bearer\s+|hf_[a-z0-9])',
    caseSensitive: false,
  ).hasMatch(threshold)) {
    return null;
  }
  return threshold;
}

String? _humanReason(String detail) {
  if (detail.isEmpty) return null;
  final code = detail.split('|').first;
  return _knownReason(code);
}

String? _knownReason(String code) => switch (code) {
  'PROCESS_INTERRUPTED' => '上次进程中断，已完成幂等清理',
  'MODEL_PREREQUISITE_MISSING' => '本机模型尚未就绪',
  'APP_BACKGROUND_INTERRUPTION' => '验收期间 App 离开前台',
  'USER_ACTION_INCOMPLETE' => '实体 3D 交互尚未完成',
  'RENDER_PERFORMANCE_REGRESSION' => '渲染性能未达到实体机门槛',
  'MEMORY_PRESSURE' => '内存压力超过门槛',
  'THERMAL_LIMIT_EXCEEDED' => '设备热状态超过门槛',
  'REQUIRED_EVIDENCE_UNAVAILABLE' => '必要设备证据不可用',
  _ => null,
};

String? _terminalProblemCode(HandsetAcceptanceSnapshot snapshot) {
  if (snapshot.cleanupError != null) return 'KNOWN_FIXTURE_CLEANUP_FAILED';
  for (final gate in snapshot.gates) {
    if (gate.status == HandsetGateStatus.failed ||
        gate.status == HandsetGateStatus.timedOut) {
      return gate.detail.split('|').first;
    }
  }
  for (final gate in snapshot.gates) {
    if (gate.status == HandsetGateStatus.blocked) {
      return gate.detail.split('|').first;
    }
  }
  return null;
}

String _terminalReason(String? code) {
  return _knownReason(code ?? '') ?? '必要验收门未通过或证据不完整';
}

String _terminalRemediation(String? code) => switch (code) {
  'RENDER_PERFORMANCE_REGRESSION' => '重新执行三维交互，避免系统负载干扰；若仍失败，检查帧时序证据。',
  'MODEL_PREREQUISITE_MISSING' => '先在模型设置完成 Gemma 4 与 EmbeddingGemma 准备，再完整重跑。',
  'APP_BACKGROUND_INTERRUPTION' ||
  'PROCESS_INTERRUPTED' => '保持 App 在前台，确认清理完成后执行完整重跑。',
  'USER_ACTION_INCOMPLETE' => '完成旋转、双指缩放、点选和界面确认后重跑。',
  'MEMORY_PRESSURE' => '关闭占用内存的应用，等待系统稳定后完整重跑。',
  'THERMAL_LIMIT_EXCEEDED' => '等待手机降温并移除外部热源后完整重跑。',
  _ => '查看证据中的首个未通过验收门，处理后执行完整重跑。',
};

_GatePresentation _gatePresentation(HandsetGateStatus status) {
  return switch (status) {
    HandsetGateStatus.pending => const _GatePresentation(
      Icons.schedule_outlined,
      '等待',
      Colors.grey,
    ),
    HandsetGateStatus.running => const _GatePresentation(
      Icons.sync,
      '运行中',
      Colors.blue,
    ),
    HandsetGateStatus.passed => const _GatePresentation(
      Icons.check_circle,
      '通过',
      Colors.green,
    ),
    HandsetGateStatus.failed => const _GatePresentation(
      Icons.cancel,
      '失败',
      Colors.red,
    ),
    HandsetGateStatus.timedOut => const _GatePresentation(
      Icons.timer_off,
      '超时',
      Colors.orange,
    ),
    HandsetGateStatus.blocked => const _GatePresentation(
      Icons.block,
      '受阻',
      Colors.deepOrange,
    ),
  };
}

_GatePresentation _goldenPresentation(GoldenGateStatus status) {
  return switch (status) {
    GoldenGateStatus.pending => const _GatePresentation(
      Icons.schedule_outlined,
      '等待',
      Colors.grey,
    ),
    GoldenGateStatus.running => const _GatePresentation(
      Icons.sync,
      '运行中',
      Colors.blue,
    ),
    GoldenGateStatus.passed => const _GatePresentation(
      Icons.check_circle,
      '通过',
      Colors.green,
    ),
    GoldenGateStatus.failed => const _GatePresentation(
      Icons.cancel,
      '失败',
      Colors.red,
    ),
    GoldenGateStatus.timedOut => const _GatePresentation(
      Icons.timer_off,
      '超时',
      Colors.orange,
    ),
    GoldenGateStatus.blocked => const _GatePresentation(
      Icons.block,
      '受阻',
      Colors.deepOrange,
    ),
  };
}

class _GatePresentation {
  const _GatePresentation(this.icon, this.label, this.color);

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
