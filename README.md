# PocketGallery

PocketGallery is a local-first Android knowledge assistant built as a downstream extension of Google AI Edge Gallery. The runtime/model/session foundation follows Google AI Edge Gallery and LiteRT-LM; PocketGallery-specific work is concentrated in the local Knowledge Layer: document intake, parsing, indexing, retrieval, evidence-grounded RAG and Markdown export.

## Current milestone: P0B

P0B establishes the first independently tested local Knowledge Core on top of the reproducible P0A downstream build path.

P0B currently proves:

1. deterministic UTF-8 TXT normalization, including BOM removal and line-ending normalization;
2. deterministic Markdown normalization with heading-derived section identity;
3. SHA-256 document deduplication before persistence;
4. deterministic paragraph-aware chunking with stable ordinal/offset metadata;
5. Room3 3.0.1 persistence using `BundledSQLiteDriver` 2.7.0;
6. local FTS5 retrieval plus a safe short-query LIKE fallback;
7. Android API-35 instrumentation smoke coverage for the real database runtime, including Chinese and English retrieval;
8. unit tests, AndroidTest APK compilation, debug APK compilation and APK artifact upload in GitHub Actions.

P0B intentionally does **not** claim PDF parsing, Android SAF import UI, Evidence/RAG prompting, knowledge Q&A UI, source cards, embeddings/vector search or Markdown answer export. Those begin in later milestones.

## Upstream baseline

- Repository: `google-ai-edge/gallery`
- Commit: `ec7fee19e3b7aad9991105e549d544233ea0b97f`
- Gallery version at baseline: 1.0.19
- Android project: `Android/src`
- LiteRT-LM: 0.11.0
- CI/runtime build JDK: 21
- Android platform package: `platforms;android-37.0`

See [`UPSTREAM.md`](UPSTREAM.md) and [`.upstream-version`](.upstream-version).

## Verify build scripts

```bash
bash scripts/verify/test_materialize_upstream.sh
bash scripts/verify/test_apply_overlay.sh
bash scripts/verify/test_build_android_debug.sh
```

## Build debug APK

Requires Git, JDK 21, Android SDK platform 37.0 and network access to the public Google upstream and Maven repositories.

```bash
bash scripts/build/build_android_debug.sh
```

The build gate runs:

```text
testDebugUnitTest assembleDebug assembleDebugAndroidTest
```

The default APK path is:

```text
.work/gallery/Android/src/app/build/outputs/apk/debug/app-debug.apk
```

The pinned pristine Google Gallery baseline has pre-existing `lintDebug` findings, so CI keeps upstream lint as a separate informational report instead of patching unrelated Google source or blocking the PocketGallery APK artifact. PocketGallery-owned behavior is gated by compiler, unit and instrumented tests.

## Run the P0B Android database smoke test

The real Room3/FTS5 runtime acceptance test uses an Android API-35 x86_64 emulator:

```bash
bash scripts/verify/run_android_emulator_db_smoke.sh
```

The smoke runner uses an explicit `ANDROID_AVD_HOME`, verifies that the created AVD is visible to the emulator before launch, bounds the boot wait, uploads the emulator log in CI, and removes its temporary AVD state on exit. This prevents an AVD-home mismatch from degrading into a long blind wait.

## Downstream structure

```text
overlay/Android/        PocketGallery additions/overrides copied onto the pinned upstream
patches/upstream/       narrow tracked patches against the pinned Google baseline
scripts/upstream/       exact upstream materialization
scripts/overlay/        deterministic downstream overlay and patch application
scripts/build/          reproducible Android build entry points
scripts/verify/         script, unit-build and emulator runtime verification
docs/superpowers/       approved design and implementation plans
```

## Milestone boundary

- **P0B (current):** TXT/Markdown parsing, dedupe, chunking, Room3/BundledSQLite persistence and FTS5 retrieval.
- **P0C (next):** Android SAF document import, PDF parsing, and minimal “我的资料 / 搜索” UI.
- **P0D:** Evidence Pack, `LlmProvider` integration, knowledge Q&A, source cards and Markdown answer export.

Keeping these boundaries explicit lets parser/database/UI/RAG work be validated independently instead of making model runtime or emulator availability a prerequisite for every development step.

## Privacy and public-repository boundary

Do not commit real business documents, personal knowledge bases, model weights, Hugging Face tokens, OAuth secrets, signing keys, APK/AAB binaries or other private artifacts. Synthetic fixtures only.

After a user has imported a model and documents, the target PocketGallery knowledge/search/RAG path is designed to work offline.

## Licensing

PocketGallery source is released under Apache License 2.0. Derived Google files retain their upstream copyright/license notices. Gemma and other model weights are not distributed in this repository and remain governed by their own model licenses and terms.
