import 'package:flutter/foundation.dart';

import '../services/golden_gate_executor.dart';
import '../services/golden_test_runner.dart';
import '../services/golden_test_state.dart';
import 'device_diagnostics.dart';
import 'device_resource_sampler.dart';
import 'frame_timing_sampler.dart';
import 'handset_acceptance_models.dart';
import 'handset_acceptance_store.dart';
import 'handset_report_exporter.dart';
import 'pocketgallery_build_identity.dart';
import 'preservation_probe.dart';
import 'vector_acceptance.dart';

typedef GoldenAcceptanceRun = Future<GoldenTestReport> Function({
  GoldenProgressCallback? onProgress,
  GoldenTraceReadyCallback? onTraceReady,
});

typedef GoldenAcceptanceInterrupt = Future<void> Function(String reasonCode);

typedef KnownFixtureCleanup = Future<void> Function();

typedef PreservationCapture = Future<PreservationSnapshot> Function(
  DeviceIdentitySnapshot identity,
);

typedef VectorArtifactCapture = Future<VectorAcceptanceArtifact> Function(
  String traceId,
);

typedef VectorTruthEvaluation = VectorTruthResult Function(
  VectorAcceptanceArtifact artifact,
);

typedef VectorInteractionRun = Future<VectorInteractionResult> Function(
  VectorAcceptanceArtifact artifact,
);

typedef ModelReadinessProbe = Future<ModelReadinessResult> Function();

typedef HandsetProgressCallback = void Function(
  HandsetAcceptanceSnapshot snapshot,
);

abstract interface class HandsetAcceptanceController {
  ValueListenable<String?> get interruption;

  Future<HandsetAcceptanceSnapshot?> recoverInterruptedCheckpoint();

  Future<HandsetAcceptanceSnapshot> run({
    HandsetProgressCallback? onProgress,
    required VectorInteractionRun runInteraction,
  });

  Future<void> interrupt(String reasonCode);
}

abstract interface class HandsetAcceptancePersistence {
  Future<HandsetAcceptanceSnapshot?> readLast();

  Future<void> saveCheckpoint(HandsetAcceptanceSnapshot snapshot);

  Future<PreservationSnapshot?> readBaseline();

  Future<void> saveBaseline(PreservationSnapshot snapshot);

  Future<String> saveFinalReport(Uint8List bytes, String runId);
}

final class FileHandsetAcceptancePersistence
    implements HandsetAcceptancePersistence {
  const FileHandsetAcceptancePersistence(this.store);

  final HandsetAcceptanceStore store;

  @override
  Future<HandsetAcceptanceSnapshot?> readLast() => store.readLast();

  @override
  Future<void> saveCheckpoint(HandsetAcceptanceSnapshot snapshot) async {
    await store.saveCheckpoint(snapshot);
  }

  @override
  Future<PreservationSnapshot?> readBaseline() => store.readBaseline();

  @override
  Future<void> saveBaseline(PreservationSnapshot snapshot) async {
    await store.saveBaseline(snapshot);
  }

  @override
  Future<String> saveFinalReport(Uint8List bytes, String runId) async {
    return (await store.saveFinalReport(bytes, runId)).path;
  }
}

final class ModelReadinessResult {
  const ModelReadinessResult._(this.ready, this.reasonCode);

  const ModelReadinessResult.passed() : this._(true, null);

  const ModelReadinessResult.blocked(String reasonCode)
    : this._(false, reasonCode);

  final bool ready;
  final String? reasonCode;
}

final class VectorInteractionResult {
  const VectorInteractionResult({
    required this.rotationComplete,
    required this.zoomComplete,
    required this.selectionComplete,
    required this.viewportConfirmed,
    required this.frameTiming,
    this.reasonCode,
  });

  const VectorInteractionResult.blocked(
    this.reasonCode, {
    this.rotationComplete = false,
    this.zoomComplete = false,
    this.selectionComplete = false,
    this.viewportConfirmed = false,
    this.frameTiming = unavailableFrameTiming,
  });

  static const FrameTimingSummary unavailableFrameTiming = FrameTimingSummary(
    available: false,
    sampleDuration: Duration.zero,
    rawFrameCount: 0,
    warmUpFrameCount: 0,
    eligibleFrameCount: 0,
    p95: null,
    framesOver16Point7Count: 0,
    framesOver16Point7Ratio: 0,
    framesOver32Count: 0,
    framesOver32Ratio: 0,
  );

  final bool rotationComplete;
  final bool zoomComplete;
  final bool selectionComplete;
  final bool viewportConfirmed;
  final FrameTimingSummary frameTiming;
  final String? reasonCode;

  bool get interactionComplete =>
      rotationComplete &&
      zoomComplete &&
      selectionComplete &&
      viewportConfirmed &&
      frameTiming.available;
}

final class HandsetAcceptanceRunner implements HandsetAcceptanceController {
  HandsetAcceptanceRunner({
    required this.diagnostics,
    required this.persistence,
    required this.capturePreservation,
    required this.runGolden,
    required this.interruptGolden,
    required this.cleanupKnownFixtures,
    required this.captureVectorArtifact,
    required this.verifyVectorTruth,
    required this.probeModelReadiness,
    required this.resources,
    this.runtimeCleanupTimeout = const Duration(seconds: 12),
    DateTime Function()? clock,
    this.runIdFactory,
  }) : _clock = clock ?? DateTime.now;

  final DeviceDiagnosticsGateway diagnostics;
  final HandsetAcceptancePersistence persistence;
  final PreservationCapture capturePreservation;
  final GoldenAcceptanceRun runGolden;
  final GoldenAcceptanceInterrupt interruptGolden;
  final KnownFixtureCleanup cleanupKnownFixtures;
  final VectorArtifactCapture captureVectorArtifact;
  final VectorTruthEvaluation verifyVectorTruth;
  final ModelReadinessProbe probeModelReadiness;
  final DeviceResourceSampling resources;
  final Duration runtimeCleanupTimeout;
  final DateTime Function() _clock;
  final String Function()? runIdFactory;
  @override
  final ValueNotifier<String?> interruption = ValueNotifier<String?>(null);

  HandsetAcceptanceSnapshot? _current;
  Future<HandsetAcceptanceSnapshot?>? _recoveryFuture;
  bool _recoveryStopsNewRun = false;
  bool _runActive = false;
  bool _goldenActive = false;
  bool _cleanupBoundaryClosed = false;
  String? _interruptReason;
  Future<void>? _interruptFuture;
  Future<void>? _runtimeCleanupFuture;
  String? _runtimeCleanupError;
  int _runSequence = 0;

  DeviceIdentitySnapshot? _identity;
  PreservationSnapshot? _baseline;
  PreservationSnapshot? _preservationBefore;
  PreservationSnapshot? _preservationAfter;
  String? _preservationCaptureError;
  bool _resourceStartFailed = false;
  GoldenTestReport? _goldenReport;
  VectorAcceptanceArtifact? _vectorArtifact;
  String? _vectorCaptureError;
  VectorInteractionResult? _interactionResult;

  @override
  Future<HandsetAcceptanceSnapshot?> recoverInterruptedCheckpoint() {
    return _recoveryFuture ??= _recoverInterruptedCheckpoint();
  }

  @override
  Future<void> interrupt(String reasonCode) {
    if (!_runActive || _cleanupBoundaryClosed) {
      return Future<void>.value();
    }
    final normalized = reasonCode.trim().isEmpty
        ? 'INTERRUPTED'
        : reasonCode.trim();
    if (_interruptReason != null) {
      return _interruptFuture ?? Future<void>.value();
    }
    _interruptReason = normalized;
    interruption.value = normalized;
    if (_goldenActive) {
      _interruptFuture = Future<void>.sync(() => interruptGolden(normalized));
    }
    return _interruptFuture ?? Future<void>.value();
  }

  @override
  Future<HandsetAcceptanceSnapshot> run({
    HandsetProgressCallback? onProgress,
    required VectorInteractionRun runInteraction,
  }) async {
    if (_runActive) {
      throw StateError('A handset acceptance run is already active');
    }
    final recovered = await recoverInterruptedCheckpoint();
    if (_recoveryStopsNewRun && recovered != null) return recovered;

    _runActive = true;
    _resetRunState();
    try {
      try {
        await diagnostics.setKeepScreenOn(true);
        await _startRun(onProgress);
        await _runH1(onProgress);
        await _runH2(onProgress);
        await _runH3(onProgress);
        await _probeReadinessAndPreservation();
        await _startResources();
        await _runH4(onProgress);
        await _runH5(onProgress);
        await _runH6(onProgress, runInteraction);
        await _runH7(onProgress);
        await _runH9(onProgress);
        await _runH8(onProgress);
        await _finalizeRuntimeCleanup();
        await _writeBaselineIfEligible();
        return await _runH10(onProgress);
      } finally {
        await _finalizeRuntimeCleanup();
      }
    } finally {
      _goldenActive = false;
      _runActive = false;
    }
  }

  Future<HandsetAcceptanceSnapshot?> _recoverInterruptedCheckpoint() async {
    final last = await persistence.readLast();
    if (last == null || last.phase == HandsetRunPhase.completed) return last;

    String? cleanupError;
    try {
      await cleanupKnownFixtures();
    } catch (_) {
      cleanupError = 'KNOWN_FIXTURE_CLEANUP_FAILED';
      _recoveryStopsNewRun = true;
    }
    final now = _clock();
    final gates = <HandsetGateSnapshot>[
      for (final gate in last.gates)
        if (gate.status == HandsetGateStatus.pending ||
            gate.status == HandsetGateStatus.running)
          HandsetGateSnapshot(
            name: gate.name,
            label: gate.label,
            status: HandsetGateStatus.blocked,
            detail: 'PROCESS_INTERRUPTED',
            evidence: gate.evidence,
            startedAt: gate.startedAt ?? now,
            finishedAt: now,
          )
        else
          gate,
    ];
    final recovered = HandsetAcceptanceSnapshot(
      runId: last.runId,
      phase: HandsetRunPhase.completed,
      startedAt: last.startedAt,
      updatedAt: now,
      gates: gates,
      nestedGolden: last.nestedGolden,
      cleanupError: cleanupError,
      reportPath: last.reportPath,
      baselineVersionCode: last.baselineVersionCode,
      mergeCandidate: false,
    );
    await persistence.saveCheckpoint(recovered);
    return recovered;
  }

  void _resetRunState() {
    _interruptReason = null;
    _interruptFuture = null;
    _runtimeCleanupFuture = null;
    _runtimeCleanupError = null;
    _cleanupBoundaryClosed = false;
    interruption.value = null;
    _identity = null;
    _baseline = null;
    _preservationBefore = null;
    _preservationAfter = null;
    _preservationCaptureError = null;
    _resourceStartFailed = false;
    _goldenReport = null;
    _vectorArtifact = null;
    _vectorCaptureError = null;
    _interactionResult = null;
    _modelReadiness = const ModelReadinessResult.blocked(
      'MODEL_PREREQUISITE_MISSING',
    );
  }

  Future<void> _startRun(HandsetProgressCallback? onProgress) async {
    final now = _clock();
    _current = HandsetAcceptanceSnapshot(
      runId: _allocateRunId(),
      phase: HandsetRunPhase.preparing,
      startedAt: now,
      updatedAt: now,
      gates: <HandsetGateSnapshot>[
        for (final entry in _gateLabels.entries)
          HandsetGateSnapshot(
            name: entry.key,
            label: entry.value,
            status: HandsetGateStatus.pending,
            detail: '',
            evidence: const <AcceptanceEvidence>[],
          ),
      ],
    );
    await _publish(onProgress);
  }

  Future<void> _runH1(HandsetProgressCallback? onProgress) async {
    const name = 'H1_TARGET_DEVICE';
    await _beginGate(name, onProgress);
    final interruptionCode = _interruptReason;
    if (interruptionCode != null) {
      await _finishGate(
        name,
        HandsetGateStatus.blocked,
        interruptionCode,
        onProgress,
      );
      return;
    }
    try {
      _identity = await diagnostics.readIdentity();
    } catch (_) {
      await _finishGate(
        name,
        HandsetGateStatus.blocked,
        'REQUIRED_EVIDENCE_UNAVAILABLE',
        onProgress,
      );
      return;
    }
    final identity = _identity!;
    final evidence = <AcceptanceEvidence>[
      _evidence(
        code: 'TARGET_MANUFACTURER',
        source: 'Build.MANUFACTURER',
        actual: identity.manufacturer,
        threshold: 'samsung',
      ),
      _evidence(
        code: 'TARGET_MODEL',
        source: 'Build.MODEL',
        actual: identity.model,
        threshold: r'^SM-S928[A-Z0-9]*$',
      ),
    ];
    await _finishGate(
      name,
      identity.isTargetS24Ultra
          ? HandsetGateStatus.passed
          : HandsetGateStatus.blocked,
      identity.isTargetS24Ultra
          ? 'TARGET_DEVICE_CONFIRMED'
          : 'TARGET_DEVICE_MISMATCH',
      onProgress,
      evidence: evidence,
    );
  }

  Future<void> _runH2(HandsetProgressCallback? onProgress) async {
    const name = 'H2_BUILD_IDENTITY';
    await _beginGate(name, onProgress);
    final interruptionCode = _interruptReason;
    final identity = _identity;
    if (interruptionCode != null || identity == null) {
      await _finishGate(
        name,
        HandsetGateStatus.blocked,
        interruptionCode ?? 'REQUIRED_EVIDENCE_UNAVAILABLE',
        onProgress,
      );
      return;
    }
    final reasons = <String>[];
    if (identity.packageName != PocketGalleryBuildIdentity.packageName) {
      reasons.add('PACKAGE_IDENTITY_MISMATCH');
    }
    if (identity.signerSha256 !=
        PocketGalleryBuildIdentity.canonicalSignerSha256) {
      reasons.add('CANONICAL_SIGNER_UNAVAILABLE');
    }
    if (identity.apkSha256 == null) reasons.add('APK_DIGEST_UNAVAILABLE');
    if (!PocketGalleryBuildIdentity.isValidSourceCommit(
      identity.sourceCommit,
    )) {
      reasons.add('SOURCE_COMMIT_UNAVAILABLE');
    }
    if (identity.versionCode != 2022 && identity.versionCode != 2023) {
      reasons.add('VERSION_CODE_UNSUPPORTED');
    }
    final evidence = <AcceptanceEvidence>[
      _evidence(
        code: 'PACKAGE_NAME',
        source: 'PackageInfo.packageName',
        actual: identity.packageName,
        threshold: PocketGalleryBuildIdentity.packageName,
      ),
      _evidence(
        code: 'VERSION_CODE',
        source: 'PackageInfo.versionCode',
        actual: identity.versionCode,
        threshold: '2022|2023',
      ),
      _evidence(
        code: 'SIGNER_SHA256',
        source: 'PackageManager.signingInfo',
        actual: identity.signerSha256,
        threshold: PocketGalleryBuildIdentity.canonicalSignerSha256,
      ),
      _evidence(
        code: 'APK_SHA256',
        source: 'ApplicationInfo.sourceDir',
        actual: identity.apkSha256,
        threshold: 'SHA-256',
      ),
      _evidence(
        code: 'SOURCE_COMMIT',
        source: 'PocketGalleryBuildIdentity',
        actual: identity.sourceCommit,
        threshold: '40 hexadecimal characters',
      ),
    ];
    await _finishGate(
      name,
      reasons.isEmpty ? HandsetGateStatus.passed : HandsetGateStatus.blocked,
      reasons.isEmpty ? 'BUILD_IDENTITY_CONFIRMED' : reasons.join('|'),
      onProgress,
      evidence: evidence,
    );
  }

  Future<void> _runH3(HandsetProgressCallback? onProgress) async {
    const name = 'H3_UPGRADE_BASELINE';
    await _beginGate(name, onProgress);
    final interruptionCode = _interruptReason;
    if (interruptionCode != null) {
      await _finishGate(
        name,
        HandsetGateStatus.blocked,
        interruptionCode,
        onProgress,
      );
      return;
    }
    try {
      _baseline = await persistence.readBaseline();
    } catch (_) {
      await _finishGate(
        name,
        HandsetGateStatus.blocked,
        'REQUIRED_EVIDENCE_UNAVAILABLE',
        onProgress,
      );
      return;
    }
    final baseline = _baseline;
    if (baseline == null) {
      await _finishGate(
        name,
        HandsetGateStatus.blocked,
        'UPGRADE_BASELINE_MISSING',
        onProgress,
      );
      return;
    }
    final identity = _identity;
    final valid =
        identity != null &&
        baseline.versionCode != null &&
        identity.versionCode != null &&
        baseline.versionCode! < identity.versionCode! &&
        baseline.packageName == identity.packageName &&
        baseline.signerSha256 == identity.signerSha256;
    _replaceCurrent(baselineVersionCode: baseline.versionCode);
    await _finishGate(
      name,
      valid ? HandsetGateStatus.passed : HandsetGateStatus.blocked,
      valid ? 'UPGRADE_BASELINE_CONFIRMED' : 'UPGRADE_BASELINE_INVALID',
      onProgress,
      evidence: <AcceptanceEvidence>[
        _evidence(
          code: 'BASELINE_VERSION_CODE',
          source: 'PG_HANDSET_BASELINE.json',
          actual: baseline.versionCode,
          threshold: identity?.versionCode,
        ),
      ],
    );
  }

  ModelReadinessResult _modelReadiness = const ModelReadinessResult.blocked(
    'MODEL_PREREQUISITE_MISSING',
  );

  Future<void> _probeReadinessAndPreservation() async {
    try {
      _modelReadiness = await probeModelReadiness();
    } catch (_) {
      _modelReadiness = const ModelReadinessResult.blocked(
        'MODEL_PREREQUISITE_MISSING',
      );
    }
    final identity = _identity;
    if (identity == null) {
      _preservationCaptureError = 'REQUIRED_EVIDENCE_UNAVAILABLE';
      return;
    }
    try {
      _preservationBefore = await capturePreservation(identity);
    } catch (_) {
      _preservationCaptureError = 'PRESERVATION_CAPTURE_FAILED';
    }
  }

  Future<void> _startResources() async {
    try {
      await resources.start();
    } catch (_) {
      _resourceStartFailed = true;
    }
  }

  Future<void> _runH4(HandsetProgressCallback? onProgress) async {
    const name = 'H4_PHONE_FUNCTION_LOOP';
    _replaceCurrent(phase: HandsetRunPhase.runningAutomated);
    await _beginGate(name, onProgress);
    final blockedReason = _dependencyBlockReason();
    if (blockedReason != null) {
      await _finishGate(
        name,
        HandsetGateStatus.blocked,
        blockedReason,
        onProgress,
      );
      return;
    }

    var progressWrites = Future<void>.value();
    void relayGoldenProgress(GoldenTestSnapshot nested) {
      progressWrites = progressWrites.then((_) async {
        _replaceCurrent(nestedGolden: nested);
        await _publish(onProgress);
      });
    }

    Future<void> captureTrace(String traceId) async {
      try {
        _vectorArtifact = await captureVectorArtifact(traceId);
      } catch (_) {
        _vectorCaptureError = 'VECTOR_TRACE_CAPTURE_FAILED';
      }
    }

    try {
      _goldenActive = true;
      _goldenReport = await runGolden(
        onProgress: relayGoldenProgress,
        onTraceReady: captureTrace,
      );
      await progressWrites;
    } catch (_) {
      await progressWrites;
      final interruptionCode = _interruptReason;
      await _finishGate(
        name,
        interruptionCode == null
            ? HandsetGateStatus.failed
            : HandsetGateStatus.blocked,
        interruptionCode ?? 'PHONE_FUNCTION_LOOP_FAILED',
        onProgress,
      );
      return;
    } finally {
      _goldenActive = false;
    }

    final report = _goldenReport!;
    if (report.snapshot != null) {
      _replaceCurrent(nestedGolden: report.snapshot);
    }
    final interruptionCode = _interruptReason;
    if (interruptionCode != null) {
      await _finishGate(
        name,
        HandsetGateStatus.blocked,
        interruptionCode,
        onProgress,
      );
      return;
    }
    if (report.passed) {
      await _finishGate(
        name,
        HandsetGateStatus.passed,
        'PHONE_FUNCTION_LOOP_PASSED',
        onProgress,
      );
      return;
    }
    final nested = report.snapshot;
    final failed =
        nested?.cleanupError != null ||
        (nested?.gates.any(
              (gate) =>
                  gate.status == GoldenGateStatus.failed ||
                  gate.status == GoldenGateStatus.timedOut,
            ) ??
            true);
    await _finishGate(
      name,
      failed ? HandsetGateStatus.failed : HandsetGateStatus.blocked,
      nested?.cleanupError != null
          ? 'GOLDEN_CLEANUP_FAILED'
          : failed
          ? 'PHONE_FUNCTION_LOOP_FAILED'
          : 'PHONE_FUNCTION_LOOP_BLOCKED',
      onProgress,
    );
  }

  Future<void> _runH5(HandsetProgressCallback? onProgress) async {
    const name = 'H5_VECTOR_3D_TRUTH';
    await _beginGate(name, onProgress);
    final blockedReason = _postGoldenBlockReason();
    if (blockedReason != null) {
      await _finishGate(
        name,
        HandsetGateStatus.blocked,
        blockedReason,
        onProgress,
      );
      return;
    }
    final artifact = _vectorArtifact;
    if (artifact == null) {
      await _finishGate(
        name,
        HandsetGateStatus.blocked,
        _vectorCaptureError ?? 'VECTOR_TRACE_UNAVAILABLE',
        onProgress,
      );
      return;
    }
    try {
      final result = verifyVectorTruth(artifact);
      final evidence = <AcceptanceEvidence>[];
      for (final entry in result.evidence.entries) {
        final actual = entry.value;
        if (actual == null ||
            actual is String ||
            actual is num ||
            actual is bool) {
          evidence.add(
            _evidence(
              code: entry.key.toUpperCase(),
              source: 'VectorTruthVerifier',
              actual: actual,
              threshold: null,
            ),
          );
        }
      }
      await _finishGate(
        name,
        result.passed ? HandsetGateStatus.passed : HandsetGateStatus.failed,
        result.passed ? 'VECTOR_3D_TRUTH_PASSED' : result.reasonCodes.join('|'),
        onProgress,
        evidence: evidence,
      );
    } catch (_) {
      await _finishGate(
        name,
        HandsetGateStatus.failed,
        'VECTOR_3D_TRUTH_FAILED',
        onProgress,
      );
    }
  }

  Future<void> _runH6(
    HandsetProgressCallback? onProgress,
    VectorInteractionRun runInteraction,
  ) async {
    const name = 'H6_VECTOR_INTERACTION';
    _replaceCurrent(phase: HandsetRunPhase.awaitingInteraction);
    await _beginGate(name, onProgress);
    final blockedReason = _postGoldenBlockReason();
    final artifact = _vectorArtifact;
    if (blockedReason != null || artifact == null) {
      await _finishGate(
        name,
        HandsetGateStatus.blocked,
        blockedReason ?? _vectorCaptureError ?? 'VECTOR_TRACE_UNAVAILABLE',
        onProgress,
      );
      return;
    }
    try {
      _interactionResult = await runInteraction(artifact);
    } catch (_) {
      await _finishGate(
        name,
        HandsetGateStatus.failed,
        'VECTOR_INTERACTION_FAILED',
        onProgress,
      );
      return;
    }
    final result = _interactionResult!;
    final reason = result.reasonCode;
    final passed = reason == null && result.interactionComplete;
    await _finishGate(
      name,
      passed ? HandsetGateStatus.passed : HandsetGateStatus.blocked,
      passed ? 'VECTOR_INTERACTION_PASSED' : reason ?? 'USER_ACTION_INCOMPLETE',
      onProgress,
      evidence: <AcceptanceEvidence>[
        _evidence(
          code: 'ROTATION_COMPLETE',
          source: 'InteractiveVectorPlot',
          actual: result.rotationComplete,
          threshold: true,
          method: EvidenceMethod.userAction,
        ),
        _evidence(
          code: 'ZOOM_COMPLETE',
          source: 'InteractiveVectorPlot',
          actual: result.zoomComplete,
          threshold: true,
          method: EvidenceMethod.userAction,
        ),
        _evidence(
          code: 'SELECTION_COMPLETE',
          source: 'InteractiveVectorPlot',
          actual: result.selectionComplete,
          threshold: true,
          method: EvidenceMethod.userAction,
        ),
        _evidence(
          code: 'VIEWPORT_CONFIRMED',
          source: 'HandsetVectorInteractionPage',
          actual: result.viewportConfirmed,
          threshold: true,
          method: EvidenceMethod.userAction,
        ),
      ],
    );
  }

  Future<void> _runH7(HandsetProgressCallback? onProgress) async {
    const name = 'H7_RENDER_PERFORMANCE';
    _replaceCurrent(phase: HandsetRunPhase.runningPostChecks);
    await _beginGate(name, onProgress);
    final blockedReason = _postGoldenBlockReason();
    final frame = _interactionResult?.frameTiming;
    if (blockedReason != null || frame == null || !frame.available) {
      await _finishGate(
        name,
        HandsetGateStatus.blocked,
        blockedReason ?? 'FRAME_TIMING_UNAVAILABLE',
        onProgress,
      );
      return;
    }
    await _finishGate(
      name,
      frame.passesReleaseThreshold
          ? HandsetGateStatus.passed
          : HandsetGateStatus.failed,
      frame.passesReleaseThreshold
          ? 'RENDER_PERFORMANCE_PASSED'
          : 'RENDER_PERFORMANCE_REGRESSION',
      onProgress,
      evidence: <AcceptanceEvidence>[
        _evidence(
          code: 'FRAME_SAMPLE_DURATION_MS',
          source: 'SchedulerBinding.addTimingsCallback',
          actual: frame.sampleDuration.inMilliseconds,
          threshold: 15000,
          unit: 'ms',
        ),
        _evidence(
          code: 'FRAME_ELIGIBLE_COUNT',
          source: 'SchedulerBinding.addTimingsCallback',
          actual: frame.eligibleFrameCount,
          threshold: 180,
          unit: 'frames',
        ),
        _evidence(
          code: 'FRAME_P95_MS',
          source: 'SchedulerBinding.addTimingsCallback',
          actual: frame.p95?.inMicroseconds == null
              ? null
              : frame.p95!.inMicroseconds / 1000,
          threshold: 16.7,
          unit: 'ms',
        ),
        _evidence(
          code: 'FRAMES_OVER_32_RATIO',
          source: 'SchedulerBinding.addTimingsCallback',
          actual: frame.framesOver32Ratio,
          threshold: 0.01,
          unit: '%',
        ),
      ],
    );
  }

  Future<void> _runH9(HandsetProgressCallback? onProgress) async {
    const name = 'H9_DATA_PRESERVATION';
    await _beginGate(name, onProgress);
    final interruptionCode = _interruptReason;
    if (interruptionCode != null) {
      await _finishGate(
        name,
        HandsetGateStatus.blocked,
        interruptionCode,
        onProgress,
      );
      return;
    }
    final before = _preservationBefore;
    final identity = _identity;
    if (before == null || identity == null) {
      await _finishGate(
        name,
        HandsetGateStatus.failed,
        _preservationCaptureError ?? 'PRESERVATION_CAPTURE_FAILED',
        onProgress,
      );
      return;
    }
    try {
      _preservationAfter = await capturePreservation(identity);
    } catch (_) {
      await _finishGate(
        name,
        HandsetGateStatus.failed,
        'PRESERVATION_CAPTURE_FAILED',
        onProgress,
      );
      return;
    }
    final lateInterruptionCode = _interruptReason;
    if (lateInterruptionCode != null) {
      await _finishGate(
        name,
        HandsetGateStatus.blocked,
        lateInterruptionCode,
        onProgress,
      );
      return;
    }
    final after = _preservationAfter!;
    final reasons = <String>{
      ...PreservationComparison.compare(
        baseline: before,
        current: after,
        requirePreviousVersion: false,
      ).reasonCodes,
    };
    if (_gateStatus('H3_UPGRADE_BASELINE') == HandsetGateStatus.passed &&
        _baseline != null) {
      reasons.addAll(
        PreservationComparison.compare(
          baseline: _baseline!,
          current: after,
        ).reasonCodes,
      );
    }
    await _finishGate(
      name,
      reasons.isEmpty ? HandsetGateStatus.passed : HandsetGateStatus.failed,
      reasons.isEmpty ? 'DATA_PRESERVATION_PASSED' : reasons.join('|'),
      onProgress,
    );
  }

  Future<void> _runH8(HandsetProgressCallback? onProgress) async {
    const name = 'H8_MEMORY_THERMAL';
    await _beginGate(name, onProgress);
    if (_resourceStartFailed) {
      await _finishGate(
        name,
        HandsetGateStatus.blocked,
        'REQUIRED_EVIDENCE_UNAVAILABLE',
        onProgress,
      );
      return;
    }
    ResourceAcceptanceSummary summary;
    try {
      summary = await resources.stop().timeout(runtimeCleanupTimeout);
    } catch (_) {
      await _finishGate(
        name,
        HandsetGateStatus.blocked,
        'REQUIRED_EVIDENCE_UNAVAILABLE',
        onProgress,
      );
      return;
    }
    final interruptionCode = _interruptReason;
    final unavailable = summary.reasonCodes.contains(
      'REQUIRED_EVIDENCE_UNAVAILABLE',
    );
    final failed = summary.reasonCodes.any(
      (reason) =>
          reason == 'MEMORY_PRESSURE' || reason == 'THERMAL_LIMIT_EXCEEDED',
    );
    final status = interruptionCode != null
        ? HandsetGateStatus.blocked
        : failed
        ? HandsetGateStatus.failed
        : unavailable
        ? HandsetGateStatus.blocked
        : HandsetGateStatus.passed;
    await _finishGate(
      name,
      status,
      interruptionCode ??
          (summary.passed
              ? 'MEMORY_THERMAL_PASSED'
              : summary.reasonCodes.join('|')),
      onProgress,
      evidence: <AcceptanceEvidence>[
        _evidence(
          code: 'BASELINE_PSS_KIB',
          source: 'Debug.getPss',
          actual: summary.baselinePssKiB,
          threshold: ResourceAcceptanceSummary.maximumPssGrowthKiB,
          unit: 'KiB',
        ),
        _evidence(
          code: 'FINAL_PSS_GROWTH_KIB',
          source: 'Debug.getPss',
          actual: summary.pssGrowthKiB,
          threshold: ResourceAcceptanceSummary.maximumPssGrowthKiB,
          unit: 'KiB',
        ),
        _evidence(
          code: 'MIN_AVAILABLE_MEMORY_BYTES',
          source: 'ActivityManager.MemoryInfo',
          actual: summary.minimumAvailableMemoryBytes,
          threshold: null,
          unit: 'bytes',
        ),
        _evidence(
          code: 'MAX_THERMAL_STATUS',
          source: 'PowerManager.currentThermalStatus',
          actual: summary.maxThermalStatus,
          threshold: ResourceAcceptanceSummary.severeThermalStatus,
        ),
        _evidence(
          code: 'PEAK_PSS_KIB',
          source: 'Debug.getPss',
          actual: summary.peakPssKiB,
          threshold: null,
          unit: 'KiB',
        ),
        _evidence(
          code: 'PEAK_BATTERY_TEMPERATURE_C',
          source: 'ACTION_BATTERY_CHANGED',
          actual: summary.peakBatteryTemperatureC,
          threshold: null,
          unit: '°C',
        ),
      ],
    );
  }

  Future<void> _writeBaselineIfEligible() async {
    if (_baseline != null ||
        _identity?.versionCode != 2022 ||
        _interruptReason != null ||
        !_cleanupBoundaryClosed ||
        _runtimeCleanupError != null ||
        _current?.cleanupError != null ||
        _preservationAfter == null ||
        _goldenReport?.snapshot?.cleanupError != null) {
      return;
    }
    const required = <String>[
      'H1_TARGET_DEVICE',
      'H2_BUILD_IDENTITY',
      'H4_PHONE_FUNCTION_LOOP',
      'H5_VECTOR_3D_TRUTH',
      'H6_VECTOR_INTERACTION',
      'H7_RENDER_PERFORMANCE',
      'H8_MEMORY_THERMAL',
      'H9_DATA_PRESERVATION',
    ];
    if (!required.every(
      (name) => _gateStatus(name) == HandsetGateStatus.passed,
    )) {
      return;
    }
    await persistence.saveBaseline(_preservationAfter!);
    _replaceCurrent(baselineVersionCode: _preservationAfter!.versionCode);
  }

  Future<HandsetAcceptanceSnapshot> _runH10(
    HandsetProgressCallback? onProgress,
  ) async {
    const name = 'H10_REPORT_INTEGRITY';
    _replaceCurrent(phase: HandsetRunPhase.cleaningUp);
    await _beginGate(name, onProgress);
    final now = _clock();
    final interruptionCode = _interruptReason;
    final status = interruptionCode == null
        ? HandsetGateStatus.passed
        : HandsetGateStatus.blocked;
    final mergeCandidate =
        status == HandsetGateStatus.passed && _isMergeCandidateEligible();
    final prospective = _snapshotWithGate(
      _current!,
      name,
      status,
      interruptionCode ?? 'REPORT_INTEGRITY_PASSED',
      finishedAt: now,
      phase: HandsetRunPhase.completed,
      updatedAt: now,
      mergeCandidate: mergeCandidate,
    );
    try {
      final bytes = HandsetReportExporter.encodeRedacted(prospective);
      final path = await persistence.saveFinalReport(bytes, prospective.runId);
      final completed = _copySnapshot(prospective, reportPath: path);
      await persistence.saveCheckpoint(completed);
      _current = completed;
      onProgress?.call(completed);
      return completed;
    } catch (_) {
      final failed = _snapshotWithGate(
        _current!,
        name,
        HandsetGateStatus.failed,
        'REPORT_INTEGRITY_FAILED',
        finishedAt: _clock(),
        phase: HandsetRunPhase.completed,
        updatedAt: _clock(),
        mergeCandidate: false,
      );
      _current = failed;
      try {
        await persistence.saveCheckpoint(failed);
        onProgress?.call(failed);
      } catch (_) {
        // The in-memory failure remains authoritative when persistence failed.
      }
      return failed;
    }
  }

  bool _isMergeCandidateEligible() {
    final identity = _identity;
    final baseline = _baseline;
    if (identity == null ||
        baseline == null ||
        !_cleanupBoundaryClosed ||
        _interruptReason != null ||
        _runtimeCleanupError != null ||
        _current?.cleanupError != null) {
      return false;
    }
    return _gateLabels.keys
            .where((name) => name != 'H10_REPORT_INTEGRITY')
            .every((name) => _gateStatus(name) == HandsetGateStatus.passed) &&
        identity.isTargetS24Ultra &&
        identity.packageName == PocketGalleryBuildIdentity.packageName &&
        identity.versionCode == 2023 &&
        identity.signerSha256 ==
            PocketGalleryBuildIdentity.canonicalSignerSha256 &&
        identity.apkSha256 != null &&
        PocketGalleryBuildIdentity.isValidSourceCommit(identity.sourceCommit) &&
        baseline.versionCode != null &&
        baseline.versionCode! < 2023 &&
        baseline.packageName == identity.packageName &&
        baseline.signerSha256 == identity.signerSha256;
  }

  Future<void> _finalizeRuntimeCleanup() {
    return _runtimeCleanupFuture ??= _performRuntimeCleanup();
  }

  Future<void> _performRuntimeCleanup() async {
    var failed = false;
    try {
      await resources.stopIfRunning().timeout(runtimeCleanupTimeout);
    } catch (_) {
      failed = true;
    }
    try {
      await diagnostics.setKeepScreenOn(false).timeout(runtimeCleanupTimeout);
    } catch (_) {
      failed = true;
    }
    if (failed) {
      _runtimeCleanupError = 'RUNTIME_CLEANUP_FAILED';
      if (_current != null) {
        _replaceCurrent(cleanupError: _runtimeCleanupError);
      }
    }
    _cleanupBoundaryClosed = true;
  }

  String? _dependencyBlockReason() {
    final interruptionCode = _interruptReason;
    if (interruptionCode != null) return interruptionCode;
    if (!_modelReadiness.ready) {
      return _modelReadiness.reasonCode ?? 'MODEL_PREREQUISITE_MISSING';
    }
    return null;
  }

  String? _postGoldenBlockReason() {
    final dependency = _dependencyBlockReason();
    if (dependency != null) return dependency;
    if (_gateStatus('H4_PHONE_FUNCTION_LOOP') != HandsetGateStatus.passed) {
      return 'PHONE_FUNCTION_LOOP_UNAVAILABLE';
    }
    return null;
  }

  Future<void> _beginGate(
    String name,
    HandsetProgressCallback? onProgress,
  ) async {
    final now = _clock();
    _replaceGate(
      HandsetGateSnapshot(
        name: name,
        label: _gateLabels[name]!,
        status: HandsetGateStatus.running,
        detail: '',
        evidence: const <AcceptanceEvidence>[],
        startedAt: now,
      ),
    );
    await _publish(onProgress);
  }

  Future<void> _finishGate(
    String name,
    HandsetGateStatus status,
    String detail,
    HandsetProgressCallback? onProgress, {
    List<AcceptanceEvidence> evidence = const <AcceptanceEvidence>[],
  }) async {
    final previous = _current!.gates.singleWhere((gate) => gate.name == name);
    _replaceGate(
      HandsetGateSnapshot(
        name: name,
        label: previous.label,
        status: status,
        detail: detail,
        evidence: evidence,
        startedAt: previous.startedAt ?? _clock(),
        finishedAt: _clock(),
      ),
    );
    await _publish(onProgress);
  }

  void _replaceGate(HandsetGateSnapshot replacement) {
    _replaceCurrent(
      gates: <HandsetGateSnapshot>[
        for (final gate in _current!.gates)
          if (gate.name == replacement.name) replacement else gate,
      ],
    );
  }

  HandsetGateStatus _gateStatus(String name) {
    return _current!.gates.singleWhere((gate) => gate.name == name).status;
  }

  Future<void> _publish(HandsetProgressCallback? onProgress) async {
    _replaceCurrent(updatedAt: _clock());
    final snapshot = _current!;
    await persistence.saveCheckpoint(snapshot);
    onProgress?.call(snapshot);
  }

  void _replaceCurrent({
    HandsetRunPhase? phase,
    DateTime? updatedAt,
    List<HandsetGateSnapshot>? gates,
    Object? nestedGolden = _unset,
    Object? cleanupError = _unset,
    Object? reportPath = _unset,
    Object? baselineVersionCode = _unset,
    bool? mergeCandidate,
  }) {
    _current = _copySnapshot(
      _current!,
      phase: phase,
      updatedAt: updatedAt,
      gates: gates,
      nestedGolden: nestedGolden,
      cleanupError: cleanupError,
      reportPath: reportPath,
      baselineVersionCode: baselineVersionCode,
      mergeCandidate: mergeCandidate,
    );
  }

  String _allocateRunId() {
    final supplied = runIdFactory?.call().trim();
    if (supplied != null && supplied.isNotEmpty) return supplied;
    _runSequence += 1;
    return 'r50-${_clock().toUtc().microsecondsSinceEpoch}-$_runSequence';
  }
}

HandsetAcceptanceSnapshot _copySnapshot(
  HandsetAcceptanceSnapshot source, {
  HandsetRunPhase? phase,
  DateTime? updatedAt,
  List<HandsetGateSnapshot>? gates,
  Object? nestedGolden = _unset,
  Object? cleanupError = _unset,
  Object? reportPath = _unset,
  Object? baselineVersionCode = _unset,
  bool? mergeCandidate,
}) {
  return HandsetAcceptanceSnapshot(
    runId: source.runId,
    phase: phase ?? source.phase,
    startedAt: source.startedAt,
    updatedAt: updatedAt ?? source.updatedAt,
    gates: gates ?? source.gates,
    nestedGolden: identical(nestedGolden, _unset)
        ? source.nestedGolden
        : nestedGolden as GoldenTestSnapshot?,
    cleanupError: identical(cleanupError, _unset)
        ? source.cleanupError
        : cleanupError as String?,
    reportPath: identical(reportPath, _unset)
        ? source.reportPath
        : reportPath as String?,
    baselineVersionCode: identical(baselineVersionCode, _unset)
        ? source.baselineVersionCode
        : baselineVersionCode as int?,
    mergeCandidate: mergeCandidate ?? source.mergeCandidate,
  );
}

HandsetAcceptanceSnapshot _snapshotWithGate(
  HandsetAcceptanceSnapshot source,
  String name,
  HandsetGateStatus status,
  String detail, {
  required DateTime finishedAt,
  required HandsetRunPhase phase,
  required DateTime updatedAt,
  required bool mergeCandidate,
}) {
  return _copySnapshot(
    source,
    phase: phase,
    updatedAt: updatedAt,
    gates: <HandsetGateSnapshot>[
      for (final gate in source.gates)
        if (gate.name == name)
          HandsetGateSnapshot(
            name: gate.name,
            label: gate.label,
            status: status,
            detail: detail,
            evidence: gate.evidence,
            startedAt: gate.startedAt,
            finishedAt: finishedAt,
          )
        else
          gate,
    ],
    mergeCandidate: mergeCandidate,
  );
}

AcceptanceEvidence _evidence({
  required String code,
  required String source,
  required Object? actual,
  required Object? threshold,
  String? unit,
  EvidenceMethod method = EvidenceMethod.measured,
}) {
  return AcceptanceEvidence(
    code: code,
    method: method,
    source: source,
    actual: actual,
    threshold: threshold,
    unit: unit,
    available: actual != null,
    detail: actual == null ? 'EVIDENCE_UNAVAILABLE' : 'EVIDENCE_RECORDED',
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

const Object _unset = Object();
