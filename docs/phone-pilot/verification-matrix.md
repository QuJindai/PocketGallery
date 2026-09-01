# PocketGallery R5.0 verification matrix

This matrix separates reproducible automated evidence from facts that require a
physical Android phone. Automated checks must never be presented as proof of
device performance or a successful live Gemma inference loop.

| Area | Automated release evidence | Physical-phone boundary |
| --- | --- | --- |
| Ten-stage RAG Lineage | Widget and store tests cover every stage route, persisted facts, waterfall, graph, rerun, compare and redacted export | Scroll, touch targets and OEM rendering are visually accepted on the target phone |
| ACTIVE retrieval | Tests prove the persisted query embedding is reused exactly and forward/backward lineage resolves | LiteRT model execution time, memory and thermals require the installed model on the phone |
| SHADOW experiments | Tests prove lane isolation, failure isolation, checkpoint resume, reranker contributions and dynamic Evidence selection | Long-running representation builds are observed under real battery and thermal conditions |
| Experiment Center | Widget tests cover progress, prerequisites, comparisons and candidate/rank/evidence drilldowns | User acceptance of the complete workflow is performed on the target phone |
| Local real benchmark | SQLite restart tests cover case durability; evaluator tests cover router/citation denominators and per-case inspection | The user selects expected documents/chunks from their own non-synthetic corpus |
| Rotatable 3D vector space | Pure-math and widget tests prove real yaw/pitch perspective, depth sorting, one-finger rotation, two-finger zoom, point selection, reset, finite degradation and 360 px layout | Physical touch feel and sustained rendering are accepted on the target phone |
| Human-readable vector evidence | SQLite integration and widget tests prove persisted chunk text, source, channel, ranks, Evidence/drop reason, real explained variance and exact captured Query identity | The user confirms that real-corpus labels and excerpts are useful on the target phone |
| Upgrade safety | Source tests pin package `com.qujindai.pocketgallery_phone_pilot.r3`, source version `0.5.0+23`, baseline/candidate versionCodes `2022`/`2023`, arm64 ABI and canonical signer SHA-256 | Android performs baseline then candidate in-place installs without uninstalling, model redownload, OAuth renewal or data loss |
| APK integrity | Actions verifies both APKs, both sidecars and emits `PG_AUTOMATED_EVIDENCE.json` only after all automated gates pass | Installation, launch and candidate APK identity are confirmed on the target device |
| Consolidated handset acceptance | Unit/widget tests cover H1–H10 state, recovery, evidence, redaction, lifecycle and deterministic precedence | The S24U runs H1–H10, including the nested F1–F10 real-model loop |
| High-dimensional interaction | Tests prove same-run high-dimensional identity, three-component PCA, real rotation/zoom/selection events and frame aggregation | The user physically rotates, pinches, selects and confirms the `768D → 3D` viewport |
| Resource envelope | Deterministic tests cover frame percentile, PSS growth, low-memory and thermal thresholds | Android APIs measure sustained frames, PSS, available memory, battery temperature and thermal status |
| Final correlation | Tests cover strict report parsing, all mismatch reasons and CLI exit codes | The exported device report is combined with `PG_AUTOMATED_EVIDENCE.json` and the candidate sidecar; only `PG_MERGE_READINESS.json` may say ready |

`PHONE_FUNCTION_LOOP = PASS` is valid only after the bounded F1–F10 acceptance
runner completes on a physical phone with the real Gemma and EmbeddingGemma
models. CI does not manufacture that result.
