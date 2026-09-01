import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketgallery_phone_pilot/core/models.dart';
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

  test('interrupt keeps the first reason and shares close and cleanup futures', () async {
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
  });
}
