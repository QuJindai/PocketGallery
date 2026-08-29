import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketgallery_phone_pilot/chat/chat_models.dart';
import 'package:pocketgallery_phone_pilot/core/models.dart';
import 'package:pocketgallery_phone_pilot/services/golden_gate_executor.dart';
import 'package:pocketgallery_phone_pilot/services/golden_test_report_store.dart';
import 'package:pocketgallery_phone_pilot/services/golden_test_runner.dart';
import 'package:pocketgallery_phone_pilot/services/golden_test_state.dart';
import 'package:pocketgallery_phone_pilot/ui/model_settings_page.dart';

void main() {
  group('R4.8 bounded phone acceptance', () {
    test('two passing gates emit the fixed monotonic progress sequence',
        () async {
      final seen = <GoldenTestSnapshot>[];

      final result = await GoldenGateExecutor().execute(
        runId: 'r48-order',
        gates: [
          GoldenGateSpec(
            name: 'F1_IMPORT_CHUNK',
            label: 'Import and chunk fixture',
            timeout: const Duration(seconds: 1),
            run: () async =>
                const GateResult('F1_IMPORT_CHUNK', true, 'chunks=3'),
          ),
          GoldenGateSpec(
            name: 'F2_FTS5',
            label: 'FTS5 exact recall',
            timeout: const Duration(seconds: 1),
            run: () async => const GateResult('F2_FTS5', true, 'top1=fixture'),
          ),
        ],
        onProgress: seen.add,
      );

      expect(
        seen.map((snapshot) => snapshot.percent).toList(),
        orderedEquals([0, 0, 0, 45, 45, 90, 95, 100]),
      );
      expect(result.phase, GoldenRunPhase.completed);
      expect(result.completedCount, 2);
      expect(result.passed, isTrue);
    });

    test('a gate timeout is terminal, calls timeout cleanup, and cannot pass',
        () async {
      var timeoutCleanupCalls = 0;

      final result = await GoldenGateExecutor().execute(
        runId: 'r48-timeout',
        gates: [
          GoldenGateSpec(
            name: 'F6_GEMMA_CITATION',
            label: 'Real Gemma citation',
            timeout: const Duration(milliseconds: 5),
            run: () => Completer<GateResult>().future,
          ),
        ],
        onGateTimeout: (_) async {
          timeoutCleanupCalls += 1;
        },
      );

      expect(result.gates.single.status, GoldenGateStatus.timedOut);
      expect(result.gates.single.detail, contains('5ms'));
      expect(timeoutCleanupCalls, 1);
      expect(result.passed, isFalse);
    });

    test('a failed dependency blocks its consumer without invoking it',
        () async {
      var dependentCalls = 0;

      final result = await GoldenGateExecutor().execute(
        runId: 'r48-blocked',
        gates: [
          GoldenGateSpec(
            name: 'F6_GEMMA_CITATION',
            label: 'Real Gemma citation',
            timeout: const Duration(seconds: 1),
            run: () async =>
                const GateResult('F6_GEMMA_CITATION', false, 'bad citation'),
          ),
          GoldenGateSpec(
            name: 'F7_CHAT_REALWORLD',
            label: 'Heavy second turn',
            timeout: const Duration(seconds: 1),
            blockedWhen: (snapshot) =>
                snapshot.gate('F6_GEMMA_CITATION')?.status !=
                GoldenGateStatus.passed,
            blockedReason: 'F6 did not pass',
            run: () async {
              dependentCalls += 1;
              return const GateResult('F7_CHAT_REALWORLD', true, 'unexpected');
            },
          ),
        ],
      );

      expect(dependentCalls, 0);
      expect(result.gate('F7_CHAT_REALWORLD')!.status,
          GoldenGateStatus.blocked);
      expect(result.gate('F7_CHAT_REALWORLD')!.detail, 'F6 did not pass');
      expect(result.passed, isFalse);
    });

    test('cleanup failure is recorded and forces an overall failure',
        () async {
      final result = await GoldenGateExecutor().execute(
        runId: 'r48-cleanup',
        gates: [
          GoldenGateSpec(
            name: 'F1_IMPORT_CHUNK',
            label: 'Import and chunk fixture',
            timeout: const Duration(seconds: 1),
            run: () async =>
                const GateResult('F1_IMPORT_CHUNK', true, 'chunks=3'),
          ),
        ],
        cleanup: () async => throw StateError('fixture cleanup failed'),
      );

      expect(result.phase, GoldenRunPhase.completed);
      expect(result.percent, 100);
      expect(result.cleanupError, contains('fixture cleanup failed'));
      expect(result.passed, isFalse);
    });

    test('snapshot JSON round-trip preserves terminal gate evidence', () {
      final startedAt = DateTime.utc(2026, 8, 29, 12);
      final finishedAt = startedAt.add(const Duration(seconds: 3));
      final snapshot = GoldenTestSnapshot(
        runId: 'r48-json',
        phase: GoldenRunPhase.completed,
        startedAt: startedAt,
        updatedAt: finishedAt,
        gates: [
          GoldenGateSnapshot(
            name: 'F1_IMPORT_CHUNK',
            label: 'Import and chunk fixture',
            timeout: const Duration(seconds: 45),
            status: GoldenGateStatus.passed,
            detail: 'chunks=3\nsource=fixture',
            startedAt: startedAt,
            finishedAt: finishedAt,
          ),
        ],
      );

      final restored = GoldenTestSnapshot.fromJson(snapshot.toJson());

      expect(restored.schemaVersion, 2);
      expect(restored.runId, 'r48-json');
      expect(restored.gates.single.status, GoldenGateStatus.passed);
      expect(restored.gates.single.detail, 'chunks=3\nsource=fixture');
      expect(restored.gates.single.duration, const Duration(seconds: 3));
      expect(restored.passed, isTrue);
    });

    test('a checkpoint is durable before its progress becomes visible',
        () async {
      final events = <String>[];

      await GoldenGateExecutor().execute(
        runId: 'r48-checkpoint-order',
        gates: [
          GoldenGateSpec(
            name: 'F1_IMPORT_CHUNK',
            label: 'Import and chunk fixture',
            timeout: const Duration(seconds: 1),
            run: () async =>
                const GateResult('F1_IMPORT_CHUNK', true, 'chunks=3'),
          ),
        ],
        onCheckpoint: (snapshot) async {
          events.add('saved:${snapshot.phase.name}:${snapshot.percent}');
        },
        onProgress: (snapshot) {
          events.add('shown:${snapshot.phase.name}:${snapshot.percent}');
        },
      );

      expect(events.first, 'saved:preparing:0');
      for (var index = 0; index < events.length; index += 2) {
        expect(events[index], startsWith('saved:'));
        expect(events[index + 1], startsWith('shown:'));
        expect(
          events[index].substring('saved:'.length),
          events[index + 1].substring('shown:'.length),
        );
      }
    });
  });

  group('R4.8 recoverable checkpoints', () {
    test('save writes valid JSON and leaves no temporary file', () async {
      final directory = await Directory.systemTemp.createTemp('pg-r48-save-');
      addTearDown(() => directory.delete(recursive: true));
      final store = GoldenTestReportStore(
        directoryProvider: () async => directory,
      );

      final file = await store.save(_checkpointSnapshot('r48-save'));

      expect(jsonDecode(await file.readAsString()), isA<Map<String, dynamic>>());
      expect(File('${file.path}.tmp').existsSync(), isFalse);
      expect((await store.readLast())!.runId, 'r48-save');
    });

    test('readLast falls back to a valid backup after an interrupted swap',
        () async {
      final directory = await Directory.systemTemp.createTemp('pg-r48-bak-');
      addTearDown(() => directory.delete(recursive: true));
      final store = GoldenTestReportStore(
        directoryProvider: () async => directory,
      );
      final file = await store.save(_checkpointSnapshot('previous-valid'));
      await file.rename('${file.path}.bak');
      await file.writeAsString('{incomplete');

      final restored = await store.readLast();

      expect(restored, isNotNull);
      expect(restored!.runId, 'previous-valid');
      expect(restored.gates.single.detail, 'line 1\nline 2: StateError');
    });

    test('readLast returns null when primary and backup are both malformed',
        () async {
      final directory = await Directory.systemTemp.createTemp('pg-r48-bad-');
      addTearDown(() => directory.delete(recursive: true));
      final store = GoldenTestReportStore(
        directoryProvider: () async => directory,
      );
      await File('${directory.path}/PG_GOLDEN_LAST.json')
          .writeAsString('{bad-primary');
      await File('${directory.path}/PG_GOLDEN_LAST.json.bak')
          .writeAsString('bad-backup');

      expect(await store.readLast(), isNull);
    });
  });

  group('R4.8 strict F7 assertion', () {
    const validAnchors = {'E1', 'E2', 'E3', 'E4', 'E5', 'E6'};

    test('rejects a non-empty second turn that never reaches E6', () {
      final reply = ChatMessage.assistant(
        id: 'a1',
        sessionId: 's1',
        text: '上下文正常 [E1]',
        retrievalMode: 'knowledge:lexical-only',
        citedAnchorsJson: ChatMessage.encodeAnchors(['E1']),
      );

      final result = GoldenF7Assertion.evaluate(reply, validAnchors);

      expect(result.name, 'F7_CHAT_REALWORLD');
      expect(result.passed, isFalse);
      expect(result.detail, contains('sentinel=false'));
      expect(result.detail, contains('citesE6=false'));
    });

    test('rejects an out-of-pack citation even when E6 is present', () {
      final reply = ChatMessage.assistant(
        id: 'a2',
        sessionId: 's1',
        text: 'PG_EVIDENCE_LAST_6 [E6] [E9]',
        retrievalMode: 'knowledge:lexical-only',
        citedAnchorsJson: ChatMessage.encodeAnchors(['E6', 'E9']),
      );

      final result = GoldenF7Assertion.evaluate(reply, validAnchors);

      expect(result.passed, isFalse);
      expect(result.detail, contains('validCitations=false'));
    });

    test('rejects model-only retrieval even with the sentinel and E6', () {
      final reply = ChatMessage.assistant(
        id: 'a3',
        sessionId: 's1',
        text: 'PG_EVIDENCE_LAST_6 [E6]',
        retrievalMode: 'modelOnly',
        citedAnchorsJson: ChatMessage.encodeAnchors(['E6']),
      );

      final result = GoldenF7Assertion.evaluate(reply, validAnchors);

      expect(result.passed, isFalse);
      expect(result.detail, contains('knowledgeMode=false'));
    });

    test('passes only the final sentinel with a valid E6 knowledge citation',
        () {
      final reply = ChatMessage.assistant(
        id: 'a4',
        sessionId: 's1',
        text: '最后标记是 PG_EVIDENCE_LAST_6 [E6]',
        retrievalMode: 'knowledge:hybrid',
        citedAnchorsJson: ChatMessage.encodeAnchors(['E6']),
      );

      final result = GoldenF7Assertion.evaluate(reply, validAnchors);

      expect(result.passed, isTrue);
      expect(result.detail, contains('sentinel=true'));
      expect(result.detail, contains('citesE6=true'));
      expect(result.detail, contains('validCitations=true'));
      expect(result.detail, contains('knowledgeMode=true'));
    });
  });

  group('R4.8 live phone progress UI', () {
    testWidgets('renders determinate live progress and checkpoint state',
        (tester) async {
      final now = DateTime.utc(2026, 8, 29, 14, 0, 12);
      final snapshot = GoldenTestSnapshot(
        runId: 'r48-ui-running',
        phase: GoldenRunPhase.running,
        startedAt: now.subtract(const Duration(seconds: 12)),
        updatedAt: now,
        gates: [
          _uiGate(1, GoldenGateStatus.passed),
          _uiGate(2, GoldenGateStatus.running),
          for (var number = 3; number <= 7; number += 1)
            _uiGate(number, GoldenGateStatus.pending),
        ],
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: GoldenTestProgressPanel(snapshot: snapshot, now: now),
        ),
      ));

      final progress = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(progress.value, closeTo(0.13, 0.001));
      expect(find.text('13%'), findsOneWidget);
      expect(find.text('当前：F2/7 · Gate 2'), findsOneWidget);
      expect(find.text('已完成：1/7'), findsOneWidget);
      expect(find.text('已用时：00:12'), findsOneWidget);
      expect(find.text('检查点：PG_GOLDEN_LAST.json · 已保存'), findsOneWidget);
      expect(find.textContaining('F6/F7 需在实体手机'), findsOneWidget);
    });

    testWidgets('renders all six gate statuses with distinct icons',
        (tester) async {
      final now = DateTime.utc(2026, 8, 29, 14, 1);
      final statuses = GoldenGateStatus.values;
      final snapshot = GoldenTestSnapshot(
        runId: 'r48-ui-statuses',
        phase: GoldenRunPhase.running,
        startedAt: now,
        updatedAt: now,
        gates: [
          for (var index = 0; index < statuses.length; index += 1)
            _uiGate(index + 1, statuses[index]),
        ],
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GoldenTestProgressPanel(snapshot: snapshot, now: now),
          ),
        ),
      ));

      for (final label in ['等待', '运行中', '通过', '失败', '超时', '已阻断']) {
        expect(find.text(label), findsOneWidget);
      }
      for (final icon in [
        Icons.schedule_outlined,
        Icons.sync,
        Icons.check_circle,
        Icons.cancel,
        Icons.timer_off,
        Icons.block,
      ]) {
        expect(find.byIcon(icon), findsOneWidget);
      }
    });

    testWidgets('renders the final PASS verdict after completed cleanup',
        (tester) async {
      final now = DateTime.utc(2026, 8, 29, 14, 2);
      final snapshot = GoldenTestSnapshot(
        runId: 'r48-ui-pass',
        phase: GoldenRunPhase.completed,
        startedAt: now.subtract(const Duration(seconds: 20)),
        updatedAt: now,
        gates: [
          for (var number = 1; number <= 7; number += 1)
            _uiGate(number, GoldenGateStatus.passed),
        ],
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GoldenTestProgressPanel(snapshot: snapshot, now: now),
          ),
        ),
      ));

      expect(find.text('PHONE_FUNCTION_LOOP = PASS'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
    });
  });

  group('R4.8 release contract', () {
    test('build number advances beyond the R4.7 APK', () async {
      final pubspec = await File('pubspec.yaml').readAsString();
      final match = RegExp(
        r'^version:\s*0\.4\.17\+(\d+)\s*$',
        multiLine: true,
      ).firstMatch(pubspec);

      expect(match, isNotNull, reason: 'R4.8 must use version 0.4.17');
      expect(int.parse(match!.group(1)!), greaterThanOrEqualTo(18));
    });
  });
}

GoldenTestSnapshot _checkpointSnapshot(String runId) {
  final startedAt = DateTime.utc(2026, 8, 29, 13);
  return GoldenTestSnapshot(
    runId: runId,
    phase: GoldenRunPhase.running,
    startedAt: startedAt,
    updatedAt: startedAt.add(const Duration(seconds: 2)),
    gates: [
      GoldenGateSnapshot(
        name: 'F1_IMPORT_CHUNK',
        label: 'Import and chunk fixture',
        timeout: const Duration(seconds: 45),
        status: GoldenGateStatus.failed,
        detail: 'line 1\nline 2: StateError',
        startedAt: startedAt,
        finishedAt: startedAt.add(const Duration(seconds: 2)),
      ),
    ],
  );
}

GoldenGateSnapshot _uiGate(int number, GoldenGateStatus status) {
  return GoldenGateSnapshot(
    name: 'F${number}_GATE',
    label: 'Gate $number',
    timeout: const Duration(seconds: 30),
    status: status,
    detail: status.isTerminal ? 'gate-$number detail' : '',
  );
}
