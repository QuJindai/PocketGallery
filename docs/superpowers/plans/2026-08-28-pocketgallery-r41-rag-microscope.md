# PocketGallery R4.1 RAG Microscope Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add real-data retrieval observability, vector visualization, chunk/index inspection and benchmark evaluation to the existing Chat-first PocketGallery without regressing the R4.0.3 phone loop.

**Architecture:** Keep existing retrieval behavior as the source of truth and add an additive observability/evaluation layer. Make document embeddings explicit at index-write time so the exact vectors can be persisted locally, instrument FTS/semantic/fusion stages into a `RetrievalTrace`, and render six microscope surfaces from those real values. All projections and aggregate metrics are labeled derived and are computed locally.

**Tech Stack:** Flutter/Dart, sqlite3, FlutterGemma/EmbeddingGemma, flutter_gemma_rag_sqlite, CustomPainter, local SQLite, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-08-28-pocketgallery-r41-rag-microscope-design.md`

## Global Constraints

- Keep Android applicationId `com.qujindai.pocketgallery_phone_pilot.r3`.
- Keep persistent R3 signing identity unchanged.
- Never redownload already-active Gemma/Embedding models.
- Preserve existing FTS5/vector/chat/OAuth/document data.
- Do not show synthetic production scores or coordinates.
- Keep trace candidates bounded to 20 and vector projection default <=250 points.
- R4.0.3 `PHONE_FUNCTION_LOOP = PASS` remains a regression gate.

---

### Task 1: Observability data contracts and local trace store

**Files:**
- Create: `pilot/flutter_phone_loop/lib/observability/retrieval_trace.dart`
- Create: `pilot/flutter_phone_loop/lib/observability/retrieval_trace_store.dart`
- Test: `pilot/flutter_phone_loop/test/r41_trace_store_test.dart`

**Interfaces:**
- Produces `RetrievalTrace`, `TraceHit`, `TraceStageTiming`, `RetrievalTraceStore.initialize()`, `save(trace)`, `latestForSession(sessionId)`, `get(traceId)`.

- [ ] Write failing tests that construct a trace containing raw BM25, cosine, lexical/semantic/final ranks, stage timings and evidence anchors, persist it to an in-memory sqlite3 DB, read it back and compare values.
- [ ] Run `flutter test test/r41_trace_store_test.dart` and verify RED because observability files do not exist.
- [ ] Implement normalized JSON/SQLite persistence with top-20 bounds and no production placeholder values.
- [ ] Run the focused test and verify PASS.
- [ ] Commit `feat: add local retrieval trace store`.

### Task 2: Exact vector observation persistence and runtime-safe explicit embedding writes

**Files:**
- Create: `pilot/flutter_phone_loop/lib/observability/vector_observation_store.dart`
- Modify: `pilot/flutter_phone_loop/lib/services/semantic_store.dart`
- Modify: `pilot/flutter_phone_loop/lib/services/knowledge_engine.dart`
- Test: `pilot/flutter_phone_loop/test/r41_vector_observation_test.dart`

**Interfaces:**
- Produces `VectorObservationStore.putChunkVector(...)`, `getChunkVector(chunkId)`, `listForDocuments(ids)`, `count()`.
- `SemanticStore.addChunks` explicitly generates document embeddings via active embedder and passes the same vector to both observation persistence and `FlutterGemma.rag.addDocumentWithEmbedding`.
- Produces `SemanticStore.observeQueryVector(query)` for microscope use.

- [ ] Write RED source/fixture tests requiring explicit `getActiveEmbedder`, `TaskType.retrievalDocument`, `addDocumentWithEmbedding`, Float32 BLOB encoding and vector norm.
- [ ] Verify RED.
- [ ] Implement Float32 little-endian encode/decode and observation metadata.
- [ ] Modify semantic indexing to use one explicit vector per chunk, while preserving runtime recovery and remove/clear behavior.
- [ ] Add query-vector observation using `TaskType.retrievalQuery` when supported by current API; otherwise use the plugin's default query task and document the exact call in metadata.
- [ ] Run focused and existing R4/R403 tests.
- [ ] Commit `feat: persist exact local embedding observations`.

### Task 3: FTS5 Inspector and CJK-aware query diagnostics

**Files:**
- Create: `pilot/flutter_phone_loop/lib/observability/fts_inspector.dart`
- Modify: `pilot/flutter_phone_loop/lib/services/lexical_fts_store.dart`
- Test: `pilot/flutter_phone_loop/test/r41_fts_inspector_test.dart`

**Interfaces:**
- Produces `FtsInspectionResult` with normalized query, `FtsInspectionHit` containing raw `bm25`, derived affinity, rank, document/chunk/locator, snippet and matched terms.
- Produces `LexicalFtsStore.inspect(query, scope, topK)`.

- [ ] Write RED tests for a two-CJK-character query such as `模型`, exact engineering identifier `31 03 51 01`, raw BM25 exposure and highlighted snippet.
- [ ] Verify RED.
- [ ] Refactor query normalization so 2-character CJK tokens survive while Latin tokens keep the existing >=3 heuristic.
- [ ] Use SQLite FTS5 `snippet()`/`highlight()` where available; retain a deterministic fallback for environments that reject those auxiliary calls.
- [ ] Run focused and existing FTS tests.
- [ ] Commit `feat: add FTS5 retrieval inspector`.

### Task 4: Retrieval instrumentation and Hybrid Rank decomposition

**Files:**
- Modify: `pilot/flutter_phone_loop/lib/core/hybrid_ranker.dart`
- Modify: `pilot/flutter_phone_loop/lib/services/knowledge_retriever.dart`
- Modify: `pilot/flutter_phone_loop/lib/chat/chat_orchestrator.dart`
- Create: `pilot/flutter_phone_loop/lib/observability/retrieval_trace_recorder.dart`
- Test: `pilot/flutter_phone_loop/test/r41_retrieval_trace_test.dart`

**Interfaces:**
- Extend `HybridHit` or companion breakdown value with lexical contribution, semantic contribution, dual-channel bonus, exact-term bonus and final score.
- `KnowledgeRetriever.retrieve` optionally accepts a recorder/trace context without changing callers that do not need observability.
- `ChatOrchestrator` saves completed knowledge traces keyed by chat session.

- [ ] Write RED tests with deterministic lexical+semantic fixtures and hand-computed RRF contributions.
- [ ] Verify RED.
- [ ] Refactor ranker to compute contribution breakdown once and preserve current final ordering exactly for old fixtures.
- [ ] Add Stopwatch timings for lexical, semantic, fusion and evidence stages.
- [ ] Persist final trace from chat orchestration; pure-model chat must not create a knowledge trace.
- [ ] Run focused tests plus all existing hybrid/chat tests.
- [ ] Commit `feat: trace hybrid retrieval decisions`.

### Task 5: PCA projector and Vector Microscope data service

**Files:**
- Create: `pilot/flutter_phone_loop/lib/observability/pca_projector.dart`
- Create: `pilot/flutter_phone_loop/lib/observability/vector_microscope_service.dart`
- Test: `pilot/flutter_phone_loop/test/r41_pca_projector_test.dart`

**Interfaces:**
- Produces deterministic `PcaProjection` with 2D/3D coordinates, component variance ratios and source IDs.
- Produces `VectorMicroscopeSnapshot` including query vector norm, neighbor cosine table and sampled document vectors.

- [ ] Write RED tests using a tiny hand-computable matrix for centering, deterministic component signs, orthogonality and stable coordinates.
- [ ] Verify RED.
- [ ] Implement centered power-iteration PCA without constructing a 768x768 covariance matrix; orthogonalize subsequent components.
- [ ] Add deterministic sampling capped at 250 points while retaining semantic Top-K neighbors.
- [ ] Compute cosine directly from stored REAL vectors for microscope display.
- [ ] Run focused tests.
- [ ] Commit `feat: add local PCA vector microscope`.

### Task 6: Chunk Explorer and Index Health

**Files:**
- Create: `pilot/flutter_phone_loop/lib/observability/index_health_service.dart`
- Modify: `pilot/flutter_phone_loop/lib/services/lexical_fts_store.dart`
- Modify: `pilot/flutter_phone_loop/lib/services/knowledge_engine.dart`
- Test: `pilot/flutter_phone_loop/test/r41_index_health_test.dart`

**Interfaces:**
- Produces `IndexHealthSnapshot` and `ChunkInspection`.
- Reports document/chunk/FTS/vector counts, zero-chunk docs, missing/stale vector observations, duplicate SHA groups and optional DB byte sizes.

- [ ] Write RED in-memory tests with one healthy doc, one zero-chunk doc, one duplicate SHA and one missing vector observation.
- [ ] Verify RED.
- [ ] Implement chunk inspection queries and health aggregation.
- [ ] Keep stale detection based on missing vector observation/model identity, never fabricated timestamps.
- [ ] Run focused tests.
- [ ] Commit `feat: add chunk and index health diagnostics`.

### Task 7: Retrieval benchmark and A/B evaluation engine

**Files:**
- Create: `pilot/flutter_phone_loop/lib/eval/retrieval_benchmark.dart`
- Create: `pilot/flutter_phone_loop/lib/eval/retrieval_evaluator.dart`
- Create: `pilot/flutter_phone_loop/assets/golden/rag_microscope_benchmark.json`
- Test: `pilot/flutter_phone_loop/test/r41_retrieval_evaluator_test.dart`

**Interfaces:**
- Produces benchmark cases, run configuration, per-case result and aggregate metrics: Hit@1, Hit@3, Recall@5, MRR, context precision proxy and optional citation accuracy.
- Supports FTS-only, Embedding-only, current Hybrid and alternate Hybrid config.

- [ ] Write RED tests with hand-computable rankings and exact expected metric values.
- [ ] Verify RED.
- [ ] Implement evaluator independent of UI and model generation.
- [ ] Add a small deterministic engineering benchmark fixture using the existing calibration/robot/network topics plus cross-language and two-character-CJK cases.
- [ ] Ensure no metric is returned as a fake percentage when zero cases ran.
- [ ] Run focused tests.
- [ ] Commit `feat: add local retrieval benchmark engine`.

### Task 8: Six RAG Microscope UI surfaces

**Files:**
- Create: `pilot/flutter_phone_loop/lib/ui/microscope/retrieval_trace_page.dart`
- Create: `pilot/flutter_phone_loop/lib/ui/microscope/fts_inspector_page.dart`
- Create: `pilot/flutter_phone_loop/lib/ui/microscope/vector_microscope_page.dart`
- Create: `pilot/flutter_phone_loop/lib/ui/microscope/hybrid_rank_lab_page.dart`
- Create: `pilot/flutter_phone_loop/lib/ui/microscope/chunk_explorer_page.dart`
- Create: `pilot/flutter_phone_loop/lib/ui/microscope/retrieval_benchmark_page.dart`
- Create: `pilot/flutter_phone_loop/lib/ui/microscope/vector_map_painter.dart`
- Modify: `pilot/flutter_phone_loop/lib/ui/chat_page.dart`
- Modify: `pilot/flutter_phone_loop/lib/ui/knowledge_page.dart`
- Modify: `pilot/flutter_phone_loop/lib/ui/main_shell.dart`
- Test: `pilot/flutter_phone_loop/test/r41_microscope_ui_test.dart`

**Interfaces:**
- Chat answer `检索依据` opens the trace overview.
- Trace stages deep-link to FTS/Vector/Hybrid detail.
- Knowledge page exposes Chunk Explorer/Index Health and Benchmark entry points.

- [ ] Write RED widget/source contract tests requiring six reachable surfaces, REAL/DERIVED labels, no hard-coded demo scores and disabled `UMAP/t-SNE 未启用` controls rather than fake plots.
- [ ] Verify RED.
- [ ] Implement high-density Material 3 pages matching the approved prototype.
- [ ] Render 2D PCA with CustomPainter; render 3D PCA through deterministic perspective projection of the third component.
- [ ] Add sortable rank tables, chunk cards, health counters and benchmark comparison table/sliders.
- [ ] Run focused widget tests and analyze.
- [ ] Commit `feat: add RAG Microscope UI`.

### Task 9: Version, upgrade regression and final APK gates

**Files:**
- Modify: `pilot/flutter_phone_loop/pubspec.yaml`
- Modify version-aware legacy tests only when their regex incorrectly rejects a valid forward version.
- Create: `pilot/flutter_phone_loop/test/r41_upgrade_contract_test.dart`

**Interfaces:**
- Version `0.4.10+11` (R4.1 family while remaining an in-place R3-signed Android upgrade).

- [ ] Write RED upgrade test for version, stable applicationId, no model redownload contract and additive DB behavior.
- [ ] Verify RED.
- [ ] Update version and forward-version legacy assertions without weakening package/signing requirements.
- [ ] Run `flutter analyze` and full `flutter test`.
- [ ] Push final HEAD and require Phone Pilot CI: analyze/test/build/package/ABI/signing/SHA/artifact all PASS.
- [ ] Require existing native Android regression workflow PASS.
- [ ] Download artifact and independently verify ZIP digest, APK sidecar digest and arm64 ABI.
- [ ] Commit only if final metadata changes are necessary; otherwise freeze HEAD.
