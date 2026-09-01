# PocketGallery R4.6 B/C release checklist

The release is eligible for delivery only when all of these gates are satisfied
at the same final source commit:

1. `flutter analyze` reports no issues.
2. The complete Flutter regression suite passes, including all R4.6 B/C and R4.9 tests.
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
14. The APK version is `0.4.17+21` with Android versionCode `2021`.
15. Native libraries contain only `arm64-v8a`.
16. The APK signer certificate SHA-256 is exactly `81af4a5ef94c236774f0e193b2a4b248805b36c14cc36e2a56df8e451a712541` for an in-place upgrade build.
17. The downloaded APK digest matches its Actions-produced SHA-256 sidecar.

Automated release eligibility does not assert successful live-model execution,
thermal stability or Android in-place installation. Those remain explicit
physical-phone acceptance steps after the verified APK is delivered.
