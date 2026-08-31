# PocketGallery R4.6 B/C verification matrix

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
| Upgrade safety | Source tests pin package `com.qujindai.pocketgallery_phone_pilot.r3`, version `0.4.17+20`, arm64 ABI and canonical signer SHA-256 | Android performs an in-place upgrade over the currently installed R3/R4.x build |
| APK integrity | Actions verifies package, versionCode, arm64-only native libraries, signer certificate and APK SHA-256 | Installation and launch are confirmed on the target device |

`PHONE_FUNCTION_LOOP = PASS` is valid only after the bounded F1–F7 acceptance
runner completes on a physical phone with the real Gemma and EmbeddingGemma
models. CI does not manufacture that result.
