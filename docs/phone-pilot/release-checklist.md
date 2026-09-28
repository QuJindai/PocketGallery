# PocketGallery R5.0 release checklist

The release is eligible for delivery only when all of these gates are satisfied
at the same final source commit:

1. `flutter analyze` reports no issues.
2. The complete Flutter regression suite passes, including R4.x regressions and all R5.0 acceptance/adjudicator tests.
3. All ten microscope stages are reachable from the compact phone summary.
4. Trace rerun, copy, compare and redacted report export are covered by tests.
5. ACTIVE query-vector identity and candidate/citation lineage are preserved.
6. SHADOW strategies are isolated, resumable and unable to mutate ACTIVE state.
7. Experiment Center failures remain inspectable and retryable.
8. Local benchmark cases survive SQLite restart and never copy raw vectors.
9. Unavailable Router Accuracy and Citation Grounding denominators remain unavailable rather than displaying zero.
10. The Trace vector plot uses the captured Query vector, real persisted corpus vectors and actual PCA explained variance.
11. Single-finger rotation, two-finger zoom, point selection, reset, readable source text and 360 px layout pass widget tests.
12. The fixed oblique z-offset painter is absent from both vector pages.
13. The APK package is `com.qujindai.pocketgallery_phone_pilot.r3`.
14. Source version is `0.5.0+23`; the canonical baseline helper has Android versionCode `2022` and the candidate has Android versionCode `2023`.
15. Native libraries contain only `arm64-v8a`.
16. The APK signer certificate SHA-256 is exactly `81af4a5ef94c236774f0e193b2a4b248805b36c14cc36e2a56df8e451a712541` for an in-place upgrade build.
17. The downloaded APK digest matches its Actions-produced SHA-256 sidecar.
18. Baseline and candidate embed the same checked-out 40-character source commit.
19. `PG_AUTOMATED_EVIDENCE.json` was emitted only after analysis, all tests, both builds, identity checks and sidecars passed.
20. The baseline was installed without uninstalling, ran H1–H10, and established the private versionCode `2022` baseline.
21. The candidate was installed over that baseline without uninstalling; no model redownload, OAuth renewal, or user-data loss occurred.
22. Candidate `PHONE_FUNCTION_LOOP = PASS`, `DEVICE_ACCEPTANCE = PASS`, `MERGE_CANDIDATE = true`, H1–H10 PASS and nested F1–F10 PASS.
23. The exported handset report contains no raw OAuth value, authorization header, raw vector, private document content or unreviewed stack trace.
24. The repository adjudicator correlates the handset report, `PG_AUTOMATED_EVIDENCE.json` and candidate sidecar into `PG_MERGE_READINESS.json`.
25. Only `PG_MERGE_READINESS.json` with `mergeReady: true` can move the release out of Draft.

Automated release eligibility does not assert successful live-model execution,
thermal stability or Android in-place installation. Those remain explicit
physical-phone acceptance steps after the verified APK is delivered. Follow
`r50-s24u-handset-acceptance-runbook.md`; CI alone cannot create device PASS.
