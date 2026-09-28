# PocketGallery R4.8 Phone Acceptance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the opaque Phone Golden Test with a bounded, checkpointed, live-progress F1–F7 acceptance runner and ship a verified R4.8 in-place-update APK.

**Architecture:** A pure Dart state model and gate executor own deterministic transitions, timeouts, dependency blocking, and progress. An atomic JSON store persists every transition. `GoldenTestRunner` supplies the real FTS5, Embedding, ChatOrchestrator, and Gemma gate closures, while `ModelSettingsPage` renders live state without creating a second runner.

**Tech Stack:** Flutter/Dart, flutter_test, sqlite3, flutter_gemma/LiteRT-LM, existing GitHub Actions Android workflows.

**Spec:** `docs/superpowers/specs/2026-08-29-pocketgallery-r48-phone-acceptance-design.md`

## Global Constraints

- Preserve package `com.qujindai.pocketgallery_phone_pilot.r3`.
- Preserve signer SHA-256 `81af4a5ef94c236774f0e193b2a4b248805b36c14cc36e2a56df8e451a712541`.
- Advance build number from 2017 to at least 2018.
- Do not change OAuth storage keys, model URLs, model activation identity, database names, or model cache paths.
- Golden fixtures must be removed after every completed or failed run.
- F6/F7 production gates must call the real `ChatOrchestrator` and `GemmaChatService`.
- No timeout, exception, blocked gate, or cleanup failure may produce an overall pass.

---

### Task 1: Acceptance state and bounded gate executor

**Files:**
- Create: `pilot/flutter_phone_loop/lib/services/golden_test_state.dart`
- Create: `pilot/flutter_phone_loop/lib/services/golden_gate_executor.dart`
- Create: `pilot/flutter_phone_loop/test/r48_phone_acceptance_regression_test.dart`

**Interfaces:**
- Produces: `GoldenRunPhase`, `GoldenGateStatus`, `GoldenGateSnapshot`, `GoldenTestSnapshot`.
- Produces: `GoldenGateSpec(name, label, timeout, run, blockedWhen)` and `GoldenGateExecutor.execute(...)`.
- `GoldenGateSpec.run` returns `Future<GateResult>`; exceptions and `TimeoutException` are converted to terminal snapshots.
- `GoldenGateExecutor.execute` accepts `onProgress`, `onCheckpoint`, `onGateTimeout`, and `cleanup` callbacks and returns the final snapshot only after cleanup finishes.

- [ ] **Step 1: Write failing state/executor tests**

```dart
test('gate progress is ordered and monotonic', () async {
  final seen = <GoldenTestSnapshot>[];
  final finalState = await GoldenGateExecutor().execute(
    runId: 'r48-order',
    gates: [
      GoldenGateSpec(
        name: 'F1_IMPORT_CHUNK',
        label: 'Import and chunk fixture',
        timeout: const Duration(seconds: 1),
        run: () async => GateResult('F1_IMPORT_CHUNK', true, 'ok'),
      ),
      GoldenGateSpec(
        name: 'F2_FTS5',
        label: 'FTS5 exact recall',
        timeout: const Duration(seconds: 1),
        run: () async => GateResult('F2_FTS5', true, 'ok'),
      ),
    ],
    onProgress: seen.add,
  );
  expect(
    seen.map((s) => s.percent).toList(),
    orderedEquals([0, 0, 0, 45, 45, 90, 95, 100]),
  );
  expect(finalState.percent, 100);
  expect(finalState.passed, isTrue);
});

test('timeout is terminal and never passes', () async {
  final state = await GoldenGateExecutor().execute(
    runId: 'r48-timeout',
    gates: [
      GoldenGateSpec(
        name: 'F1_IMPORT_CHUNK',
        label: 'Import and chunk fixture',
        timeout: const Duration(milliseconds: 5),
        run: () => Completer<GateResult>().future,
      ),
    ],
  );
  expect(state.gates.single.status, GoldenGateStatus.timedOut);
  expect(state.passed, isFalse);
});
```

- [ ] **Step 2: Push test-only RED commit and verify CI failure**

Run the Phone Pilot workflow on the branch. Expected: compile failure because `golden_test_state.dart` and `GoldenGateExecutor` do not exist.

- [ ] **Step 3: Implement immutable state and JSON serialization**

Implement `copyWith`, terminal-status helpers, completed-count calculation, monotonic percent calculation, `toJson`, and `GoldenTestSnapshot.initial(runId, gates)`.

- [ ] **Step 4: Implement sequential gate execution**

Use `Future.timeout`, catch timeout separately, call `onGateTimeout`, evaluate `blockedWhen` before a gate starts, and emit/checkpoint before and after every transition. Reserve 90% for completed gates, emit 95% while cleaning up, and set phase to `completed`/100% only after the supplied cleanup callback succeeds. A cleanup exception is recorded in `cleanupError` and forces overall failure.

- [ ] **Step 5: Run focused and full tests**

Run: `flutter test test/r48_phone_acceptance_regression_test.dart`

Expected: PASS for ordering, monotonic percentage, timeout, F1 blocking, and F6→F7 blocking.

- [ ] **Step 6: Commit**

```bash
git add pilot/flutter_phone_loop/lib/services/golden_test_state.dart pilot/flutter_phone_loop/lib/services/golden_gate_executor.dart pilot/flutter_phone_loop/test/r48_phone_acceptance_regression_test.dart
git commit -m "feat: add bounded phone acceptance executor"
```

### Task 2: Recoverable atomic checkpoint persistence

**Files:**
- Create: `pilot/flutter_phone_loop/lib/services/golden_test_report_store.dart`
- Modify: `pilot/flutter_phone_loop/test/r48_phone_acceptance_regression_test.dart`

**Interfaces:**
- Consumes: `GoldenTestSnapshot.toJson()` from Task 1.
- Produces: `GoldenTestReportStore({Future<Directory> Function()? directoryProvider})`.
- Produces: `Future<File> save(GoldenTestSnapshot snapshot)` and `Future<GoldenTestSnapshot?> readLast()` with `.bak` fallback.

- [ ] **Step 1: Write failing atomic checkpoint tests**

```dart
test('checkpoint remains valid JSON after an intermediate failure', () async {
  final directory = await Directory.systemTemp.createTemp('pg-r48-');
  final store = GoldenTestReportStore(directoryProvider: () async => directory);
  final state = GoldenTestSnapshot.initial('r48-store', testGateDefinitions)
      .copyWith(phase: GoldenRunPhase.running);
  final file = await store.save(state);
  expect(jsonDecode(await file.readAsString()), isA<Map<String, dynamic>>());
  expect(File('${file.path}.tmp').existsSync(), isFalse);
  expect((await store.readLast())!.runId, 'r48-store');
});
```

- [ ] **Step 2: Run RED test**

Expected: compile failure because `GoldenTestReportStore` does not exist.

- [ ] **Step 3: Implement temp-write plus rename**

Write and flush `PG_GOLDEN_LAST.json.tmp`; rotate a valid destination to `PG_GOLDEN_LAST.json.bak`; rename the complete temporary file into place; then remove the backup. `readLast()` must validate the primary JSON and fall back to the backup if the primary is absent or malformed, so an interrupted swap still exposes either the previous or new valid snapshot.

- [ ] **Step 4: Test malformed/empty detail serialization**

Add a snapshot containing empty details, newlines, and exception text. Assert save/read round-trips and JSON remains valid.

- [ ] **Step 5: Run focused tests and commit**

```bash
flutter test test/r48_phone_acceptance_regression_test.dart
git add pilot/flutter_phone_loop/lib/services/golden_test_report_store.dart pilot/flutter_phone_loop/test/r48_phone_acceptance_regression_test.dart
git commit -m "feat: persist phone acceptance checkpoints atomically"
```

### Task 3: Integrate real F1–F7 and strengthen F7

**Files:**
- Modify: `pilot/flutter_phone_loop/lib/services/golden_test_runner.dart`
- Modify: `pilot/flutter_phone_loop/test/r48_phone_acceptance_regression_test.dart`
- Modify: `pilot/flutter_phone_loop/test/r43_realworld_phone_regression_test.dart`

**Interfaces:**
- Consumes: `GoldenGateExecutor`, `GoldenTestReportStore`, state types.
- Produces: `GoldenTestRunner.run({void Function(GoldenTestSnapshot)? onProgress})`.
- Produces: `GoldenF7Assertion.evaluate(ChatMessage reply, Set<String> validAnchors)` as a pure testable assertion.
- Keeps: `GoldenTestReport.results` compatibility for existing UI/tests while adding `snapshot`.

- [ ] **Step 1: Write failing strict-F7 tests**

```dart
test('F7 rejects a non-empty response without E6', () {
  final reply = ChatMessage.assistant(
    id: 'a1',
    sessionId: 's1',
    text: '上下文正常 [E1]',
    retrievalMode: 'knowledge:lexical-only',
    citedAnchorsJson: ChatMessage.encodeAnchors(['E1']),
  );
  expect(GoldenF7Assertion.evaluate(reply, {'E1', 'E2', 'E3', 'E4', 'E5', 'E6'}).passed, isFalse);
});
```

Add a GREEN-only expected case containing `PG_EVIDENCE_LAST_6`, citation `E6`, and knowledge retrieval mode.

- [ ] **Step 2: Run RED test**

Expected: compile failure because `GoldenF7Assertion` and progress-enabled runner do not exist.

- [ ] **Step 3: Refactor existing F1–F7 bodies into gate closures**

Keep the same stores and queries. Wire gate-specific timeouts from the design. Persist every emitted snapshot through the store. Preserve temporary fixture/chat cleanup and convert cleanup exceptions into failed final state.

- [ ] **Step 4: Replace heavy evidence with six distinct sources**

Generate anchors `E1`–`E6`; start each body with `PG_EVIDENCE_ITEM_n`, and start E6 with `PG_EVIDENCE_LAST_6`. Ask the second turn to return the final sentinel and cite its exact evidence.

- [ ] **Step 5: Apply strict F7 assertion**

Require non-empty text, final sentinel, `E6`, valid citations only, and a `knowledge:` retrieval mode. F6 failure or timeout blocks F7.

- [ ] **Step 6: Run focused/full tests and commit**

```bash
flutter test test/r48_phone_acceptance_regression_test.dart test/r43_realworld_phone_regression_test.dart
flutter test
git add pilot/flutter_phone_loop/lib/services/golden_test_runner.dart pilot/flutter_phone_loop/test/r48_phone_acceptance_regression_test.dart pilot/flutter_phone_loop/test/r43_realworld_phone_regression_test.dart
git commit -m "feat: make F1-F7 phone acceptance strict and recoverable"
```

### Task 4: Live phone progress UI and documentation

**Files:**
- Modify: `pilot/flutter_phone_loop/lib/ui/model_settings_page.dart`
- Modify: `pilot/flutter_phone_loop/README.md`
- Modify: `pilot/flutter_phone_loop/test/r48_phone_acceptance_regression_test.dart`

**Interfaces:**
- Consumes: `GoldenTestSnapshot` and `GoldenGateSnapshot`.
- Produces: `GoldenTestProgressPanel(snapshot: ...)`, a directly widget-testable view of live state.
- The UI stores the latest snapshot in state and passes `onProgress` to `GoldenTestRunner.run`.

- [ ] **Step 1: Write failing UI behavior tests**

Pump `GoldenTestProgressPanel` with hand-built running, timed-out, blocked, and completed snapshots. Assert the rendered `LinearProgressIndicator.value`, percentage, current gate/total, completed/total, elapsed time, checkpoint-saved text, final verdict, and the six localized status labels. Do not inspect source text.

- [ ] **Step 2: Run RED test**

Expected: failure because the page still shows only an indeterminate spinner and final rows.

- [ ] **Step 3: Implement live progress panel**

Add the determinate bar, percentage, current gate label, completed count, elapsed time, per-gate rows, and checkpoint text. Keep the run button disabled while active and retain final PASS/FAIL.

- [ ] **Step 4: Update README**

Document automatic model reuse, no repeated OAuth/model download on in-place upgrades, F1–F7 meanings, timeouts, checkpoint file, strict F7, and that one chunk currently produces one vector observation without making the concepts equivalent.

- [ ] **Step 5: Run tests and commit**

```bash
flutter test test/r48_phone_acceptance_regression_test.dart test/r4_model_settings_ui_test.dart
git add pilot/flutter_phone_loop/lib/ui/model_settings_page.dart pilot/flutter_phone_loop/README.md pilot/flutter_phone_loop/test/r48_phone_acceptance_regression_test.dart
git commit -m "feat: expose live F1-F7 phone acceptance progress"
```

### Task 5: R4.8 release gate and verified APK

**Files:**
- Modify: `pilot/flutter_phone_loop/pubspec.yaml`
- Modify: `pilot/flutter_phone_loop/test/r48_phone_acceptance_regression_test.dart`
- Create: `deliverables/PocketGallery-R4.8-PHONE-ACCEPTANCE-EVIDENCE.txt`
- Create: `deliverables/PocketGallery-R4.8-PHONE-ACCEPTANCE-arm64-update.apk.sha256`

**Interfaces:**
- Version: `0.4.17+18` or later, mapping to Android versionCode at least 2018.

- [ ] **Step 1: Add version RED assertion**

Assert build number is at least 18 while the branch still contains build 17. Run CI and confirm the expected single version failure.

- [ ] **Step 2: Bump version and run final CI**

Run both repository workflows at the same final HEAD. Require Flutter analyze, all tests, arm64 APK, package/version/ABI/signer checks, and artifact upload to succeed.

- [ ] **Step 3: Request independent code review**

Review the full R4.8 diff for false-positive gates, timeout cancellation hazards, checkpoint corruption, fixture leakage, upgrade regressions, and UI progress accuracy. Fix every Critical/Important item and rerun CI.

- [ ] **Step 4: Download and independently verify artifact**

Verify GitHub artifact digest, ZIP integrity, APK SHA-256 against the CI `.sha256`, native libraries equal only `arm64-v8a`, remote HEAD equals the reviewed commit, and local source blobs equal remote blobs.

- [ ] **Step 5: Produce evidence and deliver only final files**

Record RED/GREEN runs, test count, package, versionCode, signer, ABI, hashes, and the physical-phone boundary. Provide separate clickable links for APK, SHA-256, evidence, and ZIP only after every automated check is green.

## Plan self-review

- Spec coverage: state, timeout, dependency blocking, atomic persistence, runner integration, strict F7, live UI, documentation, version, CI, review, and artifact verification are each assigned to a task.
- Placeholder scan: no TBD/TODO/“implement later” instructions remain.
- Type consistency: Tasks 2–4 consume the state/executor interfaces defined in Task 1; Task 3 preserves `GoldenTestReport.results` compatibility while exposing the new snapshot used by Task 4.
