import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketgallery_phone_pilot/acceptance/handset_acceptance_models.dart';
import 'package:pocketgallery_phone_pilot/acceptance/handset_acceptance_runner.dart';
import 'package:pocketgallery_phone_pilot/acceptance/handset_report_exporter.dart';
import 'package:pocketgallery_phone_pilot/acceptance/vector_acceptance.dart';
import 'package:pocketgallery_phone_pilot/chat/chat_session_store.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_models.dart';
import 'package:pocketgallery_phone_pilot/observability/trace_vector_space_service.dart';
import 'package:pocketgallery_phone_pilot/services/golden_test_state.dart';
import 'package:pocketgallery_phone_pilot/services/knowledge_engine.dart';
import 'package:pocketgallery_phone_pilot/services/model_setup_service.dart';
import 'package:pocketgallery_phone_pilot/ui/handset_acceptance_page.dart';
import 'package:pocketgallery_phone_pilot/ui/handset_acceptance_widgets.dart';
import 'package:pocketgallery_phone_pilot/ui/model_settings_page.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('R5.0 prominent handset entry', () {
    testWidgets(
        'entry stays above Advanced while models are unavailable and opens one full-screen route',
        (tester) async {
      _setPhoneSize(tester);
      final database = sqlite3.openInMemory();
      addTearDown(database.close);
      final latest = _terminalSnapshot(AcceptanceVerdict.pass);

      await tester.pumpWidget(
        MaterialApp(
          home: ModelSettingsPage(
            engine: KnowledgeEngine(),
            store: ChatSessionStore(database: database),
            setupService: _UnavailableModelSetupService(),
            acceptanceSnapshotLoader: () async => latest,
            acceptancePageBuilder: (context) => const Scaffold(
              body: Center(child: Text('S24U acceptance full screen')),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final entry = find.byKey(
        const ValueKey<String>('handset-acceptance-entry'),
      );
      expect(entry, findsOneWidget);
      expect(find.text('手机一键验收'), findsOneWidget);
      expect(find.text('最近结果：PASS · 通过'), findsOneWidget);
      expect(find.text('升级基线：版本 2022'), findsOneWidget);
      expect(
        tester.getTopLeft(entry).dy,
        lessThan(tester.getTopLeft(find.text('高级 / 诊断')).dy),
      );

      await tester.tap(entry);
      await tester.pumpAndSettle();

      expect(find.text('S24U acceptance full screen'), findsOneWidget);
      expect(find.text('模型 / 设置'), findsNothing);
    });

    testWidgets(
        'entry waits for checkpoint recovery before exposing an interrupted result',
        (tester) async {
      final recovery = Completer<HandsetAcceptanceSnapshot?>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HandsetAcceptanceEntryCard(
              recoverLatest: () => recovery.future,
              onOpen: () {},
            ),
          ),
        ),
      );

      expect(find.text('正在恢复上次验收…'), findsOneWidget);
      expect(find.textContaining('进程中断'), findsNothing);

      recovery.complete(_interruptedSnapshot());
      await tester.pump();
      await tester.pump();

      expect(find.text('最近结果：BLOCKED · 受阻'), findsOneWidget);
      expect(find.text('上次验收已安全恢复：进程中断'), findsOneWidget);
    });
  });

  group('R5.0 handset dashboard', () {
    testWidgets(
        'running H4 renders determinate outer progress and expandable real F1-F10 progress',
        (tester) async {
      _setPhoneSize(tester);
      final running = _runningH4Snapshot();
      final controller = _FakeHandsetController(
        progress: <HandsetAcceptanceSnapshot>[running],
        holdRun: true,
      );
      await _pumpAcceptancePage(tester, controller);

      await tester.tap(find.text('开始手机一键验收'));
      await tester.pump();

      expect(find.text('35%'), findsOneWidget);
      expect(find.text('当前：H4/10 · 手机功能闭环'), findsOneWidget);
      expect(find.text('已用时：00:12'), findsOneWidget);
      expect(
        find.text('检查点：PG_HANDSET_ACCEPTANCE_LAST.json · 已保存'),
        findsOneWidget,
      );
      final startButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey<String>('handset-acceptance-start')),
      );
      expect(startButton.onPressed, isNull);

      await tester.scrollUntilVisible(
        find.text('Phone Golden Test · F1–F10'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Phone Golden Test · F1–F10'));
      await tester.pumpAndSettle();
      expect(find.text('F1 · Golden gate 1'), findsOneWidget);
      expect(find.text('F10 · Golden gate 10'), findsOneWidget);

      controller.complete(_terminalSnapshot(AcceptanceVerdict.pass));
      await tester.pumpAndSettle();
    });

    testWidgets('awaiting H6 opens the real guided high-dimensional 3D route',
        (tester) async {
      _setPhoneSize(tester);
      final controller = _FakeHandsetController(
        progress: <HandsetAcceptanceSnapshot>[_awaitingH6Snapshot()],
        interactionArtifact: _vectorArtifact,
      );
      await _pumpAcceptancePage(tester, controller);

      await tester.tap(find.text('开始手机一键验收'));
      await tester.pump();
      await tester.pump();

      expect(find.text('高维关系 · 物理交互验收'), findsOneWidget);
      expect(find.textContaining('768D → 3D'), findsWidgets);

      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(controller.interactionResult?.reasonCode, 'USER_ACTION_INCOMPLETE');
      expect(find.text('验收受阻'), findsOneWidget);
    });

    testWidgets('running post-checks expose frame and handset resource evidence',
        (tester) async {
      _setPhoneSize(tester);
      final controller = _FakeHandsetController(
        progress: <HandsetAcceptanceSnapshot>[_runningResourcesSnapshot()],
        holdRun: true,
      );
      await _pumpAcceptancePage(tester, controller);

      await tester.tap(find.text('开始手机一键验收'));
      await tester.pump();

      for (final metric in <String>[
        '帧 P95：14.2 ms',
        '基线 PSS：320000 KiB',
        '最低可用内存：4000000000 bytes',
        '电池温度峰值：38.4 °C',
        '最高热状态：2',
      ]) {
        expect(find.text(metric), findsOneWidget);
      }

      controller.complete(_terminalSnapshot(AcceptanceVerdict.pass));
      await tester.pumpAndSettle();
    });

    testWidgets('PASS uses the green terminal card and only three run actions',
        (tester) async {
      _setPhoneSize(tester);
      await _pumpCompletedRun(
        tester,
        _terminalSnapshot(AcceptanceVerdict.pass),
      );

      expect(find.text('验收通过'), findsOneWidget);
      expect(find.text('DEVICE_ACCEPTANCE = PASS'), findsOneWidget);
      _expectOnlyTerminalActions(tester);
      final card = tester.widget<Card>(
        find.byKey(const ValueKey<String>('handset-terminal-pass')),
      );
      expect(card.color, Theme.of(tester.element(find.text('验收通过')))
          .colorScheme
          .tertiaryContainer);
    });

    testWidgets('FAIL stays distinct from BLOCKED and explains remediation',
        (tester) async {
      _setPhoneSize(tester);
      await _pumpCompletedRun(
        tester,
        _terminalSnapshot(AcceptanceVerdict.fail),
      );

      expect(find.text('验收失败'), findsOneWidget);
      expect(find.text('DEVICE_ACCEPTANCE = FAIL'), findsOneWidget);
      expect(find.text('原因：渲染性能未达到实体机门槛'), findsOneWidget);
      expect(find.textContaining('建议：重新执行三维交互'), findsOneWidget);
      _expectOnlyTerminalActions(tester);
    });

    testWidgets(
        'missing models are not pre-checked and become truthful BLOCKED only after start',
        (tester) async {
      _setPhoneSize(tester);
      await _pumpAcceptancePage(
        tester,
        _FakeHandsetController(
          terminal: _terminalSnapshot(AcceptanceVerdict.blocked),
        ),
      );

      expect(find.textContaining('本机模型尚未就绪'), findsNothing);
      await tester.tap(find.text('开始手机一键验收'));
      await tester.pumpAndSettle();

      expect(find.text('验收受阻'), findsOneWidget);
      expect(find.text('DEVICE_ACCEPTANCE = BLOCKED'), findsOneWidget);
      expect(find.text('原因：本机模型尚未就绪'), findsOneWidget);
      expect(find.textContaining('建议：先在模型设置完成'), findsOneWidget);
      _expectOnlyTerminalActions(tester);
    });
  });

  group('R5.0 lifecycle and redacted export', () {
    testWidgets('leaving resumed state interrupts the single active run',
        (tester) async {
      _setPhoneSize(tester);
      final controller = _FakeHandsetController(
        progress: <HandsetAcceptanceSnapshot>[_runningH4Snapshot()],
        holdRun: true,
      );
      await _pumpAcceptancePage(tester, controller);
      await tester.tap(find.text('开始手机一键验收'));
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.paused,
      );
      await tester.pump();

      expect(controller.interruption.value, 'APP_BACKGROUND_INTERRUPTION');
      expect(controller.interruptReasons, <String>[
        'APP_BACKGROUND_INTERRUPTION',
      ]);

      controller.complete(_terminalSnapshot(AcceptanceVerdict.blocked));
      tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await tester.pumpAndSettle();
    });

    testWidgets('active run exposes one visible cancel-and-cleanup action',
        (tester) async {
      _setPhoneSize(tester);
      final controller = _FakeHandsetController(
        progress: <HandsetAcceptanceSnapshot>[_runningH4Snapshot()],
        holdRun: true,
      );
      await _pumpAcceptancePage(tester, controller);
      await tester.tap(find.text('开始手机一键验收'));
      await tester.pump();

      final cancel = find.byKey(
        const ValueKey<String>('handset-acceptance-cancel'),
      );
      expect(cancel, findsOneWidget);
      expect(find.text('取消并清理'), findsOneWidget);
      await tester.tap(cancel);
      await tester.pump();

      expect(controller.interruptReasons, <String>['USER_CANCELLED']);
      controller.complete(_terminalSnapshot(AcceptanceVerdict.blocked));
      await tester.pumpAndSettle();
    });

    testWidgets('system back interrupts and retains an active acceptance route',
        (tester) async {
      _setPhoneSize(tester);
      final controller = _FakeHandsetController(
        progress: <HandsetAcceptanceSnapshot>[_runningH4Snapshot()],
        holdRun: true,
      );
      await _pumpAcceptancePage(tester, controller);
      await tester.tap(find.text('开始手机一键验收'));
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(controller.interruptReasons, <String>['USER_CANCELLED']);
      expect(find.text('手机一键验收'), findsOneWidget);
      controller.complete(_terminalSnapshot(AcceptanceVerdict.blocked));
      await tester.pumpAndSettle();
    });

    testWidgets('disposing an active page performs best-effort interruption',
        (tester) async {
      _setPhoneSize(tester);
      final controller = _FakeHandsetController(
        progress: <HandsetAcceptanceSnapshot>[_runningH4Snapshot()],
        holdRun: true,
      );
      await _pumpAcceptancePage(tester, controller);
      await tester.tap(find.text('开始手机一键验收'));
      await tester.pump();

      await tester.pumpWidget(
        const MaterialApp(home: SizedBox.shrink()),
      );
      await tester.pump();

      expect(controller.interruptReasons, <String>['USER_CANCELLED']);
      controller.complete(_terminalSnapshot(AcceptanceVerdict.blocked));
      await tester.pump();
    });

    testWidgets('export saves exact allow-listed bytes and never renders a token',
        (tester) async {
      _setPhoneSize(tester);
      final terminal = _terminalSnapshot(
        AcceptanceVerdict.pass,
        includeSensitiveEvidence: true,
      );
      Uint8List? savedBytes;
      String? savedName;
      final controller = _FakeHandsetController(recovered: terminal);
      await _pumpAcceptancePage(
        tester,
        controller,
        reportSaver: (bytes, fileName) async {
          savedBytes = bytes;
          savedName = fileName;
          return Uri.parse('content://exports/PG_HANDSET_ACCEPTANCE.json');
        },
      );

      await tester.tap(find.text('查看证据'));
      await tester.pump();
      expect(_visibleText(tester), isNot(contains('hf_super_secret_token')));

      await tester.tap(find.text('导出脱敏报告'));
      await tester.pumpAndSettle();

      expect(savedName, 'PG_HANDSET_ACCEPTANCE_r50-terminal.json');
      expect(
        savedBytes,
        orderedEquals(HandsetReportExporter.encodeRedacted(terminal)),
      );
      expect(utf8.decode(savedBytes!), isNot(contains('hf_super_secret_token')));
      expect(
        find.text(
          '已导出：content://exports/PG_HANDSET_ACCEPTANCE.json',
        ),
        findsOneWidget,
      );
    });
  });
}

void _setPhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpAcceptancePage(
  WidgetTester tester,
  _FakeHandsetController controller, {
  HandsetReportSaver? reportSaver,
}) async {
  final database = sqlite3.openInMemory();
  addTearDown(database.close);
  await tester.pumpWidget(
    MaterialApp(
      home: HandsetAcceptancePage(
        engine: KnowledgeEngine(),
        store: ChatSessionStore(database: database),
        runnerFactory: () async => controller,
        reportSaver: reportSaver,
        now: _now,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _pumpCompletedRun(
  WidgetTester tester,
  HandsetAcceptanceSnapshot terminal,
) async {
  await _pumpAcceptancePage(
    tester,
    _FakeHandsetController(terminal: terminal),
  );
  await tester.tap(find.text('开始手机一键验收'));
  await tester.pumpAndSettle();
}

void _expectOnlyTerminalActions(WidgetTester tester) {
  final actionArea = find.byKey(
    const ValueKey<String>('handset-terminal-actions'),
  );
  final buttons = find.descendant(
    of: actionArea,
    matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
  );
  expect(buttons, findsNWidgets(3));
  for (final label in <String>['查看证据', '导出脱敏报告', '完整重跑']) {
    expect(find.descendant(of: actionArea, matching: find.text(label)),
        findsOneWidget);
  }
}

String _visibleText(WidgetTester tester) {
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
      .join('\n');
}

final class _UnavailableModelSetupService extends ModelSetupService {
  @override
  Future<bool> hasPendingAuthorization() async => false;

  @override
  Future<ModelSetupSnapshot> prepareAutomatically({
    void Function(ModelSetupSnapshot state)? onProgress,
  }) async {
    const result = ModelSetupSnapshot(
      phase: ModelSetupPhase.authorizationRequired,
      message: '测试：模型尚未准备',
    );
    onProgress?.call(result);
    return result;
  }
}

final class _FakeHandsetController implements HandsetAcceptanceController {
  _FakeHandsetController({
    this.recovered,
    this.progress = const <HandsetAcceptanceSnapshot>[],
    this.terminal,
    this.holdRun = false,
    this.interactionArtifact,
  });

  final HandsetAcceptanceSnapshot? recovered;
  final List<HandsetAcceptanceSnapshot> progress;
  final HandsetAcceptanceSnapshot? terminal;
  final bool holdRun;
  final VectorAcceptanceArtifact? interactionArtifact;
  final Completer<HandsetAcceptanceSnapshot> _runCompletion =
      Completer<HandsetAcceptanceSnapshot>();

  @override
  final ValueNotifier<String?> interruption = ValueNotifier<String?>(null);

  final List<String> interruptReasons = <String>[];
  VectorInteractionResult? interactionResult;

  @override
  Future<HandsetAcceptanceSnapshot?> recoverInterruptedCheckpoint() async {
    return recovered;
  }

  @override
  Future<void> interrupt(String reasonCode) async {
    interruptReasons.add(reasonCode);
    interruption.value = reasonCode;
  }

  @override
  Future<HandsetAcceptanceSnapshot> run({
    HandsetProgressCallback? onProgress,
    required VectorInteractionRun runInteraction,
  }) async {
    for (final snapshot in progress) {
      onProgress?.call(snapshot);
    }
    final artifact = interactionArtifact;
    if (artifact != null) {
      interactionResult = await runInteraction(artifact);
      return terminal ?? _terminalSnapshot(AcceptanceVerdict.blocked);
    }
    if (holdRun) return _runCompletion.future;
    return terminal ?? _terminalSnapshot(AcceptanceVerdict.pass);
  }

  void complete(HandsetAcceptanceSnapshot snapshot) {
    if (!_runCompletion.isCompleted) _runCompletion.complete(snapshot);
  }
}

final DateTime _now = DateTime.utc(2026, 9, 1, 12);

HandsetAcceptanceSnapshot _runningH4Snapshot() {
  return _snapshot(
    phase: HandsetRunPhase.runningAutomated,
    startedAt: _now.subtract(const Duration(seconds: 12)),
    statuses: const <String, HandsetGateStatus>{
      'H1_TARGET_DEVICE': HandsetGateStatus.passed,
      'H2_BUILD_IDENTITY': HandsetGateStatus.passed,
      'H3_UPGRADE_BASELINE': HandsetGateStatus.passed,
      'H4_PHONE_FUNCTION_LOOP': HandsetGateStatus.running,
    },
    nestedGolden: GoldenTestSnapshot(
      runId: 'golden-live',
      phase: GoldenRunPhase.running,
      startedAt: _now.subtract(const Duration(seconds: 10)),
      updatedAt: _now,
      gates: <GoldenGateSnapshot>[
        for (var number = 1; number <= 10; number += 1)
          GoldenGateSnapshot(
            name: 'F$number',
            label: 'Golden gate $number',
            timeout: const Duration(seconds: 30),
            status: number <= 5
                ? GoldenGateStatus.passed
                : number == 6
                    ? GoldenGateStatus.running
                    : GoldenGateStatus.pending,
          ),
      ],
    ),
  );
}

HandsetAcceptanceSnapshot _awaitingH6Snapshot() {
  return _snapshot(
    phase: HandsetRunPhase.awaitingInteraction,
    statuses: const <String, HandsetGateStatus>{
      'H1_TARGET_DEVICE': HandsetGateStatus.passed,
      'H2_BUILD_IDENTITY': HandsetGateStatus.passed,
      'H3_UPGRADE_BASELINE': HandsetGateStatus.passed,
      'H4_PHONE_FUNCTION_LOOP': HandsetGateStatus.passed,
      'H5_VECTOR_3D_TRUTH': HandsetGateStatus.passed,
      'H6_VECTOR_INTERACTION': HandsetGateStatus.running,
    },
  );
}

HandsetAcceptanceSnapshot _runningResourcesSnapshot() {
  return _snapshot(
    phase: HandsetRunPhase.runningPostChecks,
    statuses: const <String, HandsetGateStatus>{
      'H1_TARGET_DEVICE': HandsetGateStatus.passed,
      'H2_BUILD_IDENTITY': HandsetGateStatus.passed,
      'H3_UPGRADE_BASELINE': HandsetGateStatus.passed,
      'H4_PHONE_FUNCTION_LOOP': HandsetGateStatus.passed,
      'H5_VECTOR_3D_TRUTH': HandsetGateStatus.passed,
      'H6_VECTOR_INTERACTION': HandsetGateStatus.passed,
      'H7_RENDER_PERFORMANCE': HandsetGateStatus.passed,
      'H8_MEMORY_THERMAL': HandsetGateStatus.running,
      'H9_DATA_PRESERVATION': HandsetGateStatus.passed,
    },
    evidence: _resourceEvidence,
  );
}

HandsetAcceptanceSnapshot _terminalSnapshot(
  AcceptanceVerdict verdict, {
  bool includeSensitiveEvidence = false,
}) {
  final statuses = <String, HandsetGateStatus>{
    for (final name in _gateLabels.keys) name: HandsetGateStatus.passed,
  };
  final details = <String, String>{};
  if (verdict == AcceptanceVerdict.fail) {
    statuses['H7_RENDER_PERFORMANCE'] = HandsetGateStatus.failed;
    details['H7_RENDER_PERFORMANCE'] = 'RENDER_PERFORMANCE_REGRESSION';
  } else if (verdict == AcceptanceVerdict.blocked) {
    statuses['H4_PHONE_FUNCTION_LOOP'] = HandsetGateStatus.blocked;
    details['H4_PHONE_FUNCTION_LOOP'] = 'MODEL_PREREQUISITE_MISSING';
  }
  final evidence = <String, List<AcceptanceEvidence>>{
    ..._resourceEvidence,
    if (includeSensitiveEvidence)
      'H2_BUILD_IDENTITY': const <AcceptanceEvidence>[
        AcceptanceEvidence(
          code: 'UNREVIEWED_VALUE',
          method: EvidenceMethod.measured,
          source: 'test',
          actual: 'hf_super_secret_token',
          threshold: null,
          unit: null,
          available: true,
          detail: 'hf_super_secret_token',
        ),
      ],
  };
  return _snapshot(
    phase: HandsetRunPhase.completed,
    statuses: statuses,
    details: details,
    evidence: evidence,
    baselineVersionCode: 2022,
  );
}

HandsetAcceptanceSnapshot _interruptedSnapshot() {
  return _snapshot(
    phase: HandsetRunPhase.completed,
    statuses: <String, HandsetGateStatus>{
      for (final name in _gateLabels.keys)
        name: name == 'H1_TARGET_DEVICE'
            ? HandsetGateStatus.passed
            : HandsetGateStatus.blocked,
    },
    details: const <String, String>{
      'H2_BUILD_IDENTITY': 'PROCESS_INTERRUPTED',
    },
    baselineVersionCode: 2022,
  );
}

HandsetAcceptanceSnapshot _snapshot({
  required HandsetRunPhase phase,
  required Map<String, HandsetGateStatus> statuses,
  DateTime? startedAt,
  Map<String, String> details = const <String, String>{},
  Map<String, List<AcceptanceEvidence>> evidence =
      const <String, List<AcceptanceEvidence>>{},
  GoldenTestSnapshot? nestedGolden,
  int? baselineVersionCode,
}) {
  return HandsetAcceptanceSnapshot(
    runId: 'r50-terminal',
    phase: phase,
    startedAt: startedAt ?? _now.subtract(const Duration(seconds: 30)),
    updatedAt: _now,
    gates: <HandsetGateSnapshot>[
      for (final entry in _gateLabels.entries)
        HandsetGateSnapshot(
          name: entry.key,
          label: entry.value,
          status: statuses[entry.key] ?? HandsetGateStatus.pending,
          detail: details[entry.key] ?? '',
          evidence: evidence[entry.key] ?? const <AcceptanceEvidence>[],
          startedAt: statuses.containsKey(entry.key) ? _now : null,
          finishedAt: (statuses[entry.key] ?? HandsetGateStatus.pending)
                  .isTerminal
              ? _now
              : null,
        ),
    ],
    nestedGolden: nestedGolden,
    baselineVersionCode: baselineVersionCode,
  );
}

const Map<String, String> _gateLabels = <String, String>{
  'H1_TARGET_DEVICE': 'Target device',
  'H2_BUILD_IDENTITY': 'Build identity',
  'H3_UPGRADE_BASELINE': 'Upgrade baseline',
  'H4_PHONE_FUNCTION_LOOP': 'Phone function loop',
  'H5_VECTOR_3D_TRUTH': 'Vector 3D truth',
  'H6_VECTOR_INTERACTION': 'Vector interaction',
  'H7_RENDER_PERFORMANCE': 'Render performance',
  'H8_MEMORY_THERMAL': 'Memory and thermal',
  'H9_DATA_PRESERVATION': 'Data preservation',
  'H10_REPORT_INTEGRITY': 'Report integrity',
};

const Map<String, List<AcceptanceEvidence>> _resourceEvidence =
    <String, List<AcceptanceEvidence>>{
  'H7_RENDER_PERFORMANCE': <AcceptanceEvidence>[
    AcceptanceEvidence(
      code: 'FRAME_P95_MS',
      method: EvidenceMethod.measured,
      source: 'SchedulerBinding.addTimingsCallback',
      actual: 14.2,
      threshold: 16.7,
      unit: 'ms',
      available: true,
      detail: 'EVIDENCE_RECORDED',
    ),
  ],
  'H8_MEMORY_THERMAL': <AcceptanceEvidence>[
    AcceptanceEvidence(
      code: 'BASELINE_PSS_KIB',
      method: EvidenceMethod.measured,
      source: 'Debug.getPss',
      actual: 320000,
      threshold: 524288,
      unit: 'KiB',
      available: true,
      detail: 'EVIDENCE_RECORDED',
    ),
    AcceptanceEvidence(
      code: 'MIN_AVAILABLE_MEMORY_BYTES',
      method: EvidenceMethod.measured,
      source: 'ActivityManager.MemoryInfo',
      actual: 4000000000,
      threshold: null,
      unit: 'bytes',
      available: true,
      detail: 'EVIDENCE_RECORDED',
    ),
    AcceptanceEvidence(
      code: 'PEAK_BATTERY_TEMPERATURE_C',
      method: EvidenceMethod.measured,
      source: 'ACTION_BATTERY_CHANGED',
      actual: 38.4,
      threshold: null,
      unit: '°C',
      available: true,
      detail: 'EVIDENCE_RECORDED',
    ),
    AcceptanceEvidence(
      code: 'MAX_THERMAL_STATUS',
      method: EvidenceMethod.measured,
      source: 'PowerManager.currentThermalStatus',
      actual: 2,
      threshold: 3,
      unit: null,
      available: true,
      detail: 'EVIDENCE_RECORDED',
    ),
  ],
};

final class _TestVectorArtifact implements VectorAcceptanceArtifact {
  const _TestVectorArtifact();

  @override
  String get traceId => 'trace-handset-ui';

  @override
  TraceVectorSpaceSnapshot get vectorSpace => _vectorSpace;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const VectorAcceptanceArtifact _vectorArtifact = _TestVectorArtifact();

const TraceVectorPoint _queryPoint = TraceVectorPoint(
  embeddingId: 'query',
  chunkId: null,
  documentId: null,
  sourceName: '当前查询',
  locator: '',
  representation: EmbeddingRepresentation.query,
  x: 0,
  y: 0,
  z: 0,
  cosineToQuery: 1,
  isQuery: true,
  lane: RetrievalLane.active,
  text: '高维关系',
  candidateId: null,
  sourceChannels: null,
  selectedForEvidence: false,
  selectionReason: null,
  dropReason: null,
  ftsRank: null,
  vectorRank: null,
  finalRank: null,
);

const TraceVectorPoint _bodyPoint = TraceVectorPoint(
  embeddingId: 'body',
  chunkId: 'chunk',
  documentId: 'document',
  sourceName: '证据.md',
  locator: 'Chunk 1',
  representation: EmbeddingRepresentation.body,
  x: 0.4,
  y: 0.2,
  z: 0.1,
  cosineToQuery: 0.8,
  isQuery: false,
  lane: RetrievalLane.active,
  text: '真实向量投影',
  candidateId: 'candidate',
  sourceChannels: 'vector',
  selectedForEvidence: true,
  selectionReason: 'direct_support',
  dropReason: null,
  ftsRank: null,
  vectorRank: 1,
  finalRank: 1,
);

const TraceVectorSpaceSnapshot _vectorSpace = TraceVectorSpaceSnapshot(
  queryEmbeddingId: 'query',
  queryVectorSha256:
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  usedCapturedQuery: true,
  samplePolicy: 'same-run',
  totalPersistentBodyCount: 1,
  points: <TraceVectorPoint>[_bodyPoint, _queryPoint],
  neighbors: <TraceVectorPoint>[_bodyPoint],
  explainedVarianceRatios: <double>[0.6, 0.25, 0.1],
  originalDimension: 768,
  effectiveComponentCount: 3,
);
