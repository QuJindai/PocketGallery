# PocketGallery P0A Bootstrap & APK CI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a reproducible downstream pipeline that materializes the pinned Google AI Edge Gallery source, applies PocketGallery-owned overlay files, verifies the exact upstream commit, and produces a debug APK through GitHub Actions.

**Architecture:** The public PocketGallery repository remains a small downstream layer rather than a bulk copy of Google Gallery. `scripts/upstream/materialize.sh` clones the exact upstream commit into a disposable workspace; `scripts/overlay/apply.sh` copies PocketGallery overlay content into that workspace; `scripts/build/build_android_debug.sh` performs the blocking Android build. GitHub Actions runs the same scripts and uploads the APK, while pristine-upstream lint is collected separately as an informational report.

**Tech Stack:** Bash 5+, Git, Google AI Edge Gallery commit `ec7fee19e3b7aad9991105e549d544233ea0b97f`, Android Gradle Plugin 8.13.0, Kotlin 2.2.0, LiteRT-LM 0.11.0, JDK 21, Android SDK platform `37.0`, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-08-21-pocketgallery-a-route-design.md`

## Global Constraints

- Upstream repository: `https://github.com/google-ai-edge/gallery.git`.
- Locked upstream commit: `ec7fee19e3b7aad9991105e549d544233ea0b97f`.
- Android baseline: Android 12+ (`minSdk = 31`) inherited from Gallery 1.0.19.
- Upstream Android project root: `Android/src`.
- Do not commit model weights, Hugging Face tokens, OAuth secrets, business documents, signing keys, or generated APK binaries.
- Derived Google files retain Apache-2.0 notices; PocketGallery repository license is Apache-2.0.
- `main` must remain buildable; implementation work occurs on `feature/p0a-bootstrap-ci` and merges through PR after CI passes.
- CI must not require a real Gemma model or Hugging Face OAuth secret merely to compile the APK.
- Pristine Google upstream lint debt must be visible but must not be misrepresented as PocketGallery regressions.

## File Map

- `.upstream-version` — machine-readable upstream repository and commit.
- `UPSTREAM.md` — upstream provenance and sync policy.
- `LICENSE` / `NOTICE` — Apache-2.0 and downstream/model boundary.
- `README.md` — purpose, milestone and reproducible commands.
- `scripts/upstream/materialize.sh` — exact-commit materialization.
- `scripts/overlay/apply.sh` — deterministic PocketGallery overlay.
- `scripts/build/build_android_debug.sh` — one-command blocking build.
- `scripts/verify/test_materialize_upstream.sh` — materialization RED/GREEN test.
- `scripts/verify/test_apply_overlay.sh` — overlay RED/GREEN test.
- `scripts/verify/test_build_android_debug.sh` — orchestration RED/GREEN test.
- `overlay/Android/.keep` — overlay root.
- `.github/workflows/android-debug-apk.yml` — PR/push/manual APK CI and informational upstream lint.

## Task 1: Repository provenance and license baseline

Create `.upstream-version`, Apache-2.0 `LICENSE`, downstream `NOTICE`, README, `UPSTREAM.md`, approved design spec and this implementation plan. README must explicitly say P0A proves the reproducible Gallery baseline/APK path and does not yet claim the knowledge layer is implemented.

## Task 2: Exact upstream materialization, test first

Create `scripts/verify/test_materialize_upstream.sh` first. The test creates a temporary fake git repository with two commits, pins the first SHA, calls `scripts/upstream/materialize.sh`, and asserts the destination HEAD equals the pinned SHA, file contents come from that commit, and the checkout is clean. Run it before implementation and expect failure because the materializer is missing.

Then implement `scripts/upstream/materialize.sh <destination> [repo] [commit]`: source `.upstream-version`, clone `--filter=blob:none --no-checkout` when needed, refuse a dirty existing checkout, `fetch` the requested commit, detached-force checkout it, clean generated/untracked files, and fail unless `git rev-parse HEAD` exactly equals the requested commit. Re-run the test and require `PASS`.

## Task 3: Deterministic overlay application, test first

Create `scripts/verify/test_apply_overlay.sh` first. The fixture contains an upstream file and a PocketGallery overlay file; after invoking `scripts/overlay/apply.sh`, assert the upstream file remains and the overlay file is copied. Run RED before implementation.

Then implement `scripts/overlay/apply.sh <upstream-worktree> [overlay-dir]` using `cp -a "$OVERLAY_DIR"/. "$WORKTREE/Android/"`. Establish `overlay/Android/.keep`. Re-run and require `PASS`.

## Task 4: One-command Android build orchestration, test first

Create `scripts/verify/test_build_android_debug.sh` first. It injects a temporary Gallery-shaped worktree with a fake executable `Android/src/gradlew` that records its arguments and writes a fake `app-debug.apk`. Invoke the build with `POCKETGALLERY_WORKTREE=<fixture>` and `POCKETGALLERY_SKIP_MATERIALIZE=1`; assert Gradle receives exactly `--no-daemon testDebugUnitTest assembleDebug` and the expected APK exists.

This expectation was changed test-first after CI proved that the pristine pinned Gallery source currently contains upstream lint errors unrelated to PocketGallery. The changed test failed against the old implementation (RED), then the implementation was changed and all three script tests passed (GREEN).

Implement `scripts/build/build_android_debug.sh`: source `.upstream-version`; default worktree to `.work/gallery`; materialize unless `POCKETGALLERY_SKIP_MATERIALIZE=1`; apply overlay; `cd "$WORKTREE/$UPSTREAM_ANDROID_ROOT"`; run `./gradlew --no-daemon testDebugUnitTest assembleDebug`.

## Task 5: GitHub Actions APK artifact pipeline

Create `.github/workflows/android-debug-apk.yml` with `pull_request`, `push` to `main`, and `workflow_dispatch`. Use JDK 21 and Android SDK package `platforms;android-37.0`, matching the requirements observed from LiteRT-LM 0.11.0 and Google Gallery's own Android CI.

The blocking path is:

1. run all three downstream script tests;
2. materialize the pinned upstream;
3. run `testDebugUnitTest assembleDebug`;
4. assert `app-debug.apk` exists;
5. upload `PocketGallery-debug-apk` for 14 days.

Then run `lintDebug` against the pristine materialized upstream as an **informational, non-blocking** step and upload the lint report. Rationale: CI run 3 demonstrated that the exact Google baseline successfully compiles and executes `assembleDebug`, but its own `lintDebug` currently reports 9 errors and 150 warnings, beginning with `SuspiciousIndentation` in `BenchmarkViewModel.kt`. PocketGallery must not patch unrelated Google source merely to make the baseline green. Future PocketGallery-owned code will receive a separate strict lint-delta gate.

## Observed CI Debug Record

- Run 1: failed before build because `sdkmanager "platforms;android-37"` was not a valid package on the runner.
- Fix: align with Google upstream package `platforms;android-37.0`.
- Run 2: SDK and downstream tests passed; build failed because JDK 17 could not consume LiteRT-LM Java 21 bytecode (`class file version 65`, max 61).
- Fix: align with upstream JDK 21.
- Run 3: JDK 21, SDK 37.0, downstream tests, Kotlin/Java compilation, unit-test task and `assembleDebug` all succeeded; only pristine upstream `lintDebug` failed with 9 existing errors and 150 warnings.
- Fix: preserve upstream lint report as non-blocking evidence and keep APK build/test as the blocking baseline.

## P0A Exit Criteria

1. Public repository records the exact Google upstream commit and Apache provenance.
2. All three shell verification tests pass.
3. The pinned Gallery baseline compiles on JDK 21 / Android platform 37.0.
4. `testDebugUnitTest` and `assembleDebug` complete successfully.
5. GitHub Actions uploads an installable `PocketGallery-debug-apk` artifact.
6. Pristine upstream lint is captured as a report, not hidden or patched away.
7. No model weights, secrets, private knowledge files, signing keys, APKs or AABs exist in repository history.
8. The next milestone adds knowledge-layer code through `overlay/Android/...` plus narrow upstream patches only when unavoidable.
