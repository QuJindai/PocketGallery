# Historical branch workflows

These workflows were archived during the 2026-09-28 main integration. They
build pinned historical branches, investigate one-off signing caches, or
write patches/readback commits to development branches. They remain here as
verbatim evidence (with `.txt` suffixes), not executable GitHub workflows.

Current workflows:
- `android-debug-apk.yml`: native overlay unit/build and Room3/FTS5 emulator checks.
- `pocketgallery-r46-tdd.yml`: checked-out Flutter source integrity, analyzer,
  full regression suite, signer-guard tests and non-canonical arm64 debug build.
- `pocketgallery-phone-pilot-apk.yml`: manual protected canonical signing;
  requires the existing signing secrets and refuses missing/mismatched keys.

No signing identity is generated, rotated or copied by this integration.
