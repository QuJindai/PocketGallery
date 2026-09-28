# PocketGallery R4.8 Phone Acceptance Design

## Goal

Turn the existing Phone Golden Test into an observable, bounded, recoverable acceptance runner so an APK is delivered only after the repository, retrieval pipeline, upgrade contract, and release artifact pass deterministic automated gates. The installed app must then provide one decisive F1–F7 physical-device verdict for the real LiteRT/Gemma runtime.

## Current gaps

The R4.7 code and CI are green, but the phone acceptance experience is not yet release-grade:

- The settings page shows only an indeterminate spinner while F1–F7 run.
- The runner persists `PG_GOLDEN_LAST.json` only after the entire run finishes, so a hang or process death loses the last known step.
- One exception becomes a generic `RUNTIME_EXCEPTION`; there is no per-gate timeout, duration, status, or blocked reason.
- F7 passes when the second response is merely non-empty. It does not prove that late evidence survived budgeting, that the response cited valid evidence, or that the second real chat turn completed on a fresh native session.
- The README still describes the older R1/manual-model flow and only F1–F6.

## Release constraints

1. Keep Android package `com.qujindai.pocketgallery_phone_pilot.r3` and the canonical signing certificate unchanged.
2. Advance the Android build number from 2017 to at least 2018 for an in-place update.
3. Never clear or rename OAuth keys, model activation records, model files, knowledge databases, chat databases, or retrieval-trace databases.
4. Do not change the three model URLs or force a model redownload when an active model/embedder already exists.
5. Golden fixtures must be temporary and must not permanently alter the user's knowledge library.
6. FTS5 and Embedding gates must use their real stores. F6 and F7 must use `ChatOrchestrator` and `GemmaChatService`, not a fake success path.
7. No gate may be reported as passed after an exception, timeout, blocked dependency, or failed cleanup.
8. CI may prove the deterministic coordinator, storage, retrieval, package, signer, ABI, and artifact integrity. Only a physical phone can execute the final LiteRT/Gemma F6/F7 runtime; the UI must state that boundary explicitly.

## Architecture

### 1. Acceptance state model

Create a focused state model in `lib/services/golden_test_state.dart`:

- `GoldenRunPhase`: `preparing`, `running`, `cleaningUp`, `completed`.
- `GoldenGateStatus`: `pending`, `running`, `passed`, `failed`, `timedOut`, `blocked`.
- `GoldenGateSnapshot`: gate name, ordinal, status, detail, start/end timestamps, elapsed milliseconds, timeout seconds.
- `GoldenTestSnapshot`: run ID, phase, started/updated timestamps, current gate ordinal, total gates, integer percent, all gate snapshots, cleanup status, and overall pass.

Progress is monotonic. Percent starts at 0, advances only when a gate reaches a terminal state, and reaches 100 only after cleanup and final persistence. Overall pass requires all seven gates to be `passed` and cleanup to succeed.

### 2. Bounded gate executor

Create `lib/services/golden_gate_executor.dart`. It executes named async gate closures in order and owns state transitions, timing, timeout conversion, progress callbacks, and checkpoint calls.

Timeouts are explicit:

| Gate | Purpose | Timeout |
|---|---|---:|
| F1 | Import and chunk fixture | 45 s |
| F2 | FTS5 exact recall | 30 s |
| F3 | Embedding semantic recall | 90 s |
| F4 | Hybrid/rerank | 90 s |
| F5 | Evidence construction | 20 s |
| F6 | First real Gemma chat and citation | 240 s |
| F7 | Second-turn heavy-context real chat | 240 s |

F1 fixture-preparation failure blocks F1–F7 because the test corpus is unavailable. A normal failed or timed-out gate is recorded and the runner continues where doing so is safe, so one run collects the maximum useful evidence. F6 failure blocks F7 because F7 must reuse the same logical chat session. A model-gate timeout invokes the injected native-chat cleanup callback before the runner proceeds to final cleanup.

### 3. Atomic checkpoint store

Create `lib/services/golden_test_report_store.dart`. It writes every transition to `PG_GOLDEN_LAST.json` through a sibling temporary file followed by rename. A process death therefore leaves either the previous valid checkpoint or the new valid checkpoint, never partial JSON.

The JSON includes `schemaVersion: 2`, run/phase/progress fields, every gate status and duration, cleanup status, and the final `passed` value. The store accepts an injectable directory provider so CI tests can use a temporary directory.

### 4. Golden runner integration

Refactor `GoldenTestRunner` to express F1–F7 as gate closures consumed by the executor. Existing fixture preparation, real FTS5/Embedding stores, `ChatOrchestrator`, `GemmaChatService`, temporary chat database, and cleanup behavior remain.

The runner accepts optional progress and persistence collaborators for testing but production defaults to the real checkpoint store. It persists at run creation, before and after every gate, when entering cleanup, and at completion.

Cleanup is part of acceptance. It closes the real chat model, closes the temporary chat database, removes the fixture lease, and performs known-fixture cleanup. Any cleanup error is retained in the report and forces overall failure.

### 5. Strict F7 contract

The heavy-evidence retriever emits six evidence items from six distinct source identities. Each body starts with a unique sentinel, with the final item containing `PG_EVIDENCE_LAST_6`.

The second-turn prompt explicitly asks for that sentinel and its evidence citation. F7 passes only when:

- generation returns non-empty text;
- the text contains `PG_EVIDENCE_LAST_6`;
- resolved citations contain `E6`;
- every resolved citation belongs to the six supplied evidence items;
- the stored reply reports a knowledge retrieval mode rather than model-only fallback;
- no closed-session, timeout, or generation exception occurred.

This directly tests the R4.6/R4.7 failure class: later evidence must survive context budgeting and a second real turn must complete on a rebuilt native session.

### 6. Phone UI

Update the Advanced/Diagnostics section in `ModelSettingsPage` to show:

- determinate overall progress bar and percentage;
- current step such as `F3/7 · Embedding semantic recall`;
- completed/total count and elapsed time;
- one row per gate with pending/running/pass/fail/timeout/blocked icon and detail;
- checkpoint text confirming that progress has been saved;
- final `PHONE_FUNCTION_LOOP = PASS/FAIL` verdict;
- an explicit note that F6/F7 are the physical LiteRT/Gemma gates.

The run button remains disabled while a run is active. Navigating between app tabs must not restart the run because `IndexedStack` retains the page state.

### 7. Documentation and version

Update `pilot/flutter_phone_loop/README.md` to describe automatic model reuse, in-place upgrades, F1–F7, live progress, checkpoint location, timeout semantics, and the distinction between a chunk and its one-per-chunk vector observation. Bump the app to R4.8 with build number 2018 or greater.

## Testing strategy

Add `test/r48_phone_acceptance_regression_test.dart` with behavior-level tests for:

1. ordered state transitions and monotonic percentage;
2. timeout becoming `timedOut`, never `passed`;
3. F1 preparation failure blocking all gates;
4. F6 failure blocking F7;
5. atomic checkpoint JSON remaining valid after intermediate failure;
6. empty/tiny details and exception text remaining serializable;
7. strict F7 rejecting non-empty but uncited output;
8. strict F7 rejecting E1-only output that omits the final sentinel/E6;
9. strict F7 accepting only the sentinel plus valid E6 citation and knowledge retrieval mode;
10. UI contract exposing determinate progress, current gate, per-gate statuses, and persisted-checkpoint text;
11. R4.8 build number remaining an in-place update.

Run the full Flutter analyze/test suite, both GitHub workflows, arm64 APK build, package/version/ABI/signing verification, artifact ZIP integrity, independent APK hash comparison, and an independent code review. No APK link is presented until these automated gates are green.

## Acceptance criteria

- All existing and new Flutter tests pass with zero failures.
- Both GitHub workflows conclude `success` at the final branch HEAD.
- Final APK is `arm64-v8a`, package `com.qujindai.pocketgallery_phone_pilot.r3`, versionCode at least 2018, and signed by SHA-256 `81af4a5ef94c236774f0e193b2a4b248805b36c14cc36e2a56df8e451a712541`.
- APK and artifact ZIP hashes independently match CI.
- Independent review reports no Critical or Important findings.
- On a physical phone, one run exposes live F1–F7 progress, writes valid checkpoints, and reports PASS only if all seven gates and cleanup pass.

## Non-goals

- Changing models, model URLs, inference backend, or embedding backend.
- Adding OCR for image-only PDFs.
- Replacing the current one-vector-observation-per-chunk indexing strategy.
- Merging Draft PR #10 before physical F1–F7 evidence exists.
