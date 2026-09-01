# PocketGallery R5.0 S24U Consolidated Handset Acceptance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Build one in-app S24U acceptance flow that combines the existing F1-F10 real-model loop, truthful three-dimensional interaction evidence, Android performance and thermal measurements, cross-version preservation checks, redacted reporting, and same-commit merge-readiness adjudication.

**Architecture:** Keep GoldenTestRunner as the nested functional authority and add a separate H1-H10 HandsetAcceptanceRunner around it. Use an injectable Dart diagnostics interface backed by a first-party Kotlin MethodChannel host, capture the F6 ACTIVE trace before temporary fixture cleanup, and keep device evidence separate from the final CI-plus-device adjudicator.

**Tech Stack:** Flutter and Dart 3.12, Material 3, flutter_gemma, sqlite3, crypto, file_picker 12, Android Kotlin platform APIs, GitHub Actions, shell artifact verification.

**Spec:** docs/superpowers/specs/2026-09-01-pocketgallery-r50-s24u-handset-acceptance-design.md

## Global Constraints

- Eligible target hardware is Samsung Galaxy S24 Ultra with a model matching case-insensitive pattern ^SM-S928[A-Z0-9]*$, including SM-S9280.
- Package remains com.qujindai.pocketgallery_phone_pilot.r3.
- Canonical signer SHA-256 remains 81af4a5ef94c236774f0e193b2a4b248805b36c14cc36e2a56df8e451a712541.
- Source candidate version is 0.5.0+23; split arm64 versionCode is 2023; baseline helper build 22 has split arm64 versionCode 2022.
- Do not add Shizuku, root, Termux, ADB, remote telemetry, a third-party 3D engine, or a new dangerous Android permission.
- Never clear or rename existing model, OAuth, knowledge, chat, vector-observation, or lineage state.
- Never export raw OAuth values, authorization headers, raw vectors, full private document content, or unreviewed stack traces.
- CI cannot manufacture DEVICE_ACCEPTANCE = PASS.
- The app may output MERGE_CANDIDATE; only the final adjudicator may output MERGE_READY.
- All production changes follow red-green-refactor and retain the existing R4.8 and R4.9 behavior.

---

## File and responsibility map

| File | Responsibility |
| --- | --- |
| pilot/flutter_phone_loop/lib/acceptance/handset_acceptance_models.dart | H1-H10 state, evidence, progress, and verdict rules |
| pilot/flutter_phone_loop/lib/acceptance/pocketgallery_build_identity.dart | Pinned package/signer constants and compiled source commit |
| pilot/flutter_phone_loop/lib/acceptance/device_diagnostics.dart | Injectable identity/resource gateway and MethodChannel decoder |
| pilot/flutter_phone_loop/android_host/MainActivity.kt | Flutter channel registration only |
| pilot/flutter_phone_loop/android_host/DeviceDiagnosticsHost.kt | Android package, signer, APK hash, memory, thermal, battery, display, and keep-screen-on APIs |
| pilot/flutter_phone_loop/lib/acceptance/preservation_probe.dart | Private durable-state snapshots and subset comparison |
| pilot/flutter_phone_loop/lib/acceptance/handset_acceptance_store.dart | Atomic checkpoint/baseline/final report persistence |
| pilot/flutter_phone_loop/lib/acceptance/handset_report_exporter.dart | Allow-listed redacted JSON and Android save dialog |
| pilot/flutter_phone_loop/lib/acceptance/vector_acceptance.dart | Same-run F6 trace capture and H5 truth verification |
| pilot/flutter_phone_loop/lib/acceptance/frame_timing_sampler.dart | Flutter frame collection and deterministic percentile calculation |
| pilot/flutter_phone_loop/lib/acceptance/vector_interaction_evidence.dart | Rotation, zoom, selection, viewport, and threshold accumulation |
| pilot/flutter_phone_loop/lib/acceptance/device_resource_sampler.dart | One-second memory/thermal samples and H8 evaluation |
| pilot/flutter_phone_loop/lib/acceptance/handset_acceptance_runner.dart | Outer H1-H10 orchestration, cancellation, cleanup, and checkpointing |
| pilot/flutter_phone_loop/lib/acceptance/handset_acceptance_composition.dart | Production dependency wiring |
| pilot/flutter_phone_loop/lib/ui/handset_acceptance_page.dart | Full-screen run, live progress, terminal verdict, and export |
| pilot/flutter_phone_loop/lib/ui/handset_vector_interaction_page.dart | Guided physical 3D interaction and 15-second frame window |
| pilot/flutter_phone_loop/lib/ui/handset_acceptance_widgets.dart | Entry card, progress rows, evidence rows, and terminal summary |
| pilot/flutter_phone_loop/lib/acceptance/release_readiness_adjudicator.dart | Pure CI-plus-device evidence correlation |
| pilot/flutter_phone_loop/tool/adjudicate_handset_acceptance.dart | Command-line wrapper that writes PG_MERGE_READINESS.json |

Existing files are modified only where they own the relevant integration:

- lib/services/golden_test_runner.dart exposes the F6 trace before fixture cleanup.
- lib/services/hf_oauth_device_service.dart adds a non-mutating credential-state probe.
- lib/observability/vector_observation_store.dart and lib/lineage/lineage_store.dart add identity-only reads.
- lib/ui/microscope/vector_space_3d.dart emits optional production gesture events.
- lib/ui/microscope/vector_space_page.dart forwards optional interaction evidence.
- lib/ui/model_settings_page.dart adds the prominent entry.
- lib/ui/main_shell.dart passes the existing chat store.
- scripts/bootstrap_android.sh installs the committed Kotlin host.
- pubspec.yaml and both workflows advance the R5.0 artifact contract.

---

### Task 1: Acceptance state, evidence, progress, and build identity

**Files:**

- Create: pilot/flutter_phone_loop/lib/acceptance/handset_acceptance_models.dart
- Create: pilot/flutter_phone_loop/lib/acceptance/pocketgallery_build_identity.dart
- Create: pilot/flutter_phone_loop/test/r50_acceptance_state_test.dart

**Interfaces:**

- Produces HandsetRunPhase, HandsetGateStatus, AcceptanceVerdict, EvidenceMethod, AcceptanceEvidence, HandsetGateSnapshot, and HandsetAcceptanceSnapshot.
- Produces PocketGalleryBuildIdentity.packageName, canonicalSignerSha256, sourceCommit, and isValidSourceCommit(String).
- HandsetAcceptanceSnapshot embeds GoldenTestSnapshot? nestedGolden, stores mergeCandidate, and uses schemaVersion 1.

- [ ] **Step 1: Write failing verdict, progress, JSON, and source-commit tests**

~~~dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketgallery_phone_pilot/acceptance/handset_acceptance_models.dart';
import 'package:pocketgallery_phone_pilot/acceptance/pocketgallery_build_identity.dart';
import 'package:pocketgallery_phone_pilot/services/golden_test_state.dart';

void main() {
  test('FAIL outranks BLOCKED and PASS', () {
    final snapshot = _snapshot(
      gates: <HandsetGateSnapshot>[
        _gate('H1_TARGET_DEVICE', HandsetGateStatus.blocked),
        _gate('H7_RENDER_PERFORMANCE', HandsetGateStatus.failed),
      ],
    );
    expect(snapshot.verdict, AcceptanceVerdict.fail);
  });

  test('H4 nested progress occupies its fixed 55 percent window', () {
    final snapshot = _snapshot(
      phase: HandsetRunPhase.runningAutomated,
      gates: <HandsetGateSnapshot>[
        _gate('H1_TARGET_DEVICE', HandsetGateStatus.passed),
        _gate('H2_BUILD_IDENTITY', HandsetGateStatus.passed),
        _gate('H3_UPGRADE_BASELINE', HandsetGateStatus.passed),
        _gate('H4_PHONE_FUNCTION_LOOP', HandsetGateStatus.running),
      ],
      nestedGolden: _goldenAtFiftyPercent(),
    );
    expect(snapshot.percent, 38);
  });

  test('schema version 1 round trips every gate and evidence item', () {
    final source = _snapshot(
      gates: <HandsetGateSnapshot>[
        _gate(
          'H1_TARGET_DEVICE',
          HandsetGateStatus.passed,
          evidence: const <AcceptanceEvidence>[
            AcceptanceEvidence(
              code: 'TARGET_MODEL',
              method: EvidenceMethod.measured,
              source: 'Build.MODEL',
              actual: 'SM-S9280',
              threshold: '^SM-S928[A-Z0-9]*\$',
              unit: null,
              available: true,
              detail: 'target matched',
            ),
          ],
        ),
      ],
    );
    expect(
      HandsetAcceptanceSnapshot.fromJson(source.toJson()).toJson(),
      source.toJson(),
    );
  });

  test('only a forty-character hex commit is release evidence', () {
    final commit = List<String>.filled(40, 'a').join();
    expect(PocketGalleryBuildIdentity.isValidSourceCommit(commit), isTrue);
    expect(PocketGalleryBuildIdentity.isValidSourceCommit('local'), isFalse);
  });
}

final _startedAt = DateTime.utc(2026, 9, 1);

HandsetGateSnapshot _gate(
  String name,
  HandsetGateStatus status, {
  List<AcceptanceEvidence> evidence = const <AcceptanceEvidence>[],
}) =>
    HandsetGateSnapshot(
      name: name,
      label: name,
      status: status,
      detail: '',
      evidence: evidence,
      startedAt: _startedAt,
      finishedAt: status == HandsetGateStatus.running ? null : _startedAt,
    );

HandsetAcceptanceSnapshot _snapshot({
  HandsetRunPhase phase = HandsetRunPhase.completed,
  required List<HandsetGateSnapshot> gates,
  GoldenTestSnapshot? nestedGolden,
}) =>
    HandsetAcceptanceSnapshot(
      runId: 'r50-test',
      phase: phase,
      startedAt: _startedAt,
      updatedAt: _startedAt,
      gates: gates,
      nestedGolden: nestedGolden,
    );

GoldenTestSnapshot _goldenAtFiftyPercent() => GoldenTestSnapshot(
      runId: 'golden-50',
      phase: GoldenRunPhase.running,
      startedAt: _startedAt,
      updatedAt: _startedAt,
      gates: List<GoldenGateSnapshot>.generate(
        9,
        (index) => GoldenGateSnapshot(
          name: 'F${index + 1}',
          label: 'F${index + 1}',
          timeout: const Duration(seconds: 30),
          status: index < 5
              ? GoldenGateStatus.passed
              : GoldenGateStatus.pending,
          detail: '',
        ),
      ),
    );
~~~

- [ ] **Step 2: Run the test and confirm RED**

Run:

~~~bash
cd pilot/flutter_phone_loop
flutter test test/r50_acceptance_state_test.dart
~~~

Expected: compilation fails because the acceptance model files do not exist.

- [ ] **Step 3: Implement the exact state and verdict contract**

Use these enum values and gate weights:

~~~dart
enum HandsetRunPhase {
  preparing,
  runningAutomated,
  awaitingInteraction,
  runningPostChecks,
  cleaningUp,
  completed,
}

enum HandsetGateStatus { pending, running, passed, failed, timedOut, blocked }
enum AcceptanceVerdict { pass, fail, blocked }
enum EvidenceMethod { measured, observed, derived, userAction }

const handsetGateWeights = <String, int>{
  'H1_TARGET_DEVICE': 3,
  'H2_BUILD_IDENTITY': 3,
  'H3_UPGRADE_BASELINE': 4,
  'H4_PHONE_FUNCTION_LOOP': 55,
  'H5_VECTOR_3D_TRUTH': 5,
  'H6_VECTOR_INTERACTION': 15,
  'H7_RENDER_PERFORMANCE': 5,
  'H8_MEMORY_THERMAL': 5,
  'H9_DATA_PRESERVATION': 3,
  'H10_REPORT_INTEGRITY': 2,
};
~~~

AcceptanceEvidence fields are code, method, source, actual, threshold, unit,
available, and detail. HandsetGateSnapshot fields are name, label, status,
detail, evidence, startedAt, and finishedAt. HandsetAcceptanceSnapshot fields
are runId, phase, startedAt, updatedAt, gates, nestedGolden, cleanupError,
reportPath, baselineVersionCode, and mergeCandidate. actual and threshold are
JSON scalar values only; unit is nullable String. mergeCandidate defaults to
false and is serialized explicitly.

Implement verdict exactly as follows:

~~~dart
AcceptanceVerdict get verdict {
  final hasFailure = cleanupError != null ||
      gates.any((gate) =>
          gate.status == HandsetGateStatus.failed ||
          gate.status == HandsetGateStatus.timedOut);
  if (hasFailure) return AcceptanceVerdict.fail;
  final incomplete = phase != HandsetRunPhase.completed ||
      gates.any((gate) => gate.status != HandsetGateStatus.passed);
  return incomplete ? AcceptanceVerdict.blocked : AcceptanceVerdict.pass;
}
~~~

Map nested Golden percent only while H4 is running: completed high-level gates
contribute their full immutable weight, running H4 contributes
55 * nestedGolden.percent / 100, and any other running gate contributes zero.
Round only the final sum with round(). Clamp progress to 99 until H10 final
persistence completes. Serialize enum names, ISO-8601 UTC timestamps, all
evidence fields, nestedGolden.toJson(), and schemaVersion 1. Reject any other
schema.

PocketGalleryBuildIdentity uses:

~~~dart
abstract final class PocketGalleryBuildIdentity {
  static const packageName =
      'com.qujindai.pocketgallery_phone_pilot.r3';
  static const canonicalSignerSha256 =
      '81af4a5ef94c236774f0e193b2a4b248805b36c14cc36e2a56df8e451a712541';
  static const sourceCommit =
      String.fromEnvironment('POCKETGALLERY_SOURCE_COMMIT');

  static bool isValidSourceCommit(String value) =>
      RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(value);
}
~~~

- [ ] **Step 4: Format and run the focused test GREEN**

~~~bash
dart format lib/acceptance/handset_acceptance_models.dart lib/acceptance/pocketgallery_build_identity.dart test/r50_acceptance_state_test.dart
flutter test test/r50_acceptance_state_test.dart
~~~

Expected: all Task 1 tests pass.

- [ ] **Step 5: Commit Task 1**

~~~bash
git add pilot/flutter_phone_loop/lib/acceptance/handset_acceptance_models.dart pilot/flutter_phone_loop/lib/acceptance/pocketgallery_build_identity.dart pilot/flutter_phone_loop/test/r50_acceptance_state_test.dart
git commit -m "feat(r50): define handset acceptance state contract"
~~~

---

### Task 2: Android device diagnostics bridge

**Files:**

- Create: pilot/flutter_phone_loop/lib/acceptance/device_diagnostics.dart
- Create: pilot/flutter_phone_loop/android_host/MainActivity.kt
- Create: pilot/flutter_phone_loop/android_host/DeviceDiagnosticsHost.kt
- Modify: pilot/flutter_phone_loop/scripts/bootstrap_android.sh
- Create: pilot/flutter_phone_loop/test/r50_device_diagnostics_test.dart
- Create: pilot/flutter_phone_loop/test/r50_android_host_contract_test.dart

**Interfaces:**

- Produces DeviceIdentitySnapshot and DeviceResourceSample.
- Produces DeviceDiagnosticsGateway.readIdentity(), readResources(), and setKeepScreenOn(bool).
- MethodChannel name is pocketgallery/device_diagnostics.
- Native methods are identity, resources, and keepScreenOn.

- [ ] **Step 1: Write failing Dart decoder and native-source contract tests**

~~~dart
testWidgets('method channel decodes S24U identity without zero fallbacks',
    (tester) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('pocketgallery/device_diagnostics'),
    (call) async => switch (call.method) {
      'identity' => <String, Object?>{
          'manufacturer': 'samsung',
          'model': 'SM-S9280',
          'sdkInt': 36,
          'refreshRateHz': 120.0,
          'packageName': 'com.qujindai.pocketgallery_phone_pilot.r3',
          'versionName': '0.5.0',
          'versionCode': 2023,
          'signerSha256': PocketGalleryBuildIdentity.canonicalSignerSha256,
          'apkSha256': List<String>.filled(64, 'b').join(),
        },
      'resources' => <String, Object?>{
          'capturedAtEpochMs': 1,
          'processPssKiB': 1024,
          'availableMemoryBytes': 8000000000,
          'totalMemoryBytes': 12000000000,
          'lowMemory': false,
          'lowMemoryThresholdBytes': 500000000,
          'thermalStatus': 1,
          'batteryTemperatureC': 35.2,
        },
      'keepScreenOn' => null,
      _ => throw MissingPluginException(),
    },
  );
  final identity = await const MethodChannelDeviceDiagnostics().readIdentity();
  expect(identity.isTargetS24Ultra, isTrue);
  expect(identity.apkSha256, hasLength(64));
});
~~~

The source test reads both Kotlin files and bootstrap_android.sh. Assert the
channel/method strings, PackageManager.GET_SIGNING_CERTIFICATES,
applicationInfo.sourceDir, MessageDigest SHA-256, Debug.getPss,
ActivityManager.MemoryInfo, PowerManager.currentThermalStatus,
ACTION_BATTERY_CHANGED, FLAG_KEEP_SCREEN_ON, ExecutorService, host.close(),
onDestroy, and the two copy commands are present. Assert no
ACCESS_FINE_LOCATION, QUERY_ALL_PACKAGES, root, or Shizuku text is introduced.

- [ ] **Step 2: Run both tests and confirm RED**

~~~bash
cd pilot/flutter_phone_loop
flutter test test/r50_device_diagnostics_test.dart test/r50_android_host_contract_test.dart
~~~

Expected: missing device_diagnostics.dart and android_host files.

- [ ] **Step 3: Implement the Dart contract**

~~~dart
abstract interface class DeviceDiagnosticsGateway {
  Future<DeviceIdentitySnapshot> readIdentity();
  Future<DeviceResourceSample> readResources();
  Future<void> setKeepScreenOn(bool enabled);
}

class MethodChannelDeviceDiagnostics implements DeviceDiagnosticsGateway {
  const MethodChannelDeviceDiagnostics();
  static const channel = MethodChannel('pocketgallery/device_diagnostics');

  @override
  Future<DeviceIdentitySnapshot> readIdentity() async {
    final value = await channel.invokeMapMethod<String, Object?>('identity');
    return DeviceIdentitySnapshot.fromMap(value ?? const <String, Object?>{});
  }

  @override
  Future<DeviceResourceSample> readResources() async {
    final value = await channel.invokeMapMethod<String, Object?>('resources');
    return DeviceResourceSample.fromMap(value ?? const <String, Object?>{});
  }

  @override
  Future<void> setKeepScreenOn(bool enabled) =>
      channel.invokeMethod<void>('keepScreenOn', <String, Object?>{
        'enabled': enabled,
      });
}
~~~

DeviceIdentitySnapshot includes sourceCommit from PocketGalleryBuildIdentity
in Dart rather than trusting native input. isTargetS24Ultra requires
manufacturer lower-case samsung and the agreed model regex. Missing native
values remain null and add stable reason codes to unavailableReasons.

- [ ] **Step 4: Implement the Kotlin host and bootstrap copy**

MainActivity.kt owns one host, registers the channel, and closes the host with
the Activity lifecycle. APK hashing is asynchronous so the MethodChannel never
blocks Android's UI thread:

~~~kotlin
class MainActivity : FlutterActivity() {
    private lateinit var host: DeviceDiagnosticsHost

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        host = DeviceDiagnosticsHost(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "pocketgallery/device_diagnostics"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "identity" -> host.identity { outcome ->
                    runOnUiThread {
                        outcome.fold(result::success) { error ->
                            result.error(
                                "IDENTITY_READ_FAILED",
                                error.message,
                                null
                            )
                        }
                    }
                }
                "resources" -> result.success(host.resources())
                "keepScreenOn" -> {
                    host.keepScreenOn(call.argument<Boolean>("enabled") == true)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        if (::host.isInitialized) host.close()
        super.onDestroy()
    }
}
~~~

DeviceDiagnosticsHost.kt computes signer and APK digests as lower-case hex,
using a private single-thread ExecutorService for identity() and shutting it
down in close(). It reads Activity.display.refreshRate, returns null plus an
unavailable reason when an API fails, and executes window flag changes on the
UI thread. If Android reports multiple current signers, do not choose an
arbitrary certificate: return signerSha256 null with SIGNER_AMBIGUOUS.

After flutter create, bootstrap_android.sh copies:

~~~bash
HOST_DIR="$ROOT/android_host"
KOTLIN_DIR="$ROOT/android/app/src/main/kotlin/com/qujindai/pocketgallery_phone_pilot"
mkdir -p "$KOTLIN_DIR"
cp "$HOST_DIR/MainActivity.kt" "$KOTLIN_DIR/MainActivity.kt"
cp "$HOST_DIR/DeviceDiagnosticsHost.kt" "$KOTLIN_DIR/DeviceDiagnosticsHost.kt"
~~~

- [ ] **Step 5: Run focused tests GREEN**

~~~bash
dart format lib/acceptance/device_diagnostics.dart test/r50_device_diagnostics_test.dart test/r50_android_host_contract_test.dart
flutter test test/r50_device_diagnostics_test.dart test/r50_android_host_contract_test.dart
~~~

Expected: both tests pass.

- [ ] **Step 6: Bootstrap a fresh Android scaffold and compile the host**

~~~bash
bash scripts/bootstrap_android.sh
flutter build apk --debug --target-platform android-arm64 --split-per-abi --dart-define=POCKETGALLERY_SOURCE_COMMIT=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
~~~

Expected: BOOTSTRAP_PASS and app-arm64-v8a-debug.apk exists. No new permission
appears in android/app/src/main/AndroidManifest.xml.

- [ ] **Step 7: Commit Task 2**

~~~bash
git add pilot/flutter_phone_loop/lib/acceptance/device_diagnostics.dart pilot/flutter_phone_loop/android_host pilot/flutter_phone_loop/scripts/bootstrap_android.sh pilot/flutter_phone_loop/test/r50_device_diagnostics_test.dart pilot/flutter_phone_loop/test/r50_android_host_contract_test.dart
git commit -m "feat(r50): add first-party Android device diagnostics"
~~~

---

### Task 3: Non-mutating OAuth and durable-state preservation

**Files:**

- Modify: pilot/flutter_phone_loop/lib/services/hf_oauth_device_service.dart
- Modify: pilot/flutter_phone_loop/lib/observability/vector_observation_store.dart
- Modify: pilot/flutter_phone_loop/lib/lineage/lineage_store.dart
- Create: pilot/flutter_phone_loop/lib/acceptance/preservation_probe.dart
- Create: pilot/flutter_phone_loop/test/r50_oauth_credential_state_test.dart
- Create: pilot/flutter_phone_loop/test/r50_preservation_probe_test.dart

**Interfaces:**

- Produces HfOAuthCredentialState and HfTokenExpiryState.
- HfOAuthDeviceService.inspectCredentialState() reads but never refreshes or clears.
- Produces VectorObservationIdentity and VectorObservationStore.listIdentities().
- Produces LineageStore.traceIds().
- Produces PreservationSnapshot, PreservationComparison, and PreservationProbe.capture(DeviceIdentitySnapshot).

- [ ] **Step 1: Write the failing OAuth non-mutation test**

Use a fake FlutterSecureStorage preloaded with access, refresh, and expired
metadata. Call inspectCredentialState(), assert accessPresent and
refreshPresent are true and expiry is expired, then assert every stored value
is byte-for-byte unchanged and the fake HTTP client received zero requests.

~~~dart
final before = Map<String, String>.from(storage.values);
final state = await service.inspectCredentialState();
expect(state.accessPresent, isTrue);
expect(state.refreshPresent, isTrue);
expect(state.expiry, HfTokenExpiryState.expired);
expect(storage.values, before);
expect(client.requests, isEmpty);
~~~

- [ ] **Step 2: Write failing in-memory preservation tests**

Seed one knowledge document, one chat session with two messages, one vector
observation, and one lineage trace in in-memory SQLite stores. Capture before
and after snapshots.

Assert:

1. adding a lineage trace is allowed;
2. removing the original document fails with DOCUMENT_REMOVED;
3. lowering a chat message count fails with CHAT_HISTORY_REDUCED;
4. reportSummary contains counts and aggregate digests but no session ID,
   message text, token value, or vector values;
5. a previous versionCode 2022 snapshot is eligible for candidate 2023;
6. same-version, different-package, or different-signer baselines are invalid.

- [ ] **Step 3: Run both test files and confirm RED**

~~~bash
cd pilot/flutter_phone_loop
flutter test test/r50_oauth_credential_state_test.dart test/r50_preservation_probe_test.dart
~~~

Expected: the new state and probe APIs are undefined.

- [ ] **Step 4: Add identity-only store reads and OAuth state**

~~~dart
enum HfTokenExpiryState { missing, valid, expired, malformed }

class HfOAuthCredentialState {
  const HfOAuthCredentialState({
    required this.accessPresent,
    required this.refreshPresent,
    required this.expiry,
  });
  final bool accessPresent;
  final bool refreshPresent;
  final HfTokenExpiryState expiry;
}
~~~

inspectCredentialState reads the three existing secure-storage keys directly,
classifies the expiry against the injected/current clock, and returns booleans
only. It must not call getValidAccessToken().

VectorObservationIdentity contains chunkId, documentId, dimension, norm, and
modelIdentity but no vector. listIdentities selects only those columns.
LineageStore.traceIds selects every trace_id ordered ascending.

- [ ] **Step 5: Implement canonical private snapshots and comparison**

PreservationProbe constructor accepts KnowledgeEngine, ChatSessionStore,
HfOAuthDeviceService, hasActiveModel, and hasActiveEmbedder. Canonicalize each
record into sorted JSON and hash it with SHA-256:

~~~dart
String digestObject(Object value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();
~~~

PreservationSnapshot schema 1 stores version/package/signer, model flags,
OAuth flags, and maps from hashed object identity to hashed state. The private
snapshot may store those digests; reportSummary exposes only object counts and
one digest of each sorted map.

PreservationComparison returns passed plus stable reason codes. Current state
must contain every baseline key with the same state digest. New lineage keys
are allowed. Existing knowledge, chat, and vector keys may not disappear or
change.

- [ ] **Step 6: Format and run focused tests GREEN**

~~~bash
dart format lib/services/hf_oauth_device_service.dart lib/observability/vector_observation_store.dart lib/lineage/lineage_store.dart lib/acceptance/preservation_probe.dart test/r50_oauth_credential_state_test.dart test/r50_preservation_probe_test.dart
flutter test test/r50_oauth_credential_state_test.dart test/r50_preservation_probe_test.dart
~~~

Expected: both files pass and the OAuth fake records no HTTP request.

- [ ] **Step 7: Commit Task 3**

~~~bash
git add pilot/flutter_phone_loop/lib/services/hf_oauth_device_service.dart pilot/flutter_phone_loop/lib/observability/vector_observation_store.dart pilot/flutter_phone_loop/lib/lineage/lineage_store.dart pilot/flutter_phone_loop/lib/acceptance/preservation_probe.dart pilot/flutter_phone_loop/test/r50_oauth_credential_state_test.dart pilot/flutter_phone_loop/test/r50_preservation_probe_test.dart
git commit -m "feat(r50): capture non-mutating upgrade preservation state"
~~~

---

### Task 4: Atomic checkpoint, private baseline, redacted report, and export

**Files:**

- Create: pilot/flutter_phone_loop/lib/acceptance/handset_acceptance_store.dart
- Create: pilot/flutter_phone_loop/lib/acceptance/handset_report_exporter.dart
- Create: pilot/flutter_phone_loop/test/r50_handset_report_store_test.dart
- Create: pilot/flutter_phone_loop/test/r50_handset_report_redaction_test.dart

**Interfaces:**

- HandsetAcceptanceStore.saveCheckpoint(), readLast(), saveBaseline(), readBaseline(), and saveFinalReport().
- HandsetReportExporter.encodeRedacted(HandsetAcceptanceSnapshot).
- HandsetReportExporter.validateNoProhibitedKeys(Map<String, Object?>).
- HandsetReportExporter.saveWithPicker(Uint8List, String) returns Future<Uri?>.

- [ ] **Step 1: Write failing atomic-generation and backup-recovery tests**

Use an injected temporary directory. Save a preparing snapshot, a running
snapshot, and a completed snapshot. After each save, decode
PG_HANDSET_ACCEPTANCE_LAST.json and compare the run ID/status. Corrupt the
primary and retain a valid .bak; readLast() must return the backup. Repeat for
PG_HANDSET_BASELINE.json.

- [ ] **Step 2: Write failing allow-list and prohibited-key tests**

Build a terminal snapshot whose source detail contains a bearer-token-shaped
value and a private-document-shaped value. encodeRedacted must retain the safe
numeric metric, PHONE_FUNCTION_LOOP, DEVICE_ACCEPTANCE, and MERGE_CANDIDATE,
but neither sensitive value may appear in the bytes. Separately call
validateNoProhibitedKeys with each of authorization, vectorF32, documentText,
and a nested body key and assert FormatException; a safe metric-only map must
pass validation.

- [ ] **Step 3: Run both tests and confirm RED**

~~~bash
cd pilot/flutter_phone_loop
flutter test test/r50_handset_report_store_test.dart test/r50_handset_report_redaction_test.dart
~~~

Expected: missing store/exporter types.

- [ ] **Step 4: Implement validated same-directory atomic replacement**

Use the established sequence:

~~~dart
await temporary.writeAsString(encoded, flush: true);
decode(await temporary.readAsString());
if (await backup.exists()) await backup.delete();
if (await destination.exists()) await destination.rename(backup.path);
try {
  await temporary.rename(destination.path);
} catch (_) {
  if (!await destination.exists() && await backup.exists()) {
    await backup.rename(destination.path);
  }
  rethrow;
}
if (await backup.exists()) await backup.delete();
~~~

File names are exactly PG_HANDSET_ACCEPTANCE_LAST.json and
PG_HANDSET_BASELINE.json. Final reports use
PG_HANDSET_ACCEPTANCE_ followed by the sanitized run ID and .json.

- [ ] **Step 5: Implement allow-listed redacted encoding and save dialog**

Construct report JSON from known fields rather than serializing arbitrary
objects. The public report contains schema
pocketgallery.r50.handset-acceptance.v1 and schemaVersion 1. Recursively reject
keys matching case-insensitive pattern:

~~~dart
final prohibited = RegExp(
  r'(authorization|credential|password|secret|token|vector|raw.*text|document.*text|chunk.*text|content|body)',
  caseSensitive: false,
);
~~~

Sanitize exception detail to one line and 400 characters. Export with:

~~~dart
return FilePicker.saveFile(
  fileName: fileName,
  bytes: bytes,
  mimeType: 'application/json',
  type: FileType.custom,
  allowedExtensions: const <String>['json'],
);
~~~

Run validateNoProhibitedKeys on the allow-listed map immediately before JSON
encoding. Keep the validator public so the redaction boundary has a direct,
pure unit test instead of a test-only serialization escape hatch.

The three release-facing fields have one deterministic mapping:

- PHONE_FUNCTION_LOOP is PASS only for a passed H4, FAIL for failed/timedOut,
  and BLOCKED otherwise;
- DEVICE_ACCEPTANCE is snapshot.verdict upper-cased;
- MERGE_CANDIDATE is the snapshot's boolean, and encoding rejects true unless
  DEVICE_ACCEPTANCE is PASS, H1/H2/H3 are passed, baselineVersionCode is lower
  than 2023, and the candidate identity evidence is present.

Do not serialize arbitrary gate detail. Export stable reason codes, numeric or
boolean metrics, approved build/device identity strings, and human-readable
text selected from an in-repository reason-code message map. reportPath and the
private preservation maps are internal-only fields.

- [ ] **Step 6: Format and run focused tests GREEN**

~~~bash
dart format lib/acceptance/handset_acceptance_store.dart lib/acceptance/handset_report_exporter.dart test/r50_handset_report_store_test.dart test/r50_handset_report_redaction_test.dart
flutter test test/r50_handset_report_store_test.dart test/r50_handset_report_redaction_test.dart
~~~

Expected: atomic recovery and redaction tests pass.

- [ ] **Step 7: Commit Task 4**

~~~bash
git add pilot/flutter_phone_loop/lib/acceptance/handset_acceptance_store.dart pilot/flutter_phone_loop/lib/acceptance/handset_report_exporter.dart pilot/flutter_phone_loop/test/r50_handset_report_store_test.dart pilot/flutter_phone_loop/test/r50_handset_report_redaction_test.dart
git commit -m "feat(r50): persist redacted handset acceptance evidence"
~~~

---

### Task 5: Capture the same-run F6 trace before cleanup and verify 3D truth

**Files:**

- Modify: pilot/flutter_phone_loop/lib/services/golden_test_runner.dart
- Create: pilot/flutter_phone_loop/lib/acceptance/vector_acceptance.dart
- Create: pilot/flutter_phone_loop/test/r50_golden_trace_handoff_test.dart
- Create: pilot/flutter_phone_loop/test/r50_vector_truth_test.dart

**Interfaces:**

- GoldenTraceReadyCallback is Future<void> Function(String traceId).
- GoldenTestRunner.run accepts onTraceReady.
- GoldenTestRunner.interrupt(String reasonCode) is cooperative and idempotent.
- GoldenTestReport exposes traceId and traceCaptureError.
- VectorAcceptanceArtifact contains traceId, TraceSnapshot, and TraceVectorSpaceSnapshot.
- VectorAcceptanceCapture.capture(KnowledgeEngine, String).
- VectorTruthVerifier.verify(VectorAcceptanceArtifact).

- [ ] **Step 1: Write failing callback and report-metadata tests**

Add source/behavior contract tests that assert runF10 awaits the callback before
the executor cleanup call; interrupt records one reason, closes an active chat
model at most once, and shares one cleanup future; and GoldenTestReport JSON
includes traceId and a sanitized traceCaptureError without changing nested
F1-F10 gate status.

~~~dart
final startedAt = DateTime.utc(2026, 9, 1);
final completedGoldenSnapshot = GoldenTestSnapshot(
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
  completedGoldenSnapshot,
  traceId: 'trace-r50',
  traceCaptureError: 'capture failed',
);
expect(report.traceId, 'trace-r50');
expect(report.toJson()['traceCaptureError'], 'capture failed');
~~~

- [ ] **Step 2: Write failing truth-verifier tests**

Create a local seedArtifact helper from the exact in-memory storage APIs used
by test/r46bc_trace_vector_space_test.dart: open lineage and lexical SQLite
databases, initialize LineageStore, put one complete ACTIVE LineageTrace, put
LineageIds.queryEmbeddingId(traceId), insert at least three ImportedDocument
chunks and their body embeddings, put one ranked ACTIVE CandidateRecord plus
EvidenceRecord, then call TraceSnapshot.load and TraceVectorSpaceService.build.
Use four-dimensional, finite, non-coplanar vectors such as [1, 0, 0, 0],
[0.8, 0.2, 0, 0], [0, 0.7, 0.3, 0], and [0, 0, 0.6, 0.4] so the valid artifact
is a genuine >3D-to-3D projection with three effective principal components.
The valid artifact must use the captured Query embedding and real body
embeddings.
Assert the verifier rejects:

- originalDimension equal to three;
- effectiveComponentCount below three or fewer than three variance ratios;
- usedCapturedQuery false;
- non-finite coordinates;
- Query embedding ID not equal to LineageIds.queryEmbeddingId(traceId);
- no non-Query point;
- candidate points lacking captured rank/evidence/drop explanation.

- [ ] **Step 3: Run both files and confirm RED**

~~~bash
cd pilot/flutter_phone_loop
flutter test test/r50_golden_trace_handoff_test.dart test/r50_vector_truth_test.dart
~~~

Expected: new callback, artifact, and verifier APIs are missing.

- [ ] **Step 4: Add pre-cleanup trace handoff without changing F1-F10 verdicts**

Store the callback in _GoldenRunContext. After runF10 obtains its GateResult,
invoke onTraceReady when lineageTraceId is non-empty:

~~~dart
Future<GateResult> runF10() async {
  final result = await _lineageGate(2);
  final id = lineageTraceId;
  if (id != null && id.isNotEmpty && onTraceReady != null) {
    try {
      await onTraceReady!(id);
    } catch (error) {
      traceCaptureError = error.toString();
    }
  }
  return result;
}
~~~

Return traceId and traceCaptureError on GoldenTestReport after executor cleanup.
A capture error does not rewrite F10; H5 evaluates it independently.

GoldenTestRunner stores only its currently active _GoldenRunContext. interrupt
sets the context's reason once, closes the active Gemma chat model to release a
native generation, and causes every later gate entry to throw a private
interruption signal before doing work. _GoldenRunContext.cleanup memoizes one
Future so timeout, interruption, and executor-final cleanup cannot race or
delete fixtures twice. GoldenTestRunner clears the active context in finally.
The outer runner maps its own interrupt reason to BLOCKED even if the nested
executor observed the model-close exception while unwinding.

- [ ] **Step 5: Implement artifact capture and H5 verification**

~~~dart
Future<VectorAcceptanceArtifact> capture(
  KnowledgeEngine engine,
  String traceId,
) async {
  final trace = await TraceSnapshot.load(engine.lineageStore, traceId);
  final space = await TraceVectorSpaceService(
    lineageStore: engine.lineageStore,
    lexicalStore: engine.lexicalStore,
  ).build(trace);
  return VectorAcceptanceArtifact(
    traceId: traceId,
    trace: trace,
    vectorSpace: space,
  );
}
~~~

The verifier returns passed plus stable reason codes and evidence. It requires
the same trace ID, complete ACTIVE trace, captured Query identity, dimension
greater than three, exactly three effective PCA components and variance ratios,
finite PCA/cosine values, at least one real Chunk, and human-readable rank plus
Evidence/drop explanation.

- [ ] **Step 6: Run focused tests and existing Golden tests GREEN**

~~~bash
dart format lib/services/golden_test_runner.dart lib/acceptance/vector_acceptance.dart test/r50_golden_trace_handoff_test.dart test/r50_vector_truth_test.dart
flutter test test/r50_golden_trace_handoff_test.dart test/r50_vector_truth_test.dart test/r48_phone_acceptance_regression_test.dart
~~~

Expected: all pass and existing F1-F10 serialization remains schema 2.

- [ ] **Step 7: Commit Task 5**

~~~bash
git add pilot/flutter_phone_loop/lib/services/golden_test_runner.dart pilot/flutter_phone_loop/lib/acceptance/vector_acceptance.dart pilot/flutter_phone_loop/test/r50_golden_trace_handoff_test.dart pilot/flutter_phone_loop/test/r50_vector_truth_test.dart
git commit -m "feat(r50): hand off the live trace before Golden cleanup"
~~~

---

### Task 6: Frame metrics and production 3D interaction evidence

**Files:**

- Create: pilot/flutter_phone_loop/lib/acceptance/frame_timing_sampler.dart
- Create: pilot/flutter_phone_loop/lib/acceptance/vector_interaction_evidence.dart
- Modify: pilot/flutter_phone_loop/lib/ui/microscope/vector_space_3d.dart
- Modify: pilot/flutter_phone_loop/lib/ui/microscope/vector_space_page.dart
- Create: pilot/flutter_phone_loop/test/r50_frame_timing_test.dart
- Create: pilot/flutter_phone_loop/test/r50_vector_interaction_evidence_test.dart

**Interfaces:**

- FrameTimingSummary has a normal immutable constructor and
  fromDurations(List<Duration>, sampleDuration:, warmUpFrames: 10).
- FrameTimingSampler.start() and stop().
- VectorInteractionType is rotation, zoom, or selection.
- VectorInteractionEvent contains type, cameraBefore, cameraAfter, and pointId.
- InteractiveVectorPlot accepts ValueChanged<VectorInteractionEvent>? onInteraction.
- TraceVectorSpaceView accepts the same optional callback.
- VectorInteractionAccumulator records the agreed thresholds.

- [ ] **Step 1: Write failing percentile and threshold tests**

~~~dart
test('summary excludes ten warm-up frames and computes nearest-rank P95', () {
  final samples = <Duration>[
    for (var index = 0; index < 10; index++) const Duration(milliseconds: 90),
    for (var index = 0; index < 179; index++) const Duration(milliseconds: 8),
    const Duration(milliseconds: 16),
  ];
  final result = FrameTimingSummary.fromDurations(
    samples,
    sampleDuration: const Duration(seconds: 15),
  );
  expect(result.eligibleFrameCount, 180);
  expect(result.p95, const Duration(milliseconds: 8));
  expect(result.framesOver32Ratio, 0);
});

test('render gate needs fifteen seconds, 180 frames and no more than one percent severe jank', () {
  const result = FrameTimingSummary(
    available: true,
    sampleDuration: const Duration(seconds: 15),
    rawFrameCount: 190,
    warmUpFrameCount: 10,
    eligibleFrameCount: 180,
    p95: const Duration(microseconds: 16600),
    framesOver16Point7Count: 0,
    framesOver16Point7Ratio: 0,
    framesOver32Count: 2,
    framesOver32Ratio: 0.01,
  );
  expect(result.passesReleaseThreshold, isTrue);
});
~~~

Write pure accumulator tests proving that yaw 0.25 **or** pitch 0.15 completes
rotation, max/min zoom ratio 1.12 completes zoom, only selection of a known
Query/Chunk point completes selection, and explicit user confirmation
completes viewport. Test values just below each boundary remain incomplete.

- [ ] **Step 2: Write failing production-widget event tests**

Extend the existing r49 interaction pattern: drag one finger, perform a
two-pointer gesture, and tap a projected point. Assert exactly one completed
rotation event, zoom event, and selection event are emitted with the real
point ID.

- [ ] **Step 3: Run focused tests and confirm RED**

~~~bash
cd pilot/flutter_phone_loop
flutter test test/r50_frame_timing_test.dart test/r50_vector_interaction_evidence_test.dart
~~~

Expected: metric/event types and callback parameters do not exist.

- [ ] **Step 4: Implement deterministic metrics and SchedulerBinding adapter**

Nearest-rank percentile sorts microseconds and selects
ceil(percentile times count) minus one. Reject an empty eligible list by
returning available false rather than zero. FrameTimingSampler registers one
timings callback, stores FrameTiming.totalSpan, start/end instants, raw and
post-warm-up counts, counts/ratios above 16.7 ms and 32 ms, P95, and observed
duration. It always unregisters the callback in stop() and dispose().

- [ ] **Step 5: Emit real gesture completion events**

Track gestureStartCamera and whether two pointers were observed. Add
onScaleEnd. Emit rotation only when a one-pointer gesture changed yaw/pitch;
emit zoom only when a two-pointer gesture changed zoom; emit selection only
after hit testing resolves an existing point.

Forward the optional callback from TraceVectorSpaceView to
InteractiveVectorPlot. Do not change default camera, projection math, point
selection, repaint rules, or normal pages when the callback is null.

- [ ] **Step 6: Format and run focused plus R4.9 tests GREEN**

~~~bash
dart format lib/acceptance/frame_timing_sampler.dart lib/acceptance/vector_interaction_evidence.dart lib/ui/microscope/vector_space_3d.dart lib/ui/microscope/vector_space_page.dart test/r50_frame_timing_test.dart test/r50_vector_interaction_evidence_test.dart
flutter test test/r50_frame_timing_test.dart test/r50_vector_interaction_evidence_test.dart test/r49_vector_space_3d_math_test.dart test/r49_interactive_vector_plot_test.dart test/r49_vector_space_page_test.dart
~~~

Expected: all R4.9 and R5.0 interaction tests pass.

- [ ] **Step 7: Commit Task 6**

~~~bash
git add pilot/flutter_phone_loop/lib/acceptance/frame_timing_sampler.dart pilot/flutter_phone_loop/lib/acceptance/vector_interaction_evidence.dart pilot/flutter_phone_loop/lib/ui/microscope/vector_space_3d.dart pilot/flutter_phone_loop/lib/ui/microscope/vector_space_page.dart pilot/flutter_phone_loop/test/r50_frame_timing_test.dart pilot/flutter_phone_loop/test/r50_vector_interaction_evidence_test.dart
git commit -m "feat(r50): measure real 3D interaction and frame timing"
~~~

---

### Task 7: Resource sampler and H1-H10 orchestration

**Files:**

- Create: pilot/flutter_phone_loop/lib/acceptance/device_resource_sampler.dart
- Create: pilot/flutter_phone_loop/lib/acceptance/handset_acceptance_runner.dart
- Create: pilot/flutter_phone_loop/test/r50_device_resource_sampler_test.dart
- Create: pilot/flutter_phone_loop/test/r50_handset_acceptance_runner_test.dart

**Interfaces:**

- DeviceResourceSampler.start(), stop(), stopIfRunning(), isRunning, and ResourceAcceptanceSummary.
- GoldenAcceptanceRun callback accepts onProgress and onTraceReady.
- GoldenAcceptanceInterrupt callback accepts a stable reason code.
- VectorInteractionRun callback accepts VectorAcceptanceArtifact.
- ModelReadinessProbe returns ModelReadinessResult.
- HandsetAcceptanceRunner.run() accepts onProgress and runInteraction.
- HandsetAcceptanceRunner.recoverInterruptedCheckpoint() is safe to call more than once.
- HandsetAcceptanceRunner.interrupt(String reasonCode) returns Future<void> and is cooperative/idempotent.

- [ ] **Step 1: Write failing H8 resource-boundary tests**

Assert one-second samples pass through MODERATE, fail at SEVERE, fail when
lowMemory is true, fail when available bytes dip below the Android threshold,
and fail when final post-H9 PSS exceeds the pre-H4 baseline by more than 512
MiB. Battery temperature and peak PSS remain evidence-only.

- [ ] **Step 2: Write failing runner scenario tests with fakes**

Create fakes for diagnostics, preservation, store, Golden run, artifact
capture, interaction, model readiness, resource sampler, and clock. Cover:

1. candidate 2023 with valid 2022 baseline and every gate passing returns PASS
   and mergeCandidate true;
2. no baseline returns BLOCKED, runs safe H4-H10, and writes a baseline only
   when H1/H2/H4-H9 and cleanup pass;
3. non-target or non-canonical run never replaces a valid baseline;
4. H7 failure outranks H3 blocked;
5. missing model blocks H4/H5/H6 but still finalizes a report;
6. interrupt sets APP_BACKGROUND_INTERRUPTION and invokes cleanup;
7. setKeepScreenOn(false) executes in finally after every exception;
8. nested Golden percent maps monotonically into H4's 55-percent window;
9. sampling continues through the post-run preservation capture and a baseline
   is not written until H8 has passed;
10. a stale nonterminal checkpoint is converted to PROCESS_INTERRUPTED only
    after known Golden fixtures are removed, and cleanup failure stops a new
    run with FAIL;
11. selective rerun state is impossible because run always allocates a new ID.

- [ ] **Step 3: Run both files and confirm RED**

~~~bash
cd pilot/flutter_phone_loop
flutter test test/r50_device_resource_sampler_test.dart test/r50_handset_acceptance_runner_test.dart
~~~

Expected: sampler and runner do not exist.

- [ ] **Step 4: Implement resource sampling and evaluation**

DeviceResourceSampler accepts DeviceDiagnosticsGateway, interval, and clock.
start() captures the post-readiness baseline and starts Timer.periodic at one
second. stop() cancels the timer, captures a final sample, and returns a
summary. stopIfRunning() returns null when idle and delegates to stop() exactly
once when active. A read error is REQUIRED_EVIDENCE_UNAVAILABLE, not a
zero-valued sample.

Use these exact orchestration boundaries so every dependency is fakeable and
tests do not load a model or wait on wall time:

~~~dart
typedef GoldenAcceptanceRun = Future<GoldenTestReport> Function({
  GoldenProgressCallback? onProgress,
  GoldenTraceReadyCallback? onTraceReady,
});

typedef GoldenAcceptanceInterrupt = Future<void> Function(String reasonCode);

typedef KnownFixtureCleanup = Future<void> Function();

typedef VectorArtifactCapture = Future<VectorAcceptanceArtifact> Function(
  String traceId,
);

typedef VectorInteractionRun = Future<VectorInteractionResult> Function(
  VectorAcceptanceArtifact artifact,
);

typedef ModelReadinessProbe = Future<ModelReadinessResult> Function();

class ModelReadinessResult {
  const ModelReadinessResult._(this.ready, this.reasonCode);
  const ModelReadinessResult.passed() : this._(true, null);
  const ModelReadinessResult.blocked(String reasonCode)
      : this._(false, reasonCode);

  final bool ready;
  final String? reasonCode;
}
~~~

- [ ] **Step 5: Implement the outer run in a fixed, checkpointed sequence**

recoverInterruptedCheckpoint(), and run() as a defensive first step, read the
last checkpoint. If it is nonterminal, invoke
the injected KnownFixtureCleanup (production uses
RetrievalBenchmarkFixture.removeKnownFixtures(engine)), convert its running
and pending gates to blocked with PROCESS_INTERRUPTED, force mergeCandidate
false, and persist it before allocating a new run ID. If cleanup fails, attach
the sanitized cleanupError, persist the resulting FAIL snapshot, and return it
without starting new work.

HandsetAcceptanceRunner.interrupt stores only the first reason, signals the
guided interaction page, and awaits GoldenAcceptanceInterrupt when H4 is
active. Every gate boundary observes that reason and transitions remaining
safe work to blocked before the final cleanup/report path.

The new-run sequence is:

~~~dart
try {
  await diagnostics.setKeepScreenOn(true);
  await runH1TargetDevice();
  await runH2BuildIdentity();
  await runH3UpgradeBaseline();
  await runModelReadiness();
  final before = await preservation.capture(identity);
  await resources.start();
  await runH4Golden();
  await runH5VectorTruth();
  await runH6Interaction(runInteraction);
  await runH7RenderPerformance();
  await runH9Preservation(before);
  await runH8MemoryThermal(await resources.stop());
  await writeBaselineIfEligible();
  await runH10ReportIntegrity();
  return currentSnapshot;
} finally {
  try {
    await resources.stopIfRunning();
  } finally {
    await diagnostics.setKeepScreenOn(false);
  }
}
~~~

Before and after every gate, persist the snapshot and notify onProgress only
after persistence succeeds. Continue independent safe gates after a block or
failure. Block H5/H6/H7 when H4 or trace capture is unavailable. Record
interrupt reasons as blocked and do not write a baseline. Although the visible
gate list remains H1-H10, H9's post-run preservation capture intentionally
finishes before H8 evaluation so the one-second resource window includes the
entire workload. A missing baseline is written only after H8 and only under
the exact H1/H2/H4-H9 plus nested-cleanup eligibility rule in the spec.

H10 has no circular success claim. Build a prospective snapshot with H10
passed, phase completed, and mergeCandidate true only when the verdict is PASS,
the installed build is candidate 2023, H1/H2/H3 passed, the matched baseline
version is lower, the package/signer are canonical, and the source commit/APK
digest are valid. Derive PHONE_FUNCTION_LOOP from H4 and DEVICE_ACCEPTANCE from
the prospective verdict. Encode and validate that allow-listed report, persist
it atomically, then publish the prospective snapshot and its 100-percent
checkpoint. If encoding, report persistence, or final checkpointing fails,
replace H10 with failed, force mergeCandidate false, retain the sanitized
failure reason, and persist the failure checkpoint when possible.

- [ ] **Step 6: Format and run focused tests GREEN**

~~~bash
dart format lib/acceptance/device_resource_sampler.dart lib/acceptance/handset_acceptance_runner.dart test/r50_device_resource_sampler_test.dart test/r50_handset_acceptance_runner_test.dart
flutter test test/r50_device_resource_sampler_test.dart test/r50_handset_acceptance_runner_test.dart
~~~

Expected: all scenario tests pass with no wall-clock delay.

- [ ] **Step 7: Commit Task 7**

~~~bash
git add pilot/flutter_phone_loop/lib/acceptance/device_resource_sampler.dart pilot/flutter_phone_loop/lib/acceptance/handset_acceptance_runner.dart pilot/flutter_phone_loop/test/r50_device_resource_sampler_test.dart pilot/flutter_phone_loop/test/r50_handset_acceptance_runner_test.dart
git commit -m "feat(r50): orchestrate consolidated handset acceptance"
~~~

---

### Task 8: Guided physical 3D interaction page

**Files:**

- Create: pilot/flutter_phone_loop/lib/ui/handset_vector_interaction_page.dart
- Create: pilot/flutter_phone_loop/test/r50_handset_vector_interaction_page_test.dart

**Interfaces:**

- HandsetVectorInteractionPage receives VectorAcceptanceArtifact,
  FrameTimingSampler, minimumDuration, timeout, and an interruption listenable.
- Navigator result is VectorInteractionResult.

- [ ] **Step 1: Write failing task-chip and completion tests**

Pump the page at 412 by 915. Inject a fake timing sampler whose summary has 15
seconds, 180 eligible frames, P95 16 ms, and zero severe jank.

Perform one-finger drag, two-finger scale, and point tap. Assert the chips
已旋转, 已缩放, and 已点选 become complete only after their production events.
Confirm the bottom button is disabled until the frame window and all actions
pass, then tap 界面完整并继续 and assert the Navigator result has
viewportConfirmed true.

- [ ] **Step 2: Write failing timeout, interruption, and overflow tests**

With no gestures, pump 91 seconds and expect USER_ACTION_INCOMPLETE. Trigger
the interruption listenable and expect APP_BACKGROUND_INTERRUPTION. Repeat
layout tests at 360 by 800, 412 by 915, dark theme, and textScaleFactor 1.3;
assert tester.takeException() is null.

- [ ] **Step 3: Run the widget test and confirm RED**

~~~bash
cd pilot/flutter_phone_loop
flutter test test/r50_handset_vector_interaction_page_test.dart
~~~

Expected: the page is undefined.

- [ ] **Step 4: Implement the full-screen guided page**

Use an AnimationController repeating for the 15-second measurement window so
Flutter produces observable frames without changing the camera. Start the
FrameTimingSampler after the first rendered frame. Feed TraceVectorSpaceView
the artifact data and onInteraction callback. Show live elapsed time, eligible
frame count, P95, and the three task chips.

The 90-second timer returns a blocked VectorInteractionResult. dispose()
cancels both timers, stops the animation, unregisters frame timings, and never
leaves a callback attached.

- [ ] **Step 5: Format and run widget plus R4.9 tests GREEN**

~~~bash
dart format lib/ui/handset_vector_interaction_page.dart test/r50_handset_vector_interaction_page_test.dart
flutter test test/r50_handset_vector_interaction_page_test.dart test/r49_interactive_vector_plot_test.dart test/r49_vector_space_page_test.dart
~~~

Expected: all pass without overflow.

- [ ] **Step 6: Commit Task 8**

~~~bash
git add pilot/flutter_phone_loop/lib/ui/handset_vector_interaction_page.dart pilot/flutter_phone_loop/test/r50_handset_vector_interaction_page_test.dart
git commit -m "feat(r50): guide physical 3D handset interaction"
~~~

---

### Task 9: Production composition, one-tap dashboard, lifecycle, and export

**Files:**

- Create: pilot/flutter_phone_loop/lib/acceptance/handset_acceptance_composition.dart
- Create: pilot/flutter_phone_loop/lib/ui/handset_acceptance_widgets.dart
- Create: pilot/flutter_phone_loop/lib/ui/handset_acceptance_page.dart
- Modify: pilot/flutter_phone_loop/lib/ui/model_settings_page.dart
- Modify: pilot/flutter_phone_loop/lib/ui/main_shell.dart
- Create: pilot/flutter_phone_loop/test/r50_handset_acceptance_ui_test.dart
- Modify: pilot/flutter_phone_loop/test/r48_phone_acceptance_regression_test.dart

**Interfaces:**

- HandsetAcceptanceComposition.create(KnowledgeEngine, ChatSessionStore).
- HandsetAcceptancePage accepts an optional runner factory and report saver for tests.
- ModelSettingsPage requires KnowledgeEngine and ChatSessionStore and accepts an optional acceptance page builder.

- [ ] **Step 1: Write failing prominent-entry and terminal-state widget tests**

Pump ModelSettingsPage without changing the installed-model static state.
Assert 手机一键验收 is visible regardless of readiness, appears above 高级 /
诊断, the latest verdict and baseline status are human-readable, and tapping
starts one full-screen route. Model readiness is checked only after the user
starts the run, where a missing model becomes a truthful BLOCKED result.
Seed a nonterminal last checkpoint and assert entry initialization awaits the
injected recovery call before rendering PROCESS_INTERRUPTED.

Pump HandsetAcceptancePage with fake runners that emit running H4, awaiting H6,
PASS, FAIL, and BLOCKED snapshots. Assert:

- determinate percent/current step/elapsed/checkpoint text;
- expandable nested F1-F10 rows;
- live frame/PSS/memory/battery/thermal evidence;
- green/red/amber terminal cards;
- reason and remediation text;
- only 查看证据, 导出脱敏报告, and 完整重跑 are offered;
- a second start is disabled while active.

- [ ] **Step 2: Write failing lifecycle and export tests**

Simulate AppLifecycleState.paused and assert interrupt is called with
APP_BACKGROUND_INTERRUPTION. Inject a report saver, tap 导出脱敏报告, and assert
the exact redacted bytes/file name are supplied. Assert no token-like test
value appears in visible text.

- [ ] **Step 3: Run UI tests and confirm RED**

~~~bash
cd pilot/flutter_phone_loop
flutter test test/r50_handset_acceptance_ui_test.dart test/r48_phone_acceptance_regression_test.dart
~~~

Expected: new page/widgets and required ChatSessionStore parameter are absent.

- [ ] **Step 4: Implement production dependency composition**

Composition wires MethodChannelDeviceDiagnostics, PreservationProbe,
HandsetAcceptanceStore, GoldenTestRunner.run/interrupt,
VectorAcceptanceCapture, DeviceResourceSampler, known-fixture cleanup, and
model readiness.

When the acceptance entry first loads, composition invokes
recoverInterruptedCheckpoint() before showing the latest verdict. run() repeats
the same idempotent recovery guard so a race or direct deep link cannot bypass
known-fixture cleanup.

Model readiness performs:

~~~dart
if (!FlutterGemma.hasActiveModel() || !FlutterGemma.hasActiveEmbedder()) {
  return const ModelReadinessResult.blocked('MODEL_PREREQUISITE_MISSING');
}
await FlutterGemma.getActiveEmbedder();
final model = GemmaService();
try {
  await model.ensureLoaded();
} finally {
  await model.close();
}
return const ModelReadinessResult.passed();
~~~

No model download or OAuth refresh occurs.

- [ ] **Step 5: Implement page orchestration and human-readable widgets**

HandsetAcceptancePage owns WidgetsBindingObserver, starts one runner, pushes
HandsetVectorInteractionPage from the runner callback, and restores the
acceptance page when the interaction returns. It always removes the lifecycle
observer. didChangeAppLifecycleState uses unawaited(runner.interrupt(...)) for
any transition away from resumed while active; interrupt itself owns error
capture and never lets an unhandled Future reach the zone.

HandsetAcceptanceProgressPanel displays H1-H10 and nested F1-F10. Evidence rows
prefer Chinese label, actual value plus unit, threshold, reason, and next
action; technical IDs remain under 开发者详情.

Use HandsetReportExporter.saveWithPicker for export. Show the returned Uri or
用户取消导出, never an inaccessible internal path as the only result.

- [ ] **Step 6: Add the prominent settings card without removing Golden Test**

Pass widget.store from MainShell into ModelSettingsPage. Insert
HandsetAcceptanceEntryCard immediately after the model readiness card and
before OAuth/license/Advanced content. Retain the existing Run Phone Golden
Test under Advanced for focused diagnostics.

- [ ] **Step 7: Format and run UI tests GREEN**

~~~bash
dart format lib/acceptance/handset_acceptance_composition.dart lib/ui/handset_acceptance_widgets.dart lib/ui/handset_acceptance_page.dart lib/ui/model_settings_page.dart lib/ui/main_shell.dart test/r50_handset_acceptance_ui_test.dart test/r48_phone_acceptance_regression_test.dart
flutter test test/r50_handset_acceptance_ui_test.dart test/r48_phone_acceptance_regression_test.dart
~~~

Expected: all pass, including old Golden Test UI coverage.

- [ ] **Step 8: Commit Task 9**

~~~bash
git add pilot/flutter_phone_loop/lib/acceptance/handset_acceptance_composition.dart pilot/flutter_phone_loop/lib/ui/handset_acceptance_widgets.dart pilot/flutter_phone_loop/lib/ui/handset_acceptance_page.dart pilot/flutter_phone_loop/lib/ui/model_settings_page.dart pilot/flutter_phone_loop/lib/ui/main_shell.dart pilot/flutter_phone_loop/test/r50_handset_acceptance_ui_test.dart pilot/flutter_phone_loop/test/r48_phone_acceptance_regression_test.dart
git commit -m "feat(r50): add one-tap S24U acceptance dashboard"
~~~

---

### Task 10: Deterministic CI-plus-device readiness adjudicator

**Files:**

- Create: pilot/flutter_phone_loop/lib/acceptance/release_readiness_adjudicator.dart
- Create: pilot/flutter_phone_loop/tool/adjudicate_handset_acceptance.dart
- Create: pilot/flutter_phone_loop/test/r50_release_readiness_adjudicator_test.dart

**Interfaces:**

- DeviceAcceptanceEvidence.fromJson() uses schema
  pocketgallery.r50.handset-acceptance.v1 and validates the nested gate set.
- AutomatedReleaseEvidence.fromJson() uses schema pocketgallery.r50.automated-evidence.v1.
- ReleaseReadinessAdjudicator.adjudicate(deviceReport, automatedEvidence, sidecarSha256).
- ReleaseReadinessDecision exposes mergeReady and stable reasons.
- CLI arguments are --device-report, --automated-evidence, --apk-sha256, and --output.

- [ ] **Step 1: Write failing pass and mismatch tests**

Construct matching candidate evidence with source commit, package, versionCode
2023, canonical signer, APK SHA, automatedGatesPassed true,
DEVICE_ACCEPTANCE PASS, and MERGE_CANDIDATE true. Assert MERGE_READY true.

Individually change commit, package, version, signer, device APK digest,
sidecar digest, CI gate status, device verdict, and merge-candidate flag.
Assert MERGE_READY false with the exact corresponding reason:

- SOURCE_COMMIT_MISMATCH
- PACKAGE_MISMATCH
- VERSION_CODE_MISMATCH
- SIGNER_MISMATCH
- DEVICE_APK_DIGEST_MISMATCH
- SIDECAR_DIGEST_MISMATCH
- AUTOMATED_GATES_FAILED
- DEVICE_GATE_STATUS_INVALID
- PHONE_FUNCTION_LOOP_NOT_PASS
- NESTED_GOLDEN_NOT_PASS
- DEVICE_ACCEPTANCE_NOT_PASS
- MERGE_CANDIDATE_FALSE

- [ ] **Step 2: Run the test and confirm RED**

~~~bash
cd pilot/flutter_phone_loop
flutter test test/r50_release_readiness_adjudicator_test.dart
~~~

Expected: adjudicator types are missing.

- [ ] **Step 3: Implement strict typed parsing and all-reasons evaluation**

Parsing rejects unknown schema, missing/wrong-typed fields, malformed commit or
digest lengths, and missing/duplicate/unknown H or F gate names. It accepts
well-shaped but non-matching version, package, signer, status, and digest values
so the adjudicator can emit a complete deterministic mismatch decision instead
of misclassifying evidence mismatch as malformed input. Normalize hex to lower
case but do not normalize package or source commit.

Adjudication requires candidate 2023, canonical signer, exactly H1-H10 passed,
PHONE_FUNCTION_LOOP PASS, nested Golden schema 2 with exactly F1-F10 passed and
no cleanupError, plus internal consistency among DEVICE_ACCEPTANCE,
MERGE_CANDIDATE, and gate status. Collect every mismatch reason in the listed
order.

The output JSON is:

~~~json
{
  "schema": "pocketgallery.r50.merge-readiness.v1",
  "mergeReady": true,
  "reasons": [],
  "sourceCommit": "0123456789abcdef0123456789abcdef01234567",
  "versionCode": 2023,
  "apkSha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
}
~~~

- [ ] **Step 4: Implement the CLI and exit contract**

Parse the four required flags without a new argument package. Read and decode
the two JSON inputs, parse the first whitespace-delimited token of the sidecar,
write indented JSON atomically, print MERGE_READY=true or false, and exit:

- 0 for ready;
- 2 for evidence mismatch;
- 64 for invalid command arguments or malformed input.

- [ ] **Step 5: Format and run unit plus CLI smoke tests GREEN**

~~~bash
dart format lib/acceptance/release_readiness_adjudicator.dart tool/adjudicate_handset_acceptance.dart test/r50_release_readiness_adjudicator_test.dart
flutter test test/r50_release_readiness_adjudicator_test.dart
dart run tool/adjudicate_handset_acceptance.dart --help
~~~

Expected: unit tests pass; --help prints usage and exits 0.

- [ ] **Step 6: Commit Task 10**

~~~bash
git add pilot/flutter_phone_loop/lib/acceptance/release_readiness_adjudicator.dart pilot/flutter_phone_loop/tool/adjudicate_handset_acceptance.dart pilot/flutter_phone_loop/test/r50_release_readiness_adjudicator_test.dart
git commit -m "feat(r50): adjudicate same-commit merge readiness"
~~~

---

### Task 11: R5.0 versions, canonical signing fallback, dual APKs, and automated evidence

**Files:**

- Modify: pilot/flutter_phone_loop/pubspec.yaml
- Modify: pilot/flutter_phone_loop/scripts/android_version_code.sh only if its test exposes an assumption beyond reading pubspec
- Modify: .github/workflows/pocketgallery-r46-tdd.yml
- Modify: .github/workflows/pocketgallery-phone-pilot-apk.yml
- Create: pilot/flutter_phone_loop/test/r50_release_contract_test.dart
- Modify: pilot/flutter_phone_loop/test/r49_release_contract_test.dart
- Modify: pilot/flutter_phone_loop/README.md
- Modify: docs/phone-pilot/release-checklist.md
- Modify: docs/phone-pilot/verification-matrix.md
- Create: docs/phone-pilot/r50-s24u-handset-acceptance-runbook.md

**Interfaces:**

- pubspec version is 0.5.0+23.
- TDD artifact is PocketGallery-R50-handset-acceptance-debug.apk.
- Canonical artifacts are PocketGallery-R50-baseline-v2022.apk and PocketGallery-R50-candidate-v2023.apk.
- Canonical evidence file is PG_AUTOMATED_EVIDENCE.json.

- [ ] **Step 1: Write failing release-contract tests**

Assert:

1. pubspec is 0.5.0+23 and android_version_code.sh prints 2023;
2. both workflows pass POCKETGALLERY_SOURCE_COMMIT from the checked-out commit;
3. the canonical workflow builds arm64 baseline with build-number 22 and
   candidate with build-number 23;
4. both APKs verify the stable package, expected versionCode, arm64 ABI, and
   canonical signer;
5. both receive SHA-256 sidecars;
6. PG_AUTOMATED_EVIDENCE.json includes schema, source commit, automated status,
   package, candidate version, signer, APK digest, and workflow identity;
7. missing cache uses only the four named secrets under RUNNER_TEMP;
8. neither workflow contains keytool -genkey, a new alias, or a replacement
   signer;
9. absent cache and absent secrets still emit SIGNING_IDENTITY_MISSING and exit
   non-zero.

- [ ] **Step 2: Run the release test and confirm RED**

~~~bash
cd pilot/flutter_phone_loop
flutter test test/r50_release_contract_test.dart test/r49_release_contract_test.dart
~~~

Expected: old version/artifact/workflow assertions fail.

- [ ] **Step 3: Advance version and non-canonical TDD artifact**

Set pubspec to 0.5.0+23. Build the TDD APK with:

~~~bash
source_commit="$(git rev-parse HEAD)"
flutter build apk --debug --target-platform android-arm64 --split-per-abi --dart-define=POCKETGALLERY_SOURCE_COMMIT="$source_commit"
~~~

Verify versionCode 2023 and rename/upload the R50 debug artifact plus sidecar.
Keep it explicitly non-canonical and unsuitable for an in-place update.

- [ ] **Step 4: Add cache-then-secret canonical credential restoration**

If the existing cache keystore/password are present, retain the current path.
Otherwise read these masked workflow secrets:

- POCKETGALLERY_SIGNING_KEYSTORE_B64
- POCKETGALLERY_SIGNING_STORE_PASSWORD
- POCKETGALLERY_SIGNING_KEY_PASSWORD
- POCKETGALLERY_SIGNING_KEY_ALIAS

Decode only to RUNNER_TEMP, verify the pinned certificate before exporting
POCKETGALLERY_SIGNING_* environment variables, and never copy secret fallback
material into the cache directory. If neither source exists, retain exit 74
SIGNING_IDENTITY_MISSING.

- [ ] **Step 5: Build and verify the same-source canonical pair**

Build baseline 22 and candidate 23 with the same source commit Dart define.
After each build, copy the split arm64 APK before the next build overwrites it.
Use a shared shell verification function that accepts expected versionCode and
checks package, ABI, signer, and file existence. Hash both artifacts.

~~~bash
source_commit="$(git rev-parse HEAD)"
artifact_dir="build/app/outputs/flutter-apk"

flutter build apk --debug --target-platform android-arm64 --split-per-abi \
  --build-name=0.5.0 --build-number=22 \
  --dart-define=POCKETGALLERY_SOURCE_COMMIT="$source_commit"
cp "$artifact_dir/app-arm64-v8a-debug.apk" \
  "$artifact_dir/PocketGallery-R50-baseline-v2022.apk"

flutter build apk --debug --target-platform android-arm64 --split-per-abi \
  --build-name=0.5.0 --build-number=23 \
  --dart-define=POCKETGALLERY_SOURCE_COMMIT="$source_commit"
cp "$artifact_dir/app-arm64-v8a-debug.apk" \
  "$artifact_dir/PocketGallery-R50-candidate-v2023.apk"
~~~

Generate PG_AUTOMATED_EVIDENCE.json only after analyze, full tests, both APK
verifications, and sidecars pass. Set automatedGatesPassed true only in that
post-verification step.

- [ ] **Step 6: Update user-facing release documentation**

README and the three phone documents must state:

- where 手机一键验收 is located;
- H1-H10 and nested F1-F10 meanings;
- why the first versionCode 2022 run is BLOCKED while establishing baseline;
- the exact 2022-to-2023 installation order;
- no uninstall, redownload, or repeat OAuth;
- how to export the device report;
- how to run the adjudicator;
- SIGNING_IDENTITY_MISSING remains an external credential blocker.

- [ ] **Step 7: Run focused release tests GREEN**

~~~bash
dart format test/r50_release_contract_test.dart test/r49_release_contract_test.dart
flutter test test/r50_release_contract_test.dart test/r49_release_contract_test.dart
bash scripts/android_version_code.sh
~~~

Expected: tests pass and the script prints 2023.

- [ ] **Step 8: Commit Task 11**

~~~bash
git add pilot/flutter_phone_loop/pubspec.yaml pilot/flutter_phone_loop/scripts/android_version_code.sh .github/workflows/pocketgallery-r46-tdd.yml .github/workflows/pocketgallery-phone-pilot-apk.yml pilot/flutter_phone_loop/test/r50_release_contract_test.dart pilot/flutter_phone_loop/test/r49_release_contract_test.dart pilot/flutter_phone_loop/README.md docs/phone-pilot/release-checklist.md docs/phone-pilot/verification-matrix.md docs/phone-pilot/r50-s24u-handset-acceptance-runbook.md
git commit -m "build(r50): publish verified handset acceptance artifacts"
~~~

---

### Task 12: Full regression, fresh Android build, evidence review, and branch handoff

**Files:**

- Modify only files required to fix failures caused by Tasks 1-11.
- Update: docs/phone-pilot/r50-s24u-handset-acceptance-runbook.md with the
  final static commands, expected evidence fields, and truthful NOT_RUN device
  state before the final source commit.

**Interfaces:**

- Automated completion is SOURCE_AUTOMATION = PASS.
- Canonical signing without credentials is SIGNING_IDENTITY_MISSING.
- Physical state remains DEVICE_ACCEPTANCE = NOT_RUN until the user runs both APKs on SM-S9280.

- [ ] **Step 1: Verify formatting and static analysis**

~~~bash
cd pilot/flutter_phone_loop
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
~~~

Expected: no formatting changes and No issues found.

- [ ] **Step 2: Run the complete Flutter regression suite**

~~~bash
flutter test
~~~

Expected: every existing and new test passes with zero failures.

- [ ] **Step 3: Recreate and compile the Android host from a fresh scaffold**

Move only the generated, ignored pilot/flutter_phone_loop/android directory to
a fresh temporary backup after proving Git does not track it, then recreate it:

~~~bash
test -z "$(git ls-files -- android)"
if [ -d android ]; then
  android_backup_dir="$(mktemp -d)"
  mv -- android "$android_backup_dir/generated-android"
fi
bash scripts/bootstrap_android.sh
flutter build apk --debug --target-platform android-arm64 --split-per-abi --dart-define=POCKETGALLERY_SOURCE_COMMIT="$(git rev-parse HEAD)"
~~~

Expected: BOOTSTRAP_PASS and a non-empty arm64 APK.

- [ ] **Step 4: Independently inspect the local debug candidate**

Use aapt to assert package
com.qujindai.pocketgallery_phone_pilot.r3 and versionCode 2023. Use unzip to
assert the only native ABI is arm64-v8a. Hash the APK twice with sha256sum and
compare values. Record that its debug signer is non-canonical and therefore
cannot prove upgrade acceptance.

- [ ] **Step 5: Perform focused privacy and state checks**

~~~bash
flutter test test/r50_handset_report_redaction_test.dart test/r50_preservation_probe_test.dart test/r50_release_readiness_adjudicator_test.dart
rg -n -i "authorization|bearer|rawVector|vectorF32|documentText" lib/acceptance test/r50_handset_report_redaction_test.dart
~~~

Expected: tests pass; any grep hit is an explicit deny-list/test fixture rather
than an exported field.

- [ ] **Step 6: Request independent code review and resolve findings**

Review the final diff against the spec with special attention to:

- abandoned native futures and cleanup;
- lifecycle observer/timer/callback disposal;
- baseline replacement eligibility;
- report allow-listing;
- signer and source-commit correlation;
- 360-pixel overflow and human-readable evidence.

Resolve every Critical or Important finding, rerun the affected focused tests,
and commit each coherent correction.

- [ ] **Step 7: Finalize and commit the static runbook**

Record the exact local verification commands, physical 2022-to-2023 order,
adjudicator command, and the truthful pre-device state. Do not embed a workflow
run ID, APK digest, test count, or source SHA that can only exist after this
commit; those dynamic values belong in PG_AUTOMATED_EVIDENCE.json and the
handoff message.

~~~bash
git add docs/phone-pilot/r50-s24u-handset-acceptance-runbook.md
if ! git diff --cached --quiet; then
  git commit -m "docs(r50): finalize handset acceptance runbook"
fi
~~~

- [ ] **Step 8: Re-run full verification at the immutable final HEAD**

~~~bash
flutter analyze
flutter test
git diff --check
git status --short
~~~

Expected: analysis/tests pass and the worktree is clean.

- [ ] **Step 9: Push the final HEAD and observe both GitHub workflows**

~~~bash
git push origin codex/r46-full-microscope
~~~

Confirm both workflows refer to the final HEAD. The non-canonical TDD workflow
must pass. The canonical workflow either publishes the verified 2022/2023 pair
or ends with the explicit existing SIGNING_IDENTITY_MISSING blocker; no other
failure is accepted.

- [ ] **Step 10: Record the truthful automated handoff without changing HEAD**

Report final HEAD, test count, analyze result, local APK package/version/ABI/SHA,
workflow run IDs, and canonical signing result in the implementation handoff.
When canonical signing succeeds, verify the same dynamic values are present in
the downloaded PG_AUTOMATED_EVIDENCE.json. Do not modify or commit a tracked
file after this observation, because doing so would invalidate the same-commit
artifact relationship.

Do not write PHONE_FUNCTION_LOOP = PASS, DEVICE_ACCEPTANCE = PASS,
MERGE_CANDIDATE = true, or MERGE_READY = true before the two physical S24U
runs and adjudication occur.

---

## Physical handoff after implementation

The implementation session stops at a truthful automated result and delivers:

1. a non-canonical debug APK for clean-install UI inspection when canonical
   credentials are blocked;
2. the canonical baseline/candidate pair only when the existing signer is
   restored;
3. SHA-256 sidecars and PG_AUTOMATED_EVIDENCE.json;
4. the S24U runbook.

The user then installs baseline 2022 over current 2021, runs 手机一键验收 to
establish the private baseline, installs candidate 2023 without uninstalling,
runs acceptance again, exports the report, and returns it for adjudication.
Only the adjudicator output PG_MERGE_READINESS.json may move PR #14 out of
Draft.
