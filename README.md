# PocketGallery

PocketGallery is a local-first Android knowledge assistant built as a downstream extension of Google AI Edge Gallery. The runtime/model/session foundation follows Google AI Edge Gallery and LiteRT-LM; PocketGallery-specific work is concentrated in the local Knowledge Layer: document intake, parsing, indexing, retrieval, evidence-grounded RAG and Markdown export.

## Current milestone: P0A

P0A establishes the reproducible downstream build path only:

1. materialize the exact pinned Google AI Edge Gallery commit;
2. apply PocketGallery-owned overlay files;
3. run verification tests;
4. build a debug APK in GitHub Actions;
5. publish the APK as a workflow artifact.

P0A does **not** yet claim that the PocketGallery knowledge layer is implemented. Knowledge features begin after this baseline is green.

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

The default APK path is:

```text
.work/gallery/Android/src/app/build/outputs/apk/debug/app-debug.apk
```

The blocking baseline build runs `testDebugUnitTest assembleDebug`. The pinned pristine Google Gallery baseline currently has pre-existing `lintDebug` findings, so CI runs upstream lint separately as an informational report instead of patching unrelated Google source or blocking the APK artifact. PocketGallery-owned code will receive a strict lint-delta gate as the knowledge layer is added.

## Downstream structure

```text
overlay/Android/        PocketGallery additions/overrides copied onto the pinned upstream
scripts/upstream/       exact upstream materialization
scripts/overlay/        deterministic downstream overlay
scripts/build/          reproducible Android build entry points
scripts/verify/         fast script-level verification
docs/superpowers/       approved design and implementation plans
```

## Privacy and public-repository boundary

Do not commit real business documents, personal knowledge bases, model weights, Hugging Face tokens, OAuth secrets, signing keys, APK/AAB binaries or other private artifacts. Synthetic fixtures only.

After a user has imported a model and documents, the target PocketGallery knowledge/search/RAG path is designed to work offline.

## Licensing

PocketGallery source is released under Apache License 2.0. Derived Google files retain their upstream copyright/license notices. Gemma and other model weights are not distributed in this repository and remain governed by their own model licenses and terms.
