import 'dart:async';

import '../core/models.dart';
import 'golden_test_state.dart';

typedef GoldenProgressCallback = void Function(GoldenTestSnapshot snapshot);
typedef GoldenCheckpointCallback = FutureOr<void> Function(
  GoldenTestSnapshot snapshot,
);
typedef GoldenGateTimeoutCallback = FutureOr<void> Function(
  GoldenGateSnapshot gate,
);
typedef GoldenCleanupCallback = FutureOr<void> Function();

class GoldenGateSpec {
  const GoldenGateSpec({
    required this.name,
    required this.label,
    required this.timeout,
    required this.run,
    this.blockedWhen,
    this.blockedReason = 'dependency did not pass',
  });

  final String name;
  final String label;
  final Duration timeout;
  final Future<GateResult> Function() run;
  final bool Function(GoldenTestSnapshot snapshot)? blockedWhen;
  final String blockedReason;
}

class GoldenGateExecutor {
  GoldenGateExecutor({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  Future<GoldenTestSnapshot> execute({
    required String runId,
    required List<GoldenGateSpec> gates,
    GoldenProgressCallback? onProgress,
    GoldenCheckpointCallback? onCheckpoint,
    GoldenGateTimeoutCallback? onGateTimeout,
    GoldenCleanupCallback? cleanup,
  }) async {
    final startedAt = _clock();
    var snapshot = GoldenTestSnapshot(
      runId: runId,
      phase: GoldenRunPhase.preparing,
      startedAt: startedAt,
      updatedAt: startedAt,
      gates: [
        for (final gate in gates)
          GoldenGateSnapshot(
            name: gate.name,
            label: gate.label,
            timeout: gate.timeout,
          ),
      ],
    );
    await _emit(snapshot, onProgress, onCheckpoint);

    snapshot = snapshot.copyWith(
      phase: GoldenRunPhase.running,
      updatedAt: _clock(),
    );
    await _emit(snapshot, onProgress, onCheckpoint);

    for (var index = 0; index < gates.length; index += 1) {
      final spec = gates[index];
      if (spec.blockedWhen?.call(snapshot) ?? false) {
        snapshot = _replaceGate(
          snapshot,
          index,
          snapshot.gates[index].copyWith(
            status: GoldenGateStatus.blocked,
            detail: spec.blockedReason,
            finishedAt: _clock(),
          ),
        );
        await _emit(snapshot, onProgress, onCheckpoint);
        continue;
      }

      final gateStartedAt = _clock();
      snapshot = _replaceGate(
        snapshot,
        index,
        snapshot.gates[index].copyWith(
          status: GoldenGateStatus.running,
          detail: '',
          startedAt: gateStartedAt,
          finishedAt: null,
        ),
      );
      await _emit(snapshot, onProgress, onCheckpoint);

      GoldenGateStatus status;
      String detail;
      try {
        final result = await spec.run().timeout(spec.timeout);
        status = result.passed
            ? GoldenGateStatus.passed
            : GoldenGateStatus.failed;
        detail = result.detail;
      } on TimeoutException {
        status = GoldenGateStatus.timedOut;
        detail = 'timeout=${spec.timeout.inMilliseconds}ms';
        try {
          await onGateTimeout?.call(snapshot.gates[index]);
        } catch (error) {
          detail = '$detail; timeoutCleanupError=$error';
        }
      } catch (error, stackTrace) {
        status = GoldenGateStatus.failed;
        detail = '$error\n$stackTrace';
      }

      snapshot = _replaceGate(
        snapshot,
        index,
        snapshot.gates[index].copyWith(
          status: status,
          detail: detail,
          finishedAt: _clock(),
        ),
      );
      await _emit(snapshot, onProgress, onCheckpoint);
    }

    snapshot = snapshot.copyWith(
      phase: GoldenRunPhase.cleaningUp,
      updatedAt: _clock(),
    );
    await _emit(snapshot, onProgress, onCheckpoint);

    String? cleanupError;
    try {
      await cleanup?.call();
    } catch (error, stackTrace) {
      cleanupError = '$error\n$stackTrace';
    }

    snapshot = snapshot.copyWith(
      phase: GoldenRunPhase.completed,
      updatedAt: _clock(),
      cleanupError: cleanupError,
    );
    await _emit(snapshot, onProgress, onCheckpoint);
    return snapshot;
  }

  GoldenTestSnapshot _replaceGate(
    GoldenTestSnapshot snapshot,
    int index,
    GoldenGateSnapshot gate,
  ) {
    final updated = List<GoldenGateSnapshot>.of(snapshot.gates);
    updated[index] = gate;
    return snapshot.copyWith(gates: updated, updatedAt: _clock());
  }

  Future<void> _emit(
    GoldenTestSnapshot snapshot,
    GoldenProgressCallback? onProgress,
    GoldenCheckpointCallback? onCheckpoint,
  ) async {
    onProgress?.call(snapshot);
    await onCheckpoint?.call(snapshot);
  }
}
