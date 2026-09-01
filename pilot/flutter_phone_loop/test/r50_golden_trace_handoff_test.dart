import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketgallery_phone_pilot/core/models.dart';
import 'package:pocketgallery_phone_pilot/services/golden_gate_executor.dart';
import 'package:pocketgallery_phone_pilot/services/golden_test_report_store.dart';
import 'package:pocketgallery_phone_pilot/services/golden_test_runner.dart';
import 'package:pocketgallery_phone_pilot/services/golden_test_state.dart';
import 'package:pocketgallery_phone_pilot/services/knowledge_engine.dart';

void main() {
  test('Golden report carries trace metadata without rewriting F10', () {
    final startedAt = DateTime.utc(2026, 9, 1);
    final snapshot = GoldenTestSnapshot(
      runId: 'golden-r50',
      phase: GoldenRunPhase.completed,
      startedAt: startedAt,
      updatedAt: startedAt.add(const Duration(seconds: 1)),
      gates: <GoldenGateSnapshot>[
        GoldenGateSnapshot(
          name: 'F10_CONTEXT_BUDGET',
          label: 'Context budget',
          timeout: const Duration(seconds: 30),
          status: GoldenGateStatus.passed,
          detail: 'budget captured',
          startedAt: startedAt,
          finishedAt: startedAt.add(const Duration(seconds: 1)),
        ),
      ],
    );

    final report = GoldenTestReport.fromSnapshot(
      snapshot,
      traceId: 'trace-r50',
      traceCaptureError: 'capture failed',
    );

    expect(report.traceId, 'trace-r50');
    expect(report.traceCaptureError, 'capture failed');
    expect(report.toJson()['traceId'], 'trace-r50');
    expect(report.toJson()['traceCaptureError'], 'capture failed');
    expect(report.snapshot!.gates.single.status, GoldenGateStatus.passed);
    expect(report.results.single.passed, isTrue);
  });

  test('trace handoff awaits capture before the caller can clean up', () async {
    final captureRelease = Completer<void>();
    final events = <String>[];
    final handoff = GoldenTraceHandoff((traceId) async {
      events.add('capture-start:$traceId');
      await captureRelease.future;
      events.add('capture-finish:$traceId');
    })..traceId = 'trace-r50';
    var completed = false;

    final future = handoff
        .captureAfter(() async {
          events.add('f10-finish');
          return const GateResult('F10_CONTEXT_BUDGET', true, 'pass');
        })
        .then((value) {
          completed = true;
          events.add('handoff-finish');
          return value;
        });
    await Future<void>.delayed(Duration.zero);

    expect(events, <String>['f10-finish', 'capture-start:trace-r50']);
    expect(completed, isFalse);
    captureRelease.complete();
    final result = await future;
    events.add('cleanup');

    expect(result.passed, isTrue);
    expect(events, <String>[
      'f10-finish',
      'capture-start:trace-r50',
      'capture-finish:trace-r50',
      'handoff-finish',
      'cleanup',
    ]);

    final failedHandoff = GoldenTraceHandoff((traceId) async {
      throw StateError('capture\nfailed for $traceId');
    })..traceId = 'trace-r50';
    final unaffected = await failedHandoff.captureAfter(
      () async => const GateResult('F10_CONTEXT_BUDGET', true, 'pass'),
    );
    expect(unaffected.passed, isTrue);
    expect(failedHandoff.captureError, isNot(contains('\n')));
    expect(failedHandoff.captureError, contains('capture failed'));
  });

  test(
    'interrupt keeps the first reason and shares close and cleanup futures',
    () async {
      var closeCount = 0;
      var cleanupCount = 0;
      final control = GoldenRunControl(
        closeActiveModel: () async {
          closeCount += 1;
        },
      );

      await Future.wait<void>(<Future<void>>[
        control.interrupt('USER_CANCELLED'),
        control.interrupt('APP_BACKGROUNDED'),
        control.closeActiveModel(),
      ]);

      expect(control.reasonCode, 'USER_CANCELLED');
      expect(closeCount, 1);
      final firstCleanup = control.cleanup(() async {
        cleanupCount += 1;
      });
      final secondCleanup = control.cleanup(() async {
        cleanupCount += 1;
      });
      expect(identical(firstCleanup, secondCleanup), isTrue);
      await Future.wait<void>(<Future<void>>[firstCleanup, secondCleanup]);
      expect(cleanupCount, 1);

      final idleRunner = GoldenTestRunner(KnowledgeEngine());
      await idleRunner.interrupt('USER_CANCELLED');
      await idleRunner.interrupt('APP_BACKGROUNDED');
    },
  );

  test(
    'sequential model closes are not suppressed after one close finishes',
    () async {
      var closeCount = 0;
      final control = GoldenRunControl(
        closeActiveModel: () async {
          closeCount += 1;
        },
      );

      await control.closeActiveModel();
      await control.closeActiveModel();

      expect(closeCount, 2);
    },
  );

  test(
    'hanging model shutdown is bounded and recorded as cleanup evidence',
    () async {
      final nativeClose = Completer<void>();
      final control = GoldenRunControl(
        closeActiveModel: () => nativeClose.future,
      );
      final execution = GoldenGateExecutor().execute(
        runId: 'golden-close-timeout',
        gates: <GoldenGateSpec>[
          GoldenGateSpec(
            name: 'F1_IMPORT_CHUNK',
            label: 'fixture',
            timeout: const Duration(seconds: 1),
            run: () async => const GateResult('F1_IMPORT_CHUNK', true, 'pass'),
          ),
        ],
        cleanup: () => control.interrupt('USER_CANCELLED'),
      );

      final outcome = await Future.any<Object>(<Future<Object>>[
        execution,
        Future<Object>.delayed(
          const Duration(seconds: 6),
          () => 'WATCHDOG_EXPIRED',
        ),
      ]);
      if (!nativeClose.isCompleted) nativeClose.complete();
      await execution;

      expect(outcome, isA<GoldenTestSnapshot>());
      final snapshot = outcome as GoldenTestSnapshot;
      expect(snapshot.phase, GoldenRunPhase.completed);
      expect(snapshot.cleanupError, contains('GOLDEN_MODEL_CLOSE_TIMEOUT'));
      expect(control.reasonCode, 'USER_CANCELLED');
    },
  );

  test(
    'late interruption preserves terminal failure and cleanup evidence',
    () async {
      final startedAt = DateTime.utc(2026, 9, 1);
      final executor = _SnapshotExecutor(
        GoldenTestSnapshot(
          runId: 'golden-terminal-precedence',
          phase: GoldenRunPhase.completed,
          startedAt: startedAt,
          updatedAt: startedAt.add(const Duration(seconds: 1)),
          cleanupError: 'cleanup failure must survive',
          gates: <GoldenGateSnapshot>[
            GoldenGateSnapshot(
              name: 'F1_IMPORT_CHUNK',
              label: 'failed',
              timeout: const Duration(seconds: 1),
              status: GoldenGateStatus.failed,
              detail: 'fixture failure',
            ),
            GoldenGateSnapshot(
              name: 'F6_GEMMA_CITATION',
              label: 'timed out',
              timeout: const Duration(seconds: 1),
              status: GoldenGateStatus.timedOut,
              detail: 'timeout=1000ms',
            ),
            const GoldenGateSnapshot(
              name: 'F7_CHAT_REALWORLD',
              label: 'not started',
              timeout: Duration(seconds: 1),
            ),
          ],
        ),
      );
      final directory = await Directory.systemTemp.createTemp(
        'pg-r50-interruption-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final runner = GoldenTestRunner(
        KnowledgeEngine(),
        executor: executor,
        reportStore: GoldenTestReportStore(
          directoryProvider: () async => directory,
        ),
      );

      final run = runner.run();
      await executor.entered.future;
      await runner.interrupt('USER_CANCELLED');
      executor.release.complete();
      final snapshot = (await run).snapshot!;

      expect(snapshot.gate('F1_IMPORT_CHUNK')!.status, GoldenGateStatus.failed);
      expect(
        snapshot.gate('F6_GEMMA_CITATION')!.status,
        GoldenGateStatus.timedOut,
      );
      expect(
        snapshot.gate('F7_CHAT_REALWORLD')!.status,
        GoldenGateStatus.blocked,
      );
      expect(snapshot.gate('F7_CHAT_REALWORLD')!.detail, 'USER_CANCELLED');
      expect(snapshot.cleanupError, 'cleanup failure must survive');
    },
  );

  test('Gemma model acquisition cannot resurrect a closed service', () async {
    final source = await File(
      'lib/services/gemma_chat_service.dart',
    ).readAsString();

    expect(source, contains('_closed = true'));
    expect(source, contains('if (_closed)'));
    expect(source, contains('await acquired.close()'));
  });
}

final class _SnapshotExecutor extends GoldenGateExecutor {
  _SnapshotExecutor(this.snapshot);

  final GoldenTestSnapshot snapshot;
  final Completer<void> entered = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<GoldenTestSnapshot> execute({
    required String runId,
    required List<GoldenGateSpec> gates,
    GoldenProgressCallback? onProgress,
    GoldenCheckpointCallback? onCheckpoint,
    GoldenGateTimeoutCallback? onGateTimeout,
    GoldenCleanupCallback? cleanup,
  }) async {
    entered.complete();
    await release.future;
    return snapshot;
  }
}
