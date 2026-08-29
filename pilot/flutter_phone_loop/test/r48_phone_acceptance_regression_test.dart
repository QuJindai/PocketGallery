import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketgallery_phone_pilot/core/models.dart';
import 'package:pocketgallery_phone_pilot/services/golden_gate_executor.dart';
import 'package:pocketgallery_phone_pilot/services/golden_test_state.dart';

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
  });
}
