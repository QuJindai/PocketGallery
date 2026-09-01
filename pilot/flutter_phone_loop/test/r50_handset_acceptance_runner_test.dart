import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketgallery_phone_pilot/acceptance/device_diagnostics.dart';
import 'package:pocketgallery_phone_pilot/acceptance/device_resource_sampler.dart';
import 'package:pocketgallery_phone_pilot/acceptance/frame_timing_sampler.dart';
import 'package:pocketgallery_phone_pilot/acceptance/handset_acceptance_models.dart';
import 'package:pocketgallery_phone_pilot/acceptance/handset_acceptance_runner.dart';
import 'package:pocketgallery_phone_pilot/acceptance/pocketgallery_build_identity.dart';
import 'package:pocketgallery_phone_pilot/acceptance/preservation_probe.dart';
import 'package:pocketgallery_phone_pilot/acceptance/vector_acceptance.dart';
import 'package:pocketgallery_phone_pilot/services/golden_test_runner.dart';
import 'package:pocketgallery_phone_pilot/services/golden_test_state.dart';
import 'package:pocketgallery_phone_pilot/services/hf_oauth_device_service.dart';

void main() {
  test('candidate 2023 with a valid 2022 baseline passes every gate', () async {
    final harness = _Harness();

    final result = await harness.runner.run(
      runInteraction: harness.runPassingInteraction,
    );

    expect(result.verdict, AcceptanceVerdict.pass);
    expect(result.mergeCandidate, isTrue);
    expect(
      result.gates.map((gate) => gate.status),
      everyElement(HandsetGateStatus.passed),
    );
    expect(result.reportPath, '/reports/${result.runId}.json');
    expect(harness.persistence.finalReports.single, isNotEmpty);
    expect(harness.diagnostics.keepScreenOnValues, <bool>[true, false]);
    expect(harness.resources.startCount, 1);
    expect(harness.resources.stopCount, 1);
  });

  test('missing baseline stays BLOCKED and writes helper baseline after H8',
      () async {
    final events = <String>[];
    final harness = _Harness(
      identity: _identity(versionCode: 2022),
      hasBaseline: false,
      events: events,
    );

    final result = await harness.runner.run(
      runInteraction: harness.runPassingInteraction,
    );

    expect(result.verdict, AcceptanceVerdict.blocked);
    expect(result.mergeCandidate, isFalse);
    expect(
      _gate(result, 'H3_UPGRADE_BASELINE').detail,
      'UPGRADE_BASELINE_MISSING',
    );
    expect(harness.persistence.savedBaselines, hasLength(1));
    expect(harness.persistence.savedBaselines.single.versionCode, 2022);
    expect(events.indexOf('preservation:after'), lessThan(events.indexOf('resources:stop')));
    expect(events.indexOf('resources:stop'), lessThan(events.indexOf('baseline:save')));
    expect(events, contains('screen:off'));
    expect(events.indexOf('screen:off'), lessThan(events.indexOf('baseline:save')));
  });

  test('non-target or non-canonical helper never establishes a baseline',
      () async {
    final identities = <DeviceIdentitySnapshot>[
      _identity(versionCode: 2022, manufacturer: 'Google', model: 'Pixel 9'),
      _identity(versionCode: 2022, signerSha256: _otherDigest),
    ];

    for (final identity in identities) {
      final harness = _Harness(
        identity: identity,
        hasBaseline: false,
      );
      final result = await harness.runner.run(
        runInteraction: harness.runPassingInteraction,
      );

      expect(result.verdict, AcceptanceVerdict.blocked);
      expect(harness.persistence.savedBaselines, isEmpty);
    }
  });

  test('H7 render failure outranks an H3 missing-baseline block', () async {
    final harness = _Harness(
      identity: _identity(versionCode: 2022),
      hasBaseline: false,
      frameTiming: _failingFrameTiming,
    );

    final result = await harness.runner.run(
      runInteraction: harness.runPassingInteraction,
    );

    expect(_gate(result, 'H3_UPGRADE_BASELINE').status, HandsetGateStatus.blocked);
    expect(_gate(result, 'H7_RENDER_PERFORMANCE').status, HandsetGateStatus.failed);
    expect(result.verdict, AcceptanceVerdict.fail);
    expect(harness.persistence.savedBaselines, isEmpty);
  });

  test('missing model blocks dependent gates but still finalizes a report',
      () async {
    final harness = _Harness(modelReady: false);

    final result = await harness.runner.run(
      runInteraction: harness.runPassingInteraction,
    );

    for (final name in <String>[
      'H4_PHONE_FUNCTION_LOOP',
      'H5_VECTOR_3D_TRUTH',
      'H6_VECTOR_INTERACTION',
      'H7_RENDER_PERFORMANCE',
    ]) {
      expect(_gate(result, name).status, HandsetGateStatus.blocked);
      expect(_gate(result, name).detail, 'MODEL_PREREQUISITE_MISSING');
    }
    expect(_gate(result, 'H10_REPORT_INTEGRITY').status, HandsetGateStatus.passed);
    expect(result.verdict, AcceptanceVerdict.blocked);
    expect(harness.goldenRunCount, 0);
    expect(harness.persistence.finalReports, hasLength(1));
  });

  test('interrupt is cooperative, idempotent, and cleans up the active run',
      () async {
    final enteredGolden = Completer<void>();
    final releaseGolden = Completer<void>();
    var nestedInterrupts = 0;
    late _Harness harness;
    harness = _Harness(
      goldenRun: ({onProgress, onTraceReady}) async {
        harness.goldenRunCount += 1;
        enteredGolden.complete();
        await releaseGolden.future;
        return _passingGoldenReport();
      },
      goldenInterrupt: (reasonCode) async {
        nestedInterrupts += 1;
        expect(reasonCode, 'APP_BACKGROUND_INTERRUPTION');
        if (!releaseGolden.isCompleted) releaseGolden.complete();
      },
    );

    final run = harness.runner.run(
      runInteraction: harness.runPassingInteraction,
    );
    await enteredGolden.future;
    await harness.runner.interrupt('APP_BACKGROUND_INTERRUPTION');
    await harness.runner.interrupt('USER_CANCELLED');
    final result = await run;

    expect(nestedInterrupts, 1);
    expect(_gate(result, 'H4_PHONE_FUNCTION_LOOP').status, HandsetGateStatus.blocked);
    expect(
      _gate(result, 'H4_PHONE_FUNCTION_LOOP').detail,
      'APP_BACKGROUND_INTERRUPTION',
    );
    expect(result.verdict, AcceptanceVerdict.blocked);
    expect(harness.resources.stopCount, 1);
    expect(harness.diagnostics.keepScreenOnValues.last, isFalse);
  });

  test('keepScreenOn false executes even when setup throws', () async {
    final diagnostics = _FakeDiagnostics(
      identity: _identity(),
      throwWhenEnablingScreen: true,
    );
    final harness = _Harness(diagnostics: diagnostics);

    await expectLater(
      harness.runner.run(runInteraction: harness.runPassingInteraction),
      throwsStateError,
    );

    expect(diagnostics.keepScreenOnValues, <bool>[true, false]);
  });

  test('interrupt after awaited H9 capture blocks terminal merge', () async {
    final enteredAfterCapture = Completer<void>();
    final releaseAfterCapture = Completer<void>();
    var captureCount = 0;
    final harness = _Harness(
      preservationCapture: (identity) async {
        captureCount += 1;
        if (captureCount == 2) {
          enteredAfterCapture.complete();
          await releaseAfterCapture.future;
        }
        return _preservation(versionCode: identity.versionCode ?? 2023);
      },
    );

    final run = harness.runner.run(
      runInteraction: harness.runPassingInteraction,
    );
    await enteredAfterCapture.future;
    await harness.runner.interrupt('APP_BACKGROUND_INTERRUPTION');
    releaseAfterCapture.complete();
    final result = await run;

    expect(
      _gate(result, 'H9_DATA_PRESERVATION').status,
      HandsetGateStatus.blocked,
    );
    expect(
      _gate(result, 'H9_DATA_PRESERVATION').detail,
      'APP_BACKGROUND_INTERRUPTION',
    );
    expect(result.mergeCandidate, isFalse);
    expect(result.verdict, AcceptanceVerdict.blocked);
  });

  test('interrupt while H8 stop is awaited cannot publish PASS', () async {
    final enteredStop = Completer<void>();
    final releaseStop = Completer<void>();
    final resources = _FakeResourceSampler(
      _passingResourceSummary(),
      stopEntered: enteredStop,
      stopBarrier: releaseStop,
    );
    final harness = _Harness(resourceSampler: resources);

    final run = harness.runner.run(
      runInteraction: harness.runPassingInteraction,
    );
    await enteredStop.future;
    await harness.runner.interrupt('APP_BACKGROUND_INTERRUPTION');
    releaseStop.complete();
    final result = await run;

    expect(
      _gate(result, 'H8_MEMORY_THERMAL').status,
      HandsetGateStatus.blocked,
    );
    expect(_gate(result, 'H8_MEMORY_THERMAL').detail,
        'APP_BACKGROUND_INTERRUPTION');
    expect(result.mergeCandidate, isFalse);
    expect(result.verdict, AcceptanceVerdict.blocked);
  });

  test('cleanup boundary closes before H10 report persistence', () async {
    final events = <String>[];
    final reportEntered = Completer<void>();
    final releaseReport = Completer<void>();
    final diagnostics = _FakeDiagnostics(
      identity: _identity(),
      events: events,
    );
    final persistence = _MemoryPersistence(
      baseline: _baseline(),
      events: events,
      finalReportEntered: reportEntered,
      finalReportBarrier: releaseReport,
    );
    final harness = _Harness(
      diagnostics: diagnostics,
      persistence: persistence,
      events: events,
    );

    final run = harness.runner.run(
      runInteraction: harness.runPassingInteraction,
    );
    await reportEntered.future;

    final screenReleasedBeforeReport = events.contains('screen:off') &&
        events.indexOf('screen:off') < events.indexOf('report:save');
    await harness.runner.interrupt('USER_CANCELLED');
    final lateInterruptIgnored = harness.runner.interruption.value == null;

    releaseReport.complete();
    final result = await run;
    expect(screenReleasedBeforeReport, isTrue);
    expect(lateInterruptIgnored, isTrue);
    expect(result.verdict, AcceptanceVerdict.pass);
    expect(result.mergeCandidate, isTrue);
  });

  test('screen release failure is terminal FAIL evidence, never a thrown PASS',
      () async {
    final diagnostics = _FakeDiagnostics(
      identity: _identity(),
      throwWhenDisablingScreen: true,
    );
    final harness = _Harness(diagnostics: diagnostics);

    final result = await harness.runner.run(
      runInteraction: harness.runPassingInteraction,
    );

    expect(result.cleanupError, 'RUNTIME_CLEANUP_FAILED');
    expect(result.verdict, AcceptanceVerdict.fail);
    expect(result.mergeCandidate, isFalse);
    expect(harness.persistence.finalReports, hasLength(1));
  });

  test('resource stop failure is terminal FAIL evidence, never a thrown PASS',
      () async {
    final resources = _FakeResourceSampler(
      _passingResourceSummary(),
      throwOnStop: true,
    );
    final harness = _Harness(resourceSampler: resources);

    final result = await harness.runner.run(
      runInteraction: harness.runPassingInteraction,
    );

    expect(result.cleanupError, 'RUNTIME_CLEANUP_FAILED');
    expect(result.verdict, AcceptanceVerdict.fail);
    expect(result.mergeCandidate, isFalse);
    expect(harness.persistence.finalReports, hasLength(1));
  });

  test('runtime cleanup gives both native shutdown calls a hard timeout',
      () async {
    final source =
        await File('lib/acceptance/handset_acceptance_runner.dart')
            .readAsString();

    expect(
      RegExp(r'\.timeout\(runtimeCleanupTimeout\)')
          .allMatches(source)
          .length,
      greaterThanOrEqualTo(2),
    );
  });

  test('nested Golden progress maps monotonically into the H4 55 percent window',
      () async {
    final progress = <int>[];
    final harness = _Harness();

    await harness.runner.run(
      onProgress: (snapshot) => progress.add(snapshot.percent),
      runInteraction: harness.runPassingInteraction,
    );

    expect(progress, contains(35));
    expect(progress.last, 100);
    for (var index = 1; index < progress.length; index += 1) {
      expect(progress[index], greaterThanOrEqualTo(progress[index - 1]));
    }
  });

  test('H9 detects same-run durable-state mutation', () async {
    final harness = _Harness(
      afterPreservation: _preservation(
        versionCode: 2023,
        knowledgeStates: const <String, String>{'doc': 'changed'},
      ),
    );

    final result = await harness.runner.run(
      runInteraction: harness.runPassingInteraction,
    );

    expect(_gate(result, 'H9_DATA_PRESERVATION').status, HandsetGateStatus.failed);
    expect(
      _gate(result, 'H9_DATA_PRESERVATION').detail,
      contains('DOCUMENT_CHANGED'),
    );
    expect(result.verdict, AcceptanceVerdict.fail);
  });

  test('stale checkpoint recovery cleans fixtures once and blocks unfinished gates',
      () async {
    final stale = _staleSnapshot();
    var cleanups = 0;
    final persistence = _MemoryPersistence(last: stale, baseline: _baseline());
    final harness = _Harness(
      persistence: persistence,
      knownFixtureCleanup: () async {
        cleanups += 1;
      },
    );

    final first = await harness.runner.recoverInterruptedCheckpoint();
    final second = await harness.runner.recoverInterruptedCheckpoint();

    expect(cleanups, 1);
    expect(second, same(first));
    expect(first!.phase, HandsetRunPhase.completed);
    expect(_gate(first, 'H1_TARGET_DEVICE').status, HandsetGateStatus.passed);
    expect(_gate(first, 'H4_PHONE_FUNCTION_LOOP').status, HandsetGateStatus.blocked);
    expect(_gate(first, 'H4_PHONE_FUNCTION_LOOP').detail, 'PROCESS_INTERRUPTED');
  });

  test('recovery cleanup failure prevents a new run and forces FAIL', () async {
    final persistence = _MemoryPersistence(
      last: _staleSnapshot(),
      baseline: _baseline(),
    );
    final harness = _Harness(
      persistence: persistence,
      knownFixtureCleanup: () async => throw StateError('cleanup token=secret'),
    );

    final recovered = await harness.runner.recoverInterruptedCheckpoint();
    final attempted = await harness.runner.run(
      runInteraction: harness.runPassingInteraction,
    );

    expect(recovered!.verdict, AcceptanceVerdict.fail);
    expect(recovered.cleanupError, isNotNull);
    expect(recovered.cleanupError, isNot(contains('secret')));
    expect(attempted.runId, recovered.runId);
    expect(harness.diagnostics.identityReads, 0);
  });

  test('every run allocates a fresh ID instead of selective rerun state', () async {
    final ids = <String>['run-a', 'run-b'];
    final harness = _Harness(runIdFactory: () => ids.removeAt(0));

    final first = await harness.runner.run(
      runInteraction: harness.runPassingInteraction,
    );
    final second = await harness.runner.run(
      runInteraction: harness.runPassingInteraction,
    );

    expect(first.runId, 'run-a');
    expect(second.runId, 'run-b');
    expect(second.runId, isNot(first.runId));
  });
}

final class _Harness {
  _Harness({
    _FakeDiagnostics? diagnostics,
    DeviceIdentitySnapshot? identity,
    bool hasBaseline = true,
    bool modelReady = true,
    this.frameTiming = _passingFrameTiming,
    ResourceAcceptanceSummary? resourceSummary,
    PreservationSnapshot? afterPreservation,
    PreservationCapture? preservationCapture,
    _MemoryPersistence? persistence,
    _FakeResourceSampler? resourceSampler,
    GoldenAcceptanceRun? goldenRun,
    GoldenAcceptanceInterrupt? goldenInterrupt,
    KnownFixtureCleanup? knownFixtureCleanup,
    DateTime Function()? clock,
    String Function()? runIdFactory,
    List<String>? events,
  })  : events = events ?? <String>[],
        diagnostics =
            diagnostics ??
                _FakeDiagnostics(
                  identity: identity ?? _identity(),
                  events: events,
                ),
        persistence = persistence ??
            _MemoryPersistence(
              baseline: hasBaseline ? _baseline() : null,
              events: events,
            ),
        resources = resourceSampler ??
            _FakeResourceSampler(
              resourceSummary ?? _passingResourceSummary(),
              events: events,
            ) {
    final before = _preservation(
      versionCode: this.diagnostics.identity.versionCode ?? 2023,
    );
    final after = afterPreservation ?? before;
    var captureCount = 0;
    final artifact = _FakeVectorArtifact('trace-task7');
    final actualGoldenRun = goldenRun ??
        ({onProgress, onTraceReady}) async {
          goldenRunCount += 1;
          onProgress?.call(_runningGoldenSnapshot());
          if (onTraceReady != null) await onTraceReady(artifact.traceId);
          return _passingGoldenReport();
        };
    runner = HandsetAcceptanceRunner(
      diagnostics: this.diagnostics,
      persistence: this.persistence,
      capturePreservation: preservationCapture ??
          (deviceIdentity) async {
            captureCount += 1;
            final isBefore = captureCount.isOdd;
            this.events.add(
              isBefore ? 'preservation:before' : 'preservation:after',
            );
            return isBefore ? before : after;
          },
      runGolden: actualGoldenRun,
      interruptGolden: goldenInterrupt ?? (reasonCode) async {},
      cleanupKnownFixtures: knownFixtureCleanup ?? () async {},
      captureVectorArtifact: (traceId) async {
        expect(traceId, artifact.traceId);
        return artifact;
      },
      verifyVectorTruth: (captured) {
        expect(captured, same(artifact));
        return VectorTruthResult(
          reasonCodes: const <String>[],
          evidence: const <String, Object?>{
            'originalDimension': 768,
            'effectiveComponentCount': 3,
          },
        );
      },
      probeModelReadiness: () async => modelReady
          ? const ModelReadinessResult.passed()
          : const ModelReadinessResult.blocked(
              'MODEL_PREREQUISITE_MISSING',
            ),
      resources: resources,
      clock: clock ?? _AdvancingClock().call,
      runIdFactory: runIdFactory,
    );
  }

  final List<String> events;
  final FrameTimingSummary frameTiming;
  final _FakeDiagnostics diagnostics;
  final _MemoryPersistence persistence;
  final _FakeResourceSampler resources;
  late final HandsetAcceptanceRunner runner;
  int goldenRunCount = 0;

  Future<VectorInteractionResult> runPassingInteraction(
    VectorAcceptanceArtifact artifact,
  ) async {
    return VectorInteractionResult(
      rotationComplete: true,
      zoomComplete: true,
      selectionComplete: true,
      viewportConfirmed: true,
      frameTiming: frameTiming,
    );
  }
}

final class _FakeDiagnostics implements DeviceDiagnosticsGateway {
  _FakeDiagnostics({
    required this.identity,
    this.throwWhenEnablingScreen = false,
    this.throwWhenDisablingScreen = false,
    List<String>? events,
  }) : events = events ?? <String>[];

  final DeviceIdentitySnapshot identity;
  final bool throwWhenEnablingScreen;
  final bool throwWhenDisablingScreen;
  final List<String> events;
  final List<bool> keepScreenOnValues = <bool>[];
  int identityReads = 0;

  @override
  Future<DeviceIdentitySnapshot> readIdentity() async {
    identityReads += 1;
    return identity;
  }

  @override
  Future<DeviceResourceSample> readResources() {
    throw UnimplementedError();
  }

  @override
  Future<void> setKeepScreenOn(bool enabled) async {
    keepScreenOnValues.add(enabled);
    events.add(enabled ? 'screen:on' : 'screen:off');
    if (enabled && throwWhenEnablingScreen) {
      throw StateError('keep screen on unavailable');
    }
    if (!enabled && throwWhenDisablingScreen) {
      throw StateError('keep screen off unavailable');
    }
  }
}

final class _FakeResourceSampler implements DeviceResourceSampling {
  _FakeResourceSampler(
    this.summary, {
    List<String>? events,
    this.stopEntered,
    this.stopBarrier,
    this.throwOnStop = false,
  })
      : events = events ?? <String>[];

  final ResourceAcceptanceSummary summary;
  final List<String> events;
  final Completer<void>? stopEntered;
  final Completer<void>? stopBarrier;
  final bool throwOnStop;
  bool _running = false;
  int startCount = 0;
  int stopCount = 0;

  @override
  bool get isRunning => _running;

  @override
  Future<void> start() async {
    expect(_running, isFalse);
    _running = true;
    startCount += 1;
    events.add('resources:start');
  }

  @override
  Future<ResourceAcceptanceSummary> stop() async {
    expect(_running, isTrue);
    stopCount += 1;
    events.add('resources:stop');
    if (stopEntered != null && !stopEntered!.isCompleted) {
      stopEntered!.complete();
    }
    await stopBarrier?.future;
    if (throwOnStop) throw StateError('resource stop unavailable');
    _running = false;
    return summary;
  }

  @override
  Future<ResourceAcceptanceSummary?> stopIfRunning() async {
    if (!_running) return null;
    return stop();
  }
}

final class _MemoryPersistence implements HandsetAcceptancePersistence {
  _MemoryPersistence({
    this.last,
    this.baseline,
    List<String>? events,
    this.finalReportEntered,
    this.finalReportBarrier,
  }) : events = events ?? <String>[];

  HandsetAcceptanceSnapshot? last;
  PreservationSnapshot? baseline;
  final List<String> events;
  final Completer<void>? finalReportEntered;
  final Completer<void>? finalReportBarrier;
  final List<HandsetAcceptanceSnapshot> checkpoints =
      <HandsetAcceptanceSnapshot>[];
  final List<PreservationSnapshot> savedBaselines = <PreservationSnapshot>[];
  final List<Uint8List> finalReports = <Uint8List>[];

  @override
  Future<HandsetAcceptanceSnapshot?> readLast() async => last;

  @override
  Future<PreservationSnapshot?> readBaseline() async => baseline;

  @override
  Future<void> saveBaseline(PreservationSnapshot snapshot) async {
    baseline = snapshot;
    savedBaselines.add(snapshot);
    events.add('baseline:save');
  }

  @override
  Future<void> saveCheckpoint(HandsetAcceptanceSnapshot snapshot) async {
    last = snapshot;
    checkpoints.add(snapshot);
  }

  @override
  Future<String> saveFinalReport(Uint8List bytes, String runId) async {
    events.add('report:save');
    if (finalReportEntered != null && !finalReportEntered!.isCompleted) {
      finalReportEntered!.complete();
    }
    await finalReportBarrier?.future;
    finalReports.add(Uint8List.fromList(bytes));
    return '/reports/$runId.json';
  }
}

final class _FakeVectorArtifact implements VectorAcceptanceArtifact {
  const _FakeVectorArtifact(this.traceId);

  @override
  final String traceId;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _AdvancingClock {
  DateTime value = DateTime.utc(2026, 9, 1);

  DateTime call() {
    final current = value;
    value = value.add(const Duration(milliseconds: 100));
    return current;
  }
}

DeviceIdentitySnapshot _identity({
  int versionCode = 2023,
  String manufacturer = 'Samsung',
  String model = 'SM-S9280',
  String signerSha256 = PocketGalleryBuildIdentity.canonicalSignerSha256,
}) {
  return DeviceIdentitySnapshot.fromMap(
    <String, Object?>{
      'manufacturer': manufacturer,
      'model': model,
      'sdkInt': 35,
      'refreshRateHz': 120.0,
      'packageName': PocketGalleryBuildIdentity.packageName,
      'versionName': versionCode == 2022 ? '0.5.0' : '0.5.1',
      'versionCode': versionCode,
      'signerSha256': signerSha256,
      'apkSha256': _apkDigest,
      'unavailableReasons': const <String>[],
    },
    sourceCommit: _sourceCommit,
  );
}

PreservationSnapshot _baseline() => _preservation(versionCode: 2022);

PreservationSnapshot _preservation({
  required int versionCode,
  Map<String, String> knowledgeStates = const <String, String>{
    'doc': 'same',
  },
}) {
  return PreservationSnapshot(
    versionCode: versionCode,
    packageName: PocketGalleryBuildIdentity.packageName,
    signerSha256: PocketGalleryBuildIdentity.canonicalSignerSha256,
    hasActiveModel: true,
    hasActiveEmbedder: true,
    oauthAccessPresent: true,
    oauthRefreshPresent: true,
    oauthExpiry: HfTokenExpiryState.valid,
    knowledgeStates: knowledgeStates,
    chatStates: const <String, String>{'chat': 'same'},
    chatMessageCounts: const <String, int>{'chat': 2},
    vectorStates: const <String, String>{'vector': 'same'},
    lineageStates: const <String, String>{'trace': 'same'},
  );
}

ResourceAcceptanceSummary _passingResourceSummary() {
  return ResourceAcceptanceSummary.evaluate(<DeviceResourceSample>[
    _resourceSample(pssKiB: 100000),
    _resourceSample(pssKiB: 100100),
  ]);
}

DeviceResourceSample _resourceSample({required int pssKiB}) {
  return DeviceResourceSample.fromMap(<String, Object?>{
    'capturedAtEpochMs': DateTime.utc(2026, 9, 1).millisecondsSinceEpoch,
    'processPssKiB': pssKiB,
    'availableMemoryBytes': 2 * 1024 * 1024 * 1024,
    'totalMemoryBytes': 12 * 1024 * 1024 * 1024,
    'lowMemory': false,
    'lowMemoryThresholdBytes': 256 * 1024 * 1024,
    'thermalStatus': 1,
    'batteryTemperatureC': 32.0,
    'unavailableReasons': const <String>[],
  });
}

GoldenTestReport _passingGoldenReport() {
  final snapshot = GoldenTestSnapshot(
    runId: 'golden-task7',
    phase: GoldenRunPhase.completed,
    startedAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 1, 0, 0, 20),
    gates: List<GoldenGateSnapshot>.generate(
      10,
      (index) => GoldenGateSnapshot(
        name: 'F${index + 1}',
        label: 'F${index + 1}',
        timeout: const Duration(seconds: 30),
        status: GoldenGateStatus.passed,
        detail: 'passed',
        startedAt: DateTime.utc(2026, 9, 1),
        finishedAt: DateTime.utc(2026, 9, 1, 0, 0, 1),
      ),
    ),
  );
  return GoldenTestReport.fromSnapshot(snapshot, traceId: 'trace-task7');
}

GoldenTestSnapshot _runningGoldenSnapshot() {
  return GoldenTestSnapshot(
    runId: 'golden-task7',
    phase: GoldenRunPhase.running,
    startedAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 1, 0, 0, 8),
    gates: List<GoldenGateSnapshot>.generate(
      10,
      (index) => GoldenGateSnapshot(
        name: 'F${index + 1}',
        label: 'F${index + 1}',
        timeout: const Duration(seconds: 30),
        status: index < 5
            ? GoldenGateStatus.passed
            : index == 5
                ? GoldenGateStatus.running
                : GoldenGateStatus.pending,
        detail: '',
      ),
    ),
  );
}

HandsetAcceptanceSnapshot _staleSnapshot() {
  final now = DateTime.utc(2026, 9, 1);
  return HandsetAcceptanceSnapshot(
    runId: 'stale-run',
    phase: HandsetRunPhase.runningAutomated,
    startedAt: now,
    updatedAt: now,
    gates: <HandsetGateSnapshot>[
      HandsetGateSnapshot(
        name: 'H1_TARGET_DEVICE',
        label: 'target',
        status: HandsetGateStatus.passed,
        detail: 'passed',
        evidence: const <AcceptanceEvidence>[],
        startedAt: now,
        finishedAt: now,
      ),
      HandsetGateSnapshot(
        name: 'H4_PHONE_FUNCTION_LOOP',
        label: 'golden',
        status: HandsetGateStatus.running,
        detail: '',
        evidence: const <AcceptanceEvidence>[],
        startedAt: now,
      ),
      HandsetGateSnapshot(
        name: 'H10_REPORT_INTEGRITY',
        label: 'report',
        status: HandsetGateStatus.pending,
        detail: '',
        evidence: const <AcceptanceEvidence>[],
      ),
    ],
  );
}

HandsetGateSnapshot _gate(HandsetAcceptanceSnapshot snapshot, String name) {
  return snapshot.gates.singleWhere((gate) => gate.name == name);
}

const FrameTimingSummary _passingFrameTiming = FrameTimingSummary(
  available: true,
  sampleDuration: Duration(seconds: 15),
  rawFrameCount: 190,
  warmUpFrameCount: 10,
  eligibleFrameCount: 180,
  p95: Duration(milliseconds: 16),
  framesOver16Point7Count: 0,
  framesOver16Point7Ratio: 0,
  framesOver32Count: 0,
  framesOver32Ratio: 0,
);

const FrameTimingSummary _failingFrameTiming = FrameTimingSummary(
  available: true,
  sampleDuration: Duration(seconds: 15),
  rawFrameCount: 190,
  warmUpFrameCount: 10,
  eligibleFrameCount: 180,
  p95: Duration(milliseconds: 20),
  framesOver16Point7Count: 40,
  framesOver16Point7Ratio: 0.22,
  framesOver32Count: 0,
  framesOver32Ratio: 0,
);

const String _sourceCommit = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _apkDigest =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const String _otherDigest =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
