# PocketGallery R5.0 S24U Consolidated Handset Acceptance Design

## 1. Status and purpose

This specification extends the implemented R4.8 Phone Golden Test and R4.9
rotatable three-dimensional vector space. It defines the remaining
physical-phone merge gate for draft PR #14.

The feature provides one prominent in-app acceptance entry on the target
Galaxy S24 Ultra. One start action runs the existing F1-F10 functional loop,
collects real device evidence, guides the user through the production
three-dimensional vector interaction, verifies preservation invariants, and
produces one truthful PASS, FAIL, or BLOCKED verdict.

The acceptance runner must never translate an unavailable prerequisite,
unperformed user action, unsupported measurement, missing signing identity, or
first-run upgrade baseline into PASS.

## 2. Scope classification and selected approach

This is an architectural change because it adds a device diagnostics boundary,
an outer acceptance state machine, cross-version persistence evidence, report
contracts, and a release gate.

The selected approach is a layered handset acceptance orchestrator:

1. Keep GoldenTestRunner and its F1-F10 behavior intact.
2. Add an outer HandsetAcceptanceRunner with handset-specific gates.
3. Relay the nested F1-F10 progress into the consolidated UI and report.
4. Add a small first-party Android diagnostics bridge through the generated
   Android host.
5. Keep physical facts distinct from CI facts.

Rejected approaches:

- Expanding F1-F10 directly would couple reusable retrieval acceptance to one
  handset and force unnecessary migration of the stable Golden Test schema.
- An ADB, Termux, Shizuku, or external runner would provide additional system
  data but would not satisfy the in-app execution requirement.

No new three-dimensional, telemetry, sharing, or device-information package is
required. The design uses Flutter frame timings and Android platform APIs
already available to the application.

## 3. Non-negotiable release constraints

1. Target device is Samsung Galaxy S24 Ultra. Android model values matching
   SM-S928 followed by a regional suffix, including SM-S9280, are eligible.
2. Other devices may run diagnostics but cannot produce MERGE_READY.
3. Package identity remains
   com.qujindai.pocketgallery_phone_pilot.r3.
4. Canonical signer certificate SHA-256 remains
   81af4a5ef94c236774f0e193b2a4b248805b36c14cc36e2a56df8e451a712541.
5. Missing or mismatched canonical signing credentials fail closed.
6. Existing models, model activation records, OAuth records, user knowledge,
   chat history, retrieval observations, and lineage data must not be cleared
   or renamed.
7. The runner may add normal acceptance trace records and temporary fixtures.
   Temporary fixtures must be removed even after timeout or cancellation.
8. Raw OAuth tokens, authorization headers, raw embedding vectors, complete
   private documents, and unredacted exception stacks never enter an exported
   report.
9. CI cannot produce a physical-device PASS.
10. PR #14 remains Draft until automated evidence and the target-device report
    both satisfy the final merge rule.
11. The app cannot claim final MERGE_READY from device evidence alone. Final
    readiness is adjudicated only after same-commit CI evidence is correlated
    with the exported device report.

## 4. Architecture

### 4.1 HandsetAcceptanceRunner

HandsetAcceptanceRunner is the outer coordinator. It owns:

- a unique handset acceptance run ID;
- high-level phase and gate transitions;
- monotonic progress;
- cancellation and application-lifecycle handling;
- periodic checkpoint persistence;
- nested GoldenTestRunner progress;
- pre-run and post-run preservation snapshots;
- resource sampling across the complete run;
- final verdict aggregation.

The runner does not reproduce retrieval, model, PCA, or report-redaction
logic. Those responsibilities remain in their existing components or in the
new focused collaborators below.

### 4.2 DeviceDiagnosticsBridge

DeviceDiagnosticsBridge is an injectable Dart interface. Its Android
implementation uses a MethodChannel backed by a committed Kotlin host template
copied by scripts/bootstrap_android.sh into the generated Android scaffold.

The bridge returns:

- manufacturer, model, Android SDK level, display refresh rate;
- package name, version name, long version code;
- the installed APK signer certificate SHA-256;
- the installed APK file SHA-256 calculated from the app source path;
- process proportional set size in KiB;
- system available and total memory, low-memory flag, and low-memory threshold;
- Android PowerManager thermal status;
- battery temperature, explicitly labelled as battery rather than CPU or SoC
  temperature;
- support flags and reason codes for unavailable fields.

It also controls keep-screen-on only while an acceptance run is active.

These APIs require no Shizuku, root, Termux, location access, or new dangerous
Android permission. An unavailable value is represented as unavailable with a
reason; it is never replaced with zero.

The build also exposes an immutable sourceCommit compiled from
POCKETGALLERY_SOURCE_COMMIT. Canonical workflows set it to the 40-character
GitHub commit SHA through a Dart define. A missing or malformed source commit
is acceptable for local diagnostics but blocks release evidence.

### 4.3 FrameTimingSampler

FrameTimingSampler uses SchedulerBinding frame timing callbacks. Sampling runs
on the production three-dimensional vector page while a lightweight progress
animation keeps frame production observable.

It records:

- frame count;
- total-span P50, P95, P99, and maximum;
- count and ratio above 16.7 ms;
- count and ratio above 32 ms;
- observed display refresh rate;
- sample start, end, and duration.

The first ten frames are warm-up evidence and are excluded from threshold
aggregation but retained in the internal sample count.

The threshold window lasts at least 15 seconds and contains at least 180
post-warm-up frames. Completing the gestures early does not shorten that
window.

### 4.4 Three-dimensional interaction probe

The existing production InteractiveVectorPlot gains an optional acceptance
event sink. Normal application behavior remains unchanged when the sink is
absent.

The probe observes actual user input rather than synthetic widget gestures:

- single-pointer rotation must change yaw by at least 0.25 radians or pitch by
  at least 0.15 radians;
- a two-pointer scale gesture must change zoom by at least 12 percent;
- point selection must resolve to a real captured Query or Chunk point;
- the user must confirm that the legend, metrics, source text, and bottom
  control are visible without clipping.

The probe also records the real original embedding dimension, three PCA
coordinates, explained variance, Query embedding identity, Chunk identities,
REAL cosine values, captured ranks, and Evidence or drop reasons. It does not
recompute PCA during paint or gesture callbacks.

### 4.5 PreservationProbe

PreservationProbe captures private comparison snapshots and produces only
redacted summaries for reports.

The snapshot contains:

- package, version code, and signer identity;
- whether an active Gemma model and active EmbeddingGemma exist and can be
  opened without download;
- non-mutating OAuth credential-state flags and expiry classification, never
  token values;
- knowledge document identity digests, source SHA-256 values, and chunk counts;
- chat session identity digests and message counts;
- pre-existing retrieval observation and lineage identity digests and counts.

The OAuth service receives a non-mutating credential-state method. It reads
presence and expiry metadata but cannot refresh, clear, return, log, or export a
token.

Same-run preservation requires every pre-run user-owned object to remain
present with unchanged durable identity. New acceptance lineage is allowed.
Cross-version preservation requires the previous lower-version private
baseline to remain readable after installation and to be a subset of the
candidate state.

An empty user library is valid. The comparison verifies the objects that
actually existed rather than inventing a required document count.

### 4.6 Acceptance checkpoint and report store

HandsetAcceptanceStore follows the existing atomic temporary-file, validation,
rename, and backup pattern used by GoldenTestReportStore.

It stores:

- PG_HANDSET_ACCEPTANCE_LAST.json for the latest checkpoint;
- PG_HANDSET_BASELINE.json for the private cross-version baseline;
- a timestamped final redacted JSON report;
- a human-readable summary rendered in the UI and contained in the report.

The acceptance checkpoint and final report start at schemaVersion 1. The final
device summary exposes PHONE_FUNCTION_LOOP, DEVICE_ACCEPTANCE, and
MERGE_CANDIDATE as separate fields so a functional PASS cannot be mistaken for
complete release readiness.

Each evidence item contains:

- stable gate and reason codes;
- status;
- evidence method: MEASURED, OBSERVED, DERIVED, or USER_ACTION;
- source API or component;
- actual value, unit, and threshold where applicable;
- start, finish, and duration;
- availability and redacted detail.

The report exporter applies the existing sensitive-key philosophy and rejects
token, authorization, credential, secret, password, raw vector, and raw
document-content fields. The internal private baseline is not exportable.

### 4.7 ReleaseReadinessAdjudicator

A deterministic repository script performs the final non-device correlation.
It consumes:

- the exported redacted device report;
- PG_AUTOMATED_EVIDENCE.json produced by the canonical workflow;
- the candidate APK SHA-256 sidecar.

It requires matching source commit, package, versionCode, signer, and APK
digest; green automated gates; DEVICE_ACCEPTANCE = PASS; and
MERGE_CANDIDATE = true. It then writes PG_MERGE_READINESS.json with
MERGE_READY = true or false and stable reasons. The app never performs this
adjudication and does not upload the device report automatically.

## 5. State and verdict model

### 5.1 Run phases

The high-level phases are:

1. preparing;
2. runningAutomated;
3. awaitingInteraction;
4. runningPostChecks;
5. cleaningUp;
6. completed.

Every transition is checkpointed before the UI presents it.

Progress uses fixed weights so the long real-model block does not appear
stalled: H1 3 percent, H2 3, H3 4, H4 55, H5 5, H6 15, H7 5, H8 5, H9 3,
and H10 2. H4 maps the nested Golden Test percentage into its 55-percent
window. Progress reaches 100 only after final report persistence.

### 5.2 Gate statuses

The gate statuses are pending, running, passed, failed, timedOut, and blocked.
User cancellation, background interruption, missing user action, missing
baseline, unsupported evidence, and unmet prerequisite are blocked states with
specific reason codes rather than product failures.

### 5.3 Overall precedence

Overall verdict aggregation is deterministic:

1. Any failed or timedOut required gate, or failed cleanup, produces FAIL.
2. Otherwise, any blocked required gate produces BLOCKED.
3. Only all required gates passed with successful cleanup produces PASS.

MERGE_CANDIDATE additionally requires a PASS report from an eligible S24U, the
canonical signer, an actual lower-version baseline comparison, and a valid
source commit. MERGE_READY additionally requires the adjudicator to correlate
that report with green automated release evidence at the same source commit.

## 6. Consolidated gates

| Gate | Purpose | Pass condition |
| --- | --- | --- |
| H1_TARGET_DEVICE | Establish handset identity | Samsung model matches SM-S928 with any regional suffix |
| H2_BUILD_IDENTITY | Establish upgrade identity | Package and canonical signer match; installed APK digest and source commit are available; version code is 2022 for the helper or 2023 for the candidate |
| H3_UPGRADE_BASELINE | Load prior-version evidence | Valid private baseline exists with lower version code, same package, and same signer |
| H4_PHONE_FUNCTION_LOOP | Execute real application path | Nested F1-F10 and cleanup all pass |
| H5_VECTOR_3D_TRUTH | Verify high-dimensional evidence | Real dimension above three, real Query and Chunk identities, finite PCA coordinates, captured ranks and evidence reasons |
| H6_VECTOR_INTERACTION | Verify physical interaction | Rotation, zoom, point selection, viewport confirmation, and frame sample all complete |
| H7_RENDER_PERFORMANCE | Judge sustained rendering | At least 15 seconds and 180 post-warm-up frames, P95 at most 16.7 ms, and frames above 32 ms at most 1 percent |
| H8_MEMORY_THERMAL | Judge device resource state | No system low-memory state, available memory never below the Android threshold, post-cleanup PSS no more than 512 MiB above pre-run PSS, and maximum thermal status below SEVERE |
| H9_DATA_PRESERVATION | Verify non-destructive behavior | Same-run and prior-version preservation invariants pass |
| H10_REPORT_INTEGRITY | Finalize evidence | Redacted report validates, persists atomically, and contains no prohibited fields |

Battery temperature and peak PSS are reported as measured evidence but do not
have independent absolute pass thresholds. Android thermal status and memory
recovery are the release gates.

The memory baseline is sampled after package, device, model, and embedder
readiness probes complete and immediately before H4 starts. Resource sampling
then runs once per second through H9. This prevents model-readiness
initialization from being misclassified as a leak while still detecting
memory retained by the acceptance workload.

If no valid lower-version baseline exists, H3 is BLOCKED, all safe remaining
gates still run, and the run establishes a new private baseline. That run
cannot produce PASS or MERGE_CANDIDATE.

A missing-baseline run writes PG_HANDSET_BASELINE.json only when H1, H2, and
H4-H9 pass and cleanup succeeds. A cancelled, interrupted, failed, non-target,
or non-canonical run cannot replace a valid baseline.

## 7. Nested F1-F10 contract

H4 invokes the existing GoldenTestRunner and relays every nested checkpoint:

- F1 temporary import and chunking;
- F2 FTS5 exact recall;
- F3 Embedding semantic recall;
- F4 Hybrid and rerank;
- F5 Evidence construction;
- F6 real Gemma cited answer;
- F7 real heavy-evidence second turn;
- F8 ACTIVE runtime lineage;
- F9 Query vector identity;
- F10 context-budget conservation.

Existing F1-F10 timeout, dependency-blocking, strict citation, and cleanup
semantics remain authoritative. The outer runner stores the complete nested
snapshot and does not flatten blocked nested gates into a generic exception.
H5 uses the ACTIVE trace created by F6/F7 inside the same H4 run; it cannot
substitute an older successful trace.

## 8. User experience

### 8.1 Entry and preparation

ModelSettingsPage shows a prominent 手机一键验收 card above the existing
Advanced/Diagnostics expansion. The card displays the latest verdict, target
device status, baseline status, and one start button.

Missing models, model activation, or OAuth requirements produce BLOCKED with a
direct action into the existing model setup flow. Non-target devices can start
diagnostics after seeing that they are in diagnostic-only mode.

### 8.2 Live run

The full-screen acceptance page shows:

- determinate overall progress, percentage, current step, and elapsed time;
- high-level H1-H10 rows;
- expandable nested F1-F10 rows;
- live frame, PSS, available-memory, battery-temperature, and thermal-status
  values when available;
- checkpoint confirmation;
- a cancel action that performs cleanup.

The application keeps the screen on only for the run. The full-screen route
prevents accidental internal navigation. If the application leaves the
resumed lifecycle state during any active phase, the run stops safely,
performs cleanup, and produces BLOCKED with APP_BACKGROUND_INTERRUPTION.

### 8.3 Guided vector interaction

The runner opens the real captured three-dimensional vector view and shows
three task chips: 已旋转, 已缩放, and 已点选. Each chip completes only from the
corresponding observed production event.

After the three gestures and minimum frame sample are complete, the user
confirms that the full viewport is readable. Failure to complete within 90
seconds produces BLOCKED with USER_ACTION_INCOMPLETE, not FAIL.

### 8.4 Final result

The final screen uses:

- green PASS;
- red FAIL;
- amber BLOCKED.

Every gate shows the measured value, threshold, reason, and recommended next
action. Actions are limited to 查看证据, 导出脱敏报告, and 完整重跑. Selective
gate reruns cannot be combined into an overall verdict.

## 9. Error handling and recovery

| Condition | Result |
| --- | --- |
| Target model mismatch | BLOCKED: TARGET_DEVICE_MISMATCH |
| Canonical signer absent or mismatched | BLOCKED: CANONICAL_SIGNER_UNAVAILABLE |
| Previous baseline absent | BLOCKED: UPGRADE_BASELINE_MISSING, then establish baseline |
| Model or embedder unavailable | BLOCKED: MODEL_PREREQUISITE_MISSING |
| OAuth action required | BLOCKED: OAUTH_PREREQUISITE_MISSING |
| User action incomplete | BLOCKED: USER_ACTION_INCOMPLETE |
| App leaves the resumed state during an active run | BLOCKED: APP_BACKGROUND_INTERRUPTION |
| Canonical build source commit absent or malformed | BLOCKED: SOURCE_COMMIT_UNAVAILABLE |
| Installed APK digest unavailable | BLOCKED: APK_DIGEST_UNAVAILABLE |
| Unsupported required Android measurement | BLOCKED: REQUIRED_EVIDENCE_UNAVAILABLE |
| PCA, lineage, preservation, or report assertion false | FAIL with the specific gate reason |
| Render threshold exceeded | FAIL: RENDER_PERFORMANCE_REGRESSION |
| Android low-memory state or failed PSS recovery | FAIL: MEMORY_PRESSURE |
| Thermal status reaches SEVERE or above | FAIL: THERMAL_LIMIT_EXCEEDED |
| Required gate timeout | FAIL through timedOut status |
| User cancellation | BLOCKED: USER_CANCELLED after cleanup |

On startup, a checkpoint left in a nonterminal phase is converted to BLOCKED
with PROCESS_INTERRUPTED. Known temporary fixture cleanup runs before another
acceptance attempt. Cleanup failure is retained and forces FAIL.

Exceptions are mapped to stable reason codes. The internal checkpoint may keep
a sanitized diagnostic message; exported reports never contain an unreviewed
stack trace.

## 10. Upgrade artifact and signing design

R5.0 advances the candidate source version to 0.5.0+23. The arm64 split maps
build 23 to Android versionCode 2023.

The canonical workflow produces two same-source, same-signer artifacts:

1. baseline helper: version name 0.5.0, build 22, Android versionCode 2022;
2. candidate: version name 0.5.0, build 23, Android versionCode 2023.

Both artifacts contain identical product code; only the build number differs.
The baseline helper upgrades the current versionCode 2021 installation and
establishes PG_HANDSET_BASELINE.json. The candidate then performs the measured
2022-to-2023 in-place-upgrade comparison.

Both builds receive POCKETGALLERY_SOURCE_COMMIT equal to GITHUB_SHA. The
canonical workflow emits PG_AUTOMATED_EVIDENCE.json containing that source
commit, automated gate outcomes, package, both version codes, signer, candidate
APK digest, and workflow-run identity.

The signing workflow restores credentials in this order:

1. existing pocketgallery-r3-signing-v1 Actions cache;
2. explicitly provisioned GitHub Actions secrets
   POCKETGALLERY_SIGNING_KEYSTORE_B64,
   POCKETGALLERY_SIGNING_STORE_PASSWORD,
   POCKETGALLERY_SIGNING_KEY_PASSWORD, and
   POCKETGALLERY_SIGNING_KEY_ALIAS;
3. fail with SIGNING_IDENTITY_MISSING.

Secret fallback material is decoded only under RUNNER_TEMP, masked, certificate
checked against the pinned SHA-256, used for the job, and deleted by runner
teardown. The keystore is never committed, cached under a new identity,
uploaded as an artifact, or printed.

Adding the fallback path does not create signing authority. Until the owner
provisions the existing canonical keystore, signed artifact generation remains
BLOCKED. CI must never generate a replacement key.

## 11. Testing strategy

Implementation follows red-green-refactor. New tests are added before their
production behavior.

### 11.1 Unit tests

Unit tests cover:

- deterministic verdict precedence;
- state serialization and schema rejection;
- S24U regional model matching and non-target diagnostic mode;
- package, version, and signer checks;
- percentile and jank calculations, warm-up exclusion, and insufficient
  sample handling;
- memory recovery and thermal boundary values;
- interaction threshold accumulation;
- preservation subset comparisons and allowed new lineage;
- non-mutating OAuth credential-state probing;
- report allow-listing and prohibited-field rejection;
- final readiness adjudication rejecting any commit, signer, version, or APK
  digest mismatch;
- stale-run recovery and cleanup failure.

### 11.2 Widget tests

Widget tests cover:

- prominent one-tap entry and disabled duplicate start;
- live H1-H10 and nested F1-F10 progress;
- automatic rotation, zoom, and selection task chips;
- PASS, FAIL, and BLOCKED presentation with human-readable guidance;
- export action and complete-rerun behavior;
- 360 by 800 and representative S24U viewport sizes;
- light and dark themes and enlarged text;
- no RenderFlex or text overflow in all terminal states.

Synthetic widget gestures prove event wiring only. They are not reported as
physical-phone evidence.

### 11.3 Platform and build tests

Tests assert:

- the committed Kotlin host exposes the exact MethodChannel contract;
- scripts/bootstrap_android.sh installs the host into a fresh scaffold;
- Android compilation validates the Kotlin API usage;
- no new dangerous permission is added;
- the canonical workflow keeps the signer pin and fail-closed behavior;
- baseline and candidate APK package, versionCode, ABI, signer, and SHA-256
  sidecars are verified independently.
- the device report APK digest must equal the candidate APK sidecar during
  readiness adjudication.

### 11.4 Full regression

The complete Flutter suite, flutter analyze, both repository workflows, and
arm64 APK builds must pass at one source commit. Existing R4.8 and R4.9 tests
remain unchanged unless a version assertion is intentionally advanced to
R5.0.

## 12. Physical S24U acceptance procedure

1. Confirm the currently installed application is the canonical package and
   retains the user's active models and data.
2. Install the canonical baseline helper over versionCode 2021.
3. Launch it and run 手机一键验收. When all other gates pass, the expected
   remaining blocker is the absent prior structured baseline; the run
   establishes the versionCode 2022 baseline.
4. Install the canonical versionCode 2023 candidate without uninstalling.
5. Launch it and run 手机一键验收.
6. Complete physical rotation, zoom, point selection, and viewport
   confirmation.
7. Export the redacted report and verify H1-H10 PASS.
8. Confirm PHONE_FUNCTION_LOOP = PASS, DEVICE_ACCEPTANCE = PASS, and
   MERGE_CANDIDATE = true.
9. Correlate the device report with PG_AUTOMATED_EVIDENCE.json and the APK
   sidecar; only the adjudicator may output MERGE_READY = true.

An installation failure, model redownload, renewed OAuth requirement, missing
user data, high thermal state, performance regression, or incomplete evidence
prevents merge.

## 13. Merge decision

PR #14 may leave Draft only when PG_MERGE_READINESS.json reports
MERGE_READY = true and all of the following refer to the same final source
commit:

1. full automated suite and analysis pass;
2. candidate arm64 APK identity and SHA-256 are verified;
3. baseline and candidate use the canonical signer;
4. the S24U candidate report has H1-H10 PASS;
5. nested F1-F10 all pass;
6. cross-version preservation passes;
7. cleanup and report integrity pass;
8. no Critical or Important code-review findings remain.

If canonical credentials are unavailable, the truthful decision is
SIGNING_IDENTITY_MISSING and MERGE_READY = false even when all source tests are
green.

## 14. Non-goals

- Changing Gemma, EmbeddingGemma, model URLs, inference backends, retrieval
  algorithms, PCA mathematics, or the vector-space visual design.
- Adding Shizuku, root, Termux, ADB, an external benchmark service, or remote
  telemetry.
- Treating battery temperature as CPU or SoC temperature.
- Adding raw user content or embeddings to reports.
- Automatically merging PR #14.
- Manufacturing or rotating the canonical signing key.
