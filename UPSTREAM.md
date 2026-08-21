# PocketGallery Upstream Baseline

PocketGallery is an Android downstream distribution derived from Google AI Edge Gallery and extended with a local-first Knowledge Layer.

## Locked baseline

- Upstream repository: `google-ai-edge/gallery`
- Upstream commit: `ec7fee19e3b7aad9991105e549d544233ea0b97f`
- Baseline date: 2026-08-21
- Upstream license: Apache License 2.0

PocketGallery will preserve upstream copyright and license notices for derived files. Model weights are not part of this repository and remain subject to their respective model licenses and terms.

## Sync policy

PocketGallery-specific features should stay behind narrow adapters or inside dedicated `pocketgallery` packages whenever possible. Upstream updates are validated on an `upstream-sync/*` branch before integration into `main`.

Each upstream sync must record the old/new commit, API/runtime impact, conflicts, CI result, and device regression result.
