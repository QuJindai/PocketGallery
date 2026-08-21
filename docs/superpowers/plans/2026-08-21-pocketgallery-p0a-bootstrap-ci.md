# PocketGallery P0A Bootstrap & APK CI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reproducible downstream pipeline that materializes the pinned Google AI Edge Gallery source, applies PocketGallery-owned overlay files, verifies the exact upstream commit, and produces a debug APK through GitHub Actions.

**Architecture:** The public PocketGallery repository remains a small downstream layer rather than a bulk copy of Google Gallery. `scripts/upstream/materialize.sh` clones the exact upstream commit into a disposable workspace; `scripts/overlay/apply.sh` copies PocketGallery overlay content into that workspace; `scripts/build/build_android_debug.sh` performs the Android build. GitHub Actions runs the same scripts and uploads the APK, so local and CI builds use one path.

**Tech Stack:** Bash 5+, Git, Google AI Edge Gallery commit `ec7fee19e3b7aad9991105e549d544233ea0b97f`, Android Gradle Plugin 8.13.0, Kotlin 2.2.0, LiteRT-LM 0.11.0, JDK 17, Android SDK 37, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-08-21-pocketgallery-a-route-design.md`

## Global Constraints

- Upstream repository is `https://github.com/google-ai-edge/gallery.git`.
- Locked upstream commit is exactly `ec7fee19e3b7aad9991105e549d544233ea0b97f`.
- Android baseline is Android 12+ (`minSdk = 31`) inherited from Gallery 1.0.19.
- Upstream Android project root is `Android/src`.
- Do not commit model weights, Hugging Face tokens, OAuth secrets, business documents, signing keys, or generated APK binaries.
- Derived Google files retain Apache-2.0 notices; PocketGallery repository license is Apache-2.0.
- `main` must remain buildable; implementation work occurs on `feature/p0a-bootstrap-ci` and merges through PR after CI passes.
- CI must not require a real Gemma model or Hugging Face OAuth secret merely to compile the APK.

## File Map

- `.upstream-version` — machine-readable upstream repository and commit.
- `UPSTREAM.md` — upstream provenance and sync policy.
- `LICENSE` / `NOTICE` — Apache-2.0 and downstream/model boundary.
- `README.md` — purpose, milestone and reproducible commands.
- `scripts/upstream/materialize.sh` — exact-commit materialization.
- `scripts/overlay/apply.sh` — deterministic PocketGallery overlay.
- `scripts/build/build_android_debug.sh` — one-command build.
- `scripts/verify/test_materialize_upstream.sh` — materialization RED/GREEN test.
- `scripts/verify/test_apply_overlay.sh` — overlay RED/GREEN test.
- `scripts/verify/test_build_android_debug.sh` — orchestration RED/GREEN test.
- `overlay/Android/.keep` — overlay root.
- `.github/workflows/android-debug-apk.yml` — PR/push/manual APK CI.

### Task 1: Repository provenance and license baseline

Create `.upstream-version` exactly as:

```text
UPSTREAM_REPO=https://github.com/google-ai-edge/gallery.git
UPSTREAM_COMMIT=ec7fee19e3b7aad9991105e549d544233ea0b97f
UPSTREAM_ANDROID_ROOT=Android/src
```

Add Apache-2.0 `LICENSE`, downstream `NOTICE`, and a README that exposes these commands:

```bash
bash scripts/verify/test_materialize_upstream.sh
bash scripts/verify/test_apply_overlay.sh
bash scripts/verify/test_build_android_debug.sh
bash scripts/build/build_android_debug.sh
```

README must explicitly say P0A proves the reproducible Gallery baseline/APK path and does not yet claim the knowledge layer is implemented.

### Task 2: Exact upstream materialization, test first

Create `scripts/verify/test_materialize_upstream.sh` first. The test creates a temporary fake git repository with two commits, pins the first SHA, calls `scripts/upstream/materialize.sh`, and asserts the destination HEAD equals the pinned SHA, file contents come from that commit, and the checkout is clean. Run it before implementation and expect failure because the materializer is missing.

Then implement `scripts/upstream/materialize.sh <destination> [repo] [commit]`: source `.upstream-version`, clone `--filter=blob:none --no-checkout` when needed, refuse a dirty existing checkout, `fetch` the requested commit, detached-force checkout it, clean generated/untracked files, and fail unless `git rev-parse HEAD` exactly equals the requested commit. Re-run the test and require `PASS`.

### Task 3: Deterministic overlay application, test first

Create `scripts/verify/test_apply_overlay.sh` first. The fixture contains an upstream file and a PocketGallery overlay file; after invoking `scripts/overlay/apply.sh`, assert the upstream file remains and the overlay file is copied. Run RED before implementation.

Then implement `scripts/overlay/apply.sh <upstream-worktree> [overlay-dir]` using `cp -a "$OVERLAY_DIR"/. "$WORKTREE/Android/"`. Establish `overlay/Android/.keep`. Re-run and require `PASS`.

### Task 4: One-command Android build orchestration, test first

Create `scripts/verify/test_build_android_debug.sh` first. It injects a temporary Gallery-shaped worktree with a fake executable `Android/src/gradlew` that records its arguments and writes a fake `app-debug.apk`. Invoke the build with `POCKETGALLERY_WORKTREE=<fixture>` and `POCKETGALLERY_SKIP_MATERIALIZE=1`; assert Gradle receives exactly `--no-daemon testDebugUnitTest lintDebug assembleDebug` and the expected APK exists. Run RED before implementation.

Then implement `scripts/build/build_android_debug.sh`: source `.upstream-version`; default worktree to `.work/gallery`; materialize unless `POCKETGALLERY_SKIP_MATERIALIZE=1`; apply overlay; `cd "$WORKTREE/$UPSTREAM_ANDROID_ROOT"`; run `./gradlew --no-daemon testDebugUnitTest lintDebug assembleDebug`. Run all three verification scripts and require all to print `PASS`.

### Task 5: GitHub Actions APK artifact pipeline

Create `.github/workflows/android-debug-apk.yml` with `pull_request`, `push` to `main`, and `workflow_dispatch`. Use `actions/checkout@v4`, Temurin JDK 17, `android-actions/setup-android@v3`, install `platforms;android-37`, run all three script tests, run `scripts/build/build_android_debug.sh`, assert `.work/gallery/Android/src/app/build/outputs/apk/debug/app-debug.apk` exists, and upload it with `actions/upload-artifact@v4` as `PocketGallery-debug-apk` for 14 days.

Open PR `feature/p0a-bootstrap-ci` → `main` titled `P0A: reproducible Gallery baseline and APK CI`. Merge only after script tests, Gradle unit tests, lint, assemble and APK artifact all succeed. If upstream uses a different valid debug task name, inspect Gradle tasks and change only the task invocation while retaining unit/lint/assemble coverage.

## P0A Exit Criteria

1. Public repository records the exact Google upstream commit and Apache provenance.
2. All three shell verification tests pass.
3. A PR builds the pinned Gallery baseline through PocketGallery downstream scripts.
4. GitHub Actions uploads an installable debug APK artifact.
5. No model weights, secrets, private knowledge files, or signing keys exist in repository history.
6. The next milestone adds knowledge-layer code through `overlay/Android/...` plus narrow upstream patches only when unavoidable.
