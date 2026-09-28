# PocketGallery R4.6-B/C Full Microscope + Retrieval Evolution Implementation Plan

> **Execution:** use `superpowers:executing-plans` in the isolated `codex/r46-full-microscope` worktree. Multi-agent execution is intentionally disabled for this delivery. Every behavior change follows RED → verify expected failure in GitHub Actions → GREEN → related regression pass → commit.

**Goal:** Complete the frozen R4.6-B/C design: a truthful, phone-usable ten-stage runtime-lineage microscope plus on-demand, isolated retrieval experiments whose real candidate and evidence effects can be inspected without changing the ACTIVE answer.

**Architecture:** Keep `active.r45-body-hybrid` as the answer-producing control lane. Add a trace snapshot/query layer above the additive lineage database, ten focused drill-down pages, a compact dashboard visualization layer, and an on-demand `RetrievalExperimentEngine`. Experiments reuse the exact captured query vector, generate only requested heading/sentence representations, checkpoint work in the existing lineage database, persist candidate/metric differences, and never write ACTIVE prompt/evidence/chat state. Benchmark cases are stored locally and are separate from packaged Golden fixtures.

**Tech stack:** Flutter/Dart, SQLite via `sqlite3`, existing FTS5 and R4.6 explicit vector index, EmbeddingGemma already installed on-device, CustomPainter for compact charts, GitHub Actions Android arm64 build/sign pipeline.

**Spec:** `docs/superpowers/specs/2026-08-29-pocketgallery-r46-runtime-lineage-retrieval-evolution-design.md`

## Global invariants

- Preserve Android application ID `com.qujindai.pocketgallery_phone_pilot.r3` and canonical signer SHA-256 `81af4a5ef94c236774f0e193b2a4b248805b36c14cc36e2a56df8e451a712541`.
- Deliver version `0.4.17+20` / Android versionCode `2020` or higher; never reduce the installed version.
- Do not redownload Gemma 4 or EmbeddingGemma during upgrade.
- Do not mutate or clear R4.5 lexical/vector/observability stores.
- No metric is labeled REAL unless captured by runtime. Derived rank motion, PCA, comparisons and percentages are labeled DERIVED.
- No fake UMAP/t-SNE, TTFT, output-token count, backend name, parse offset, citation confidence or shadow result.
- The exact ACTIVE query embedding stored for the trace is the only query vector accepted by trace-scoped vector-space and experiment services.
- SHADOW writes are strategy/lane scoped and may not update ACTIVE candidates, Evidence, prompt budget, generation, citations or chat messages.
- Extra heading/sentence embeddings are opt-in and bounded; sentence representations are capped at four per chunk.
- Existing 162-test baseline and all R2–R4.8 regression gates remain required.

## Task 1 — Enrich trace storage, source lineage, experiment persistence and safe export

**Files:**

- Modify: `pilot/flutter_phone_loop/lib/lineage/lineage_models.dart`
- Modify: `pilot/flutter_phone_loop/lib/lineage/lineage_ids.dart`
- Modify: `pilot/flutter_phone_loop/lib/lineage/lineage_store.dart`
- Modify: `pilot/flutter_phone_loop/lib/lineage/runtime_lineage_recorder.dart`
- Modify: `pilot/flutter_phone_loop/lib/retrieval/evidence_policy.dart`
- Modify: `pilot/flutter_phone_loop/lib/chat/chat_orchestrator.dart`
- Create: `pilot/flutter_phone_loop/lib/lineage/trace_snapshot.dart`
- Create: `pilot/flutter_phone_loop/lib/lineage/trace_report_exporter.dart`
- Test: `pilot/flutter_phone_loop/test/r46bc_lineage_enrichment_test.dart`
- Test: `pilot/flutter_phone_loop/test/r46bc_trace_report_test.dart`

**Interfaces and behavior:**

- Add `LineageStore.lineageChunkById`, `lineageSectionById`, lane/strategy-filtered candidate and Evidence readers, and CRUD for `ExperimentRunRecord`.
- Add `TraceSnapshot.load(store, traceId)` that resolves trace, events, candidates, router, Evidence, budget, generation, citations, exact query embedding, chunks, sections and documents once for all pages.
- Persist actual per-Evidence token allocations from the prompt context builder instead of a hard-coded zero.
- Resolve citation `sectionId`, `pageNo` and document identity from the cited chunk when those facts exist; unknown legacy values remain null.
- Add `TraceReportExporter.encodeRedacted(snapshot)` returning deterministic UTF-8 JSON containing IDs, metadata, stage timing, ranks and fingerprints, but no raw vectors, raw document/chunk text, OAuth values or model credentials.

- [ ] Write focused tests first. Named breaks:
  - deleting source joins makes a resolved citation lose section/page and fails the test;
  - reverting Evidence token count to zero fails a non-empty evidence allocation assertion;
  - allowing a SHADOW query to return ACTIVE rows fails lane isolation;
  - adding `vector_f32`, source text, bearer/device tokens or authorization fields to export fails redaction.
- [ ] Push RED-only commit and verify the workflow fails for missing behavior, not syntax/setup.
- [ ] Implement the minimum storage/query/recorder changes and `TraceSnapshot`.
- [ ] Implement deterministic redacted report encoding.
- [ ] Push GREEN commit; require focused tests and the complete suite to pass.

## Task 2 — Make the RAG Lineage dashboard the truthful responsive entry point

**Files:**

- Modify: `pilot/flutter_phone_loop/lib/ui/main_shell.dart`
- Modify: `pilot/flutter_phone_loop/lib/ui/knowledge_page.dart`
- Rewrite: `pilot/flutter_phone_loop/lib/ui/microscope/rag_lineage_dashboard_page.dart`
- Create: `pilot/flutter_phone_loop/lib/ui/microscope/lineage_dashboard_visuals.dart`
- Create: `pilot/flutter_phone_loop/lib/ui/microscope/trace_actions.dart`
- Test: `pilot/flutter_phone_loop/test/r46bc_dashboard_test.dart`
- Test: `pilot/flutter_phone_loop/test/r46bc_trace_actions_test.dart`

**Interfaces and behavior:**

- Pass `ChatOrchestrator` into Knowledge/RAG Lineage so “rerun” creates a real diagnostic chat turn with the original mode/scope and loads the newly created trace.
- Render `TraceHeaderCard`, horizontally scrollable ten-stage strip, stacked phone summary cards, timing waterfall, lineage graph, ACTIVE-vs-SHADOW summary and trace actions.
- Stage taps navigate to real detail pages through an explicit `RagStage` descriptor; no disabled prototype buttons remain.
- Actions: refresh, copy Trace ID, rerun as a new trace, compare with another historical trace, and save a redacted local JSON report with a share/save fallback supported by current dependencies.
- Waterfall durations come only from captured `durationUs`; absent duration renders “未捕获” and has no fabricated bar.
- Lineage graph derives edges from stored identities and clearly renders `Chunk → Embedding`, not equality.

- [ ] Write widget/service tests first. Named breaks:
  - replacing horizontal strip with a non-scrollable Column fails reachability on 360×800;
  - removing any stage route fails the ten-stage navigation test;
  - rerun that reuses the old trace ID fails real rerun contract;
  - giving a missing duration a zero-width REAL timing fails truthfulness test.
- [ ] Push and observe RED in Actions.
- [ ] Implement shell, visuals, actions and dependency wiring.
- [ ] Push GREEN; verify focused widgets plus the complete suite.

## Task 3 — Implement drill-down stages 1–5 and exact-vector sampling

**Files:**

- Create: `pilot/flutter_phone_loop/lib/ui/microscope/document_parse_microscope_page.dart`
- Create: `pilot/flutter_phone_loop/lib/ui/microscope/chunk_lineage_page.dart`
- Modify: `pilot/flutter_phone_loop/lib/ui/microscope/fts_inspector_page.dart`
- Create: `pilot/flutter_phone_loop/lib/ui/microscope/embedding_microscope_page.dart`
- Create: `pilot/flutter_phone_loop/lib/ui/microscope/vector_space_page.dart`
- Create: `pilot/flutter_phone_loop/lib/observability/trace_vector_space_service.dart`
- Modify: `pilot/flutter_phone_loop/lib/observability/vector_microscope_service.dart`
- Test: `pilot/flutter_phone_loop/test/r46bc_stage_1_5_test.dart`
- Test: `pilot/flutter_phone_loop/test/r46bc_trace_vector_space_test.dart`

**Interfaces and behavior:**

- Parse page shows exact/legacy provenance, file/SHA/type/size/page facts, extraction coverage and honest zero-chunk diagnostics.
- Chunk page shows document/section/chunk ancestry, text-object metrics, offsets when known, overlap, boundary reason and neighbors.
- FTS page is trace aware: raw/normalized query, expanded windows/terms when present, real raw BM25/rank/snippet and captured timing.
- Embedding page renders explicit chunk-to-one-or-many representation edges, ID/model/task/dimension/norm/fingerprint/duration and Generated/Persisted/Indexed states.
- `TraceVectorSpaceService` accepts a `TraceSnapshot`, loads the exact persisted query embedding by ID, never invokes the embedder, and orders its declared sample as: ACTIVE trace hits, selected SHADOW hits, deterministic document-stratified fill.
- Vector page displays real top neighbors/cosines/gap and 2D/3D PCA as DERIVED with sample coverage. UMAP/t-SNE stay disabled and explicitly say unavailable.

- [ ] Write tests first. Named breaks:
  - any embedder call during trace-space build fails exact-query-vector identity;
  - dropping a trace candidate from a capped sample fails candidate-priority;
  - returning the first database rows rather than stratified rows fails fixture ordering;
  - hiding legacy unknown offsets as zero fails provenance truthfulness.
- [ ] Push RED and confirm expected failures.
- [ ] Implement stages 1–5 and the trace-vector service.
- [ ] Push GREEN and run all regression tests.

## Task 4 — Implement drill-down stages 6–10 and forward/backward decision lineage

**Files:**

- Create: `pilot/flutter_phone_loop/lib/ui/microscope/candidate_pool_page.dart`
- Create: `pilot/flutter_phone_loop/lib/ui/microscope/rank_trajectory_page.dart`
- Create: `pilot/flutter_phone_loop/lib/ui/microscope/router_decision_page.dart`
- Create: `pilot/flutter_phone_loop/lib/ui/microscope/evidence_context_page.dart`
- Create: `pilot/flutter_phone_loop/lib/ui/microscope/generation_citation_page.dart`
- Create: `pilot/flutter_phone_loop/lib/ui/microscope/rank_trajectory_painter.dart`
- Test: `pilot/flutter_phone_loop/test/r46bc_stage_6_10_test.dart`
- Test: `pilot/flutter_phone_loop/test/r46bc_lineage_navigation_test.dart`

**Interfaces and behavior:**

- Candidate page shows FTS-only/vector-only/dual/parent-child counts, raw ranks/scores, representation origin, selection/truncation reason and a compact channel intersection view.
- Rank page shows FTS/vector → fusion → rerank → Evidence motion. Feature contribution rows appear only when persisted by a real experiment; otherwise state that reranking was not run.
- Router page shows actual inputs, captured thresholds/profile, PASS/FAIL gates, final mode and human-readable reason.
- Evidence page lists selected and dropped candidates, anchors/reasons, per-item tokens, source diversity, complete System/History/Evidence/Query/Reserve budget and trim details.
- Generation page shows only exposed generation metrics and citation chains `Citation → Evidence → Chunk → Section/Page → Document`, with missing/invalid diagnostics and answer preview only when locally available.

- [ ] Write tests first. Named breaks:
  - treating dropped candidates as absent fails the forward-lineage test;
  - flipping one router gate fails displayed PASS/FAIL fixture;
  - omitting output reserve or trimmed counts fails budget completeness;
  - stopping citation lineage at chunk fails backward navigation.
- [ ] Push RED and validate failure cause.
- [ ] Implement pages and route integration.
- [ ] Push GREEN and require full suite pass.

## Task 5 — Implement real, isolated on-demand SHADOW strategies

**Files:**

- Create: `pilot/flutter_phone_loop/lib/experiments/retrieval_strategy.dart`
- Create: `pilot/flutter_phone_loop/lib/experiments/retrieval_experiment_engine.dart`
- Create: `pilot/flutter_phone_loop/lib/experiments/representation_builder.dart`
- Create: `pilot/flutter_phone_loop/lib/experiments/feature_reranker.dart`
- Create: `pilot/flutter_phone_loop/lib/experiments/dynamic_evidence_policy.dart`
- Modify: `pilot/flutter_phone_loop/lib/lineage/lineage_models.dart`
- Modify: `pilot/flutter_phone_loop/lib/lineage/lineage_store.dart`
- Test: `pilot/flutter_phone_loop/test/r46c_strategy_descriptor_test.dart`
- Test: `pilot/flutter_phone_loop/test/r46c_shadow_isolation_test.dart`
- Test: `pilot/flutter_phone_loop/test/r46c_multivector_parent_child_test.dart`
- Test: `pilot/flutter_phone_loop/test/r46c_feature_reranker_test.dart`
- Test: `pilot/flutter_phone_loop/test/r46c_dynamic_evidence_test.dart`
- Test: `pilot/flutter_phone_loop/test/r46c_resumable_build_test.dart`

**Interfaces and behavior:**

- Define immutable descriptors for `active.r45-body-hybrid`, `shadow.heading-body-multivector`, `shadow.sentence-parent-child`, `rerank.features-v1`, `parent-child-v1`, and `evidence.dynamic-v1`.
- `RetrievalExperimentEngine.run(traceId, strategyId)` snapshots the trace, creates an `ExperimentRunRecord`, uses the captured query vector, updates progress, persists strategy/lane-scoped outputs, and completes or fails independently.
- Heading/body: embed a real non-empty stored section heading at most once per heading/source identity; combine representation hits and collapse them to the parent chunk while preserving the triggering embedding ID/type.
- Sentence parent-child: split real stored chunk text deterministically, keep meaningful spans, cap at four per chunk, embed incrementally, and return parent chunks while retaining child-span provenance.
- Feature reranker contributions are individually persisted: normalized lexical affinity, cosine, dual-channel agreement, query-window coverage, heading/exact-term match and source diversity. Literal fixture scores in tests are hand-calculated.
- Dynamic Evidence selects 1–3 normal-Q&A chunks within the supplied token reserve, penalizes near-neighbor duplicates, prefers source diversity when close, and records selected/dropped reasons.
- Build jobs checkpoint after each representation, resume missing items only, expose failure details and never mark READY from row counts alone.

- [ ] Write all strategy and isolation tests before production files.
- [ ] Push RED; confirm missing strategy behavior is the failure.
- [ ] Implement descriptors, builders, engine, reranker, dynamic Evidence and checkpoints in the smallest increments.
- [ ] Push GREEN; require focused strategy tests, old retrieval tests and full suite.

## Task 6 — Implement Experiment Center and ACTIVE-vs-SHADOW inspection

**Files:**

- Create: `pilot/flutter_phone_loop/lib/ui/microscope/retrieval_experiment_center_page.dart`
- Create: `pilot/flutter_phone_loop/lib/ui/microscope/experiment_run_detail_page.dart`
- Modify: `pilot/flutter_phone_loop/lib/ui/microscope/rag_lineage_dashboard_page.dart`
- Modify: `pilot/flutter_phone_loop/lib/ui/knowledge_page.dart`
- Test: `pilot/flutter_phone_loop/test/r46c_experiment_center_test.dart`
- Test: `pilot/flutter_phone_loop/test/r46c_experiment_detail_test.dart`

**Interfaces and behavior:**

- Show ACTIVE control strategy, SHADOW descriptors, required representations, persisted build status/progress, last run/failure and run/resume actions.
- On-demand run is disabled without a completed trace or exact query embedding and explains why.
- Comparison table shows candidate additions/removals, rank deltas, Evidence differences and real/derived metrics per strategy; per-case detail links to candidate/rank/Evidence pages filtered by lane/strategy.
- Promotion card displays the frozen promotion gates but does not auto-promote or alter ACTIVE settings.
- A failed SHADOW run remains inspectable and never changes the selected chat answer.

- [ ] Write widget tests first for progress, disabled prerequisites, lane labels, per-case navigation and failure isolation.
- [ ] Push RED.
- [ ] Implement pages and dashboard/Knowledge entry points.
- [ ] Push GREEN and run all tests.

## Task 7 — Add persistent local-real-corpus benchmarks and per-case inspection

**Files:**

- Create: `pilot/flutter_phone_loop/lib/eval/local_benchmark_store.dart`
- Modify: `pilot/flutter_phone_loop/lib/eval/retrieval_benchmark.dart`
- Modify: `pilot/flutter_phone_loop/lib/eval/retrieval_evaluator.dart`
- Modify: `pilot/flutter_phone_loop/lib/ui/microscope/retrieval_benchmark_page.dart`
- Create: `pilot/flutter_phone_loop/lib/ui/microscope/benchmark_case_detail_page.dart`
- Test: `pilot/flutter_phone_loop/test/r46c_local_benchmark_store_test.dart`
- Test: `pilot/flutter_phone_loop/test/r46c_benchmark_case_detail_test.dart`

**Interfaces and behavior:**

- Persist `LocalBenchmarkCase` with question, expected document IDs, optional expected chunk IDs, tags, source trace and timestamps in a local additive SQLite table/store.
- Allow saving the current real trace as a case only after the user chooses at least one expected document/chunk; raw vectors are not copied.
- Dataset selector switches between packaged deterministic Golden and local real corpus.
- Preserve the temporary Golden fixture lease/cleanup behavior.
- Add Router Accuracy and Citation Grounding Rate only when expected/observed facts exist; unavailable denominators display unavailable, not zero.
- Every aggregate card links to per-case actual ranks, expected IDs, failures and candidate differences.

- [ ] Write persistence/evaluation/widget tests first, including restart durability and empty-denominator truthfulness.
- [ ] Push RED and verify.
- [ ] Implement store, evaluator extensions and UI.
- [ ] Push GREEN and run full suite.

## Task 8 — Release regression, versioning, CI, signed APK and recovery evidence

**Files:**

- Modify: `pilot/flutter_phone_loop/pubspec.yaml`
- Modify if required: `.github/workflows/pocketgallery-r46-tdd.yml`
- Modify if required: `.github/workflows/pocketgallery-phone-pilot-apk.yml`
- Modify: `docs/phone-pilot/verification-matrix.md`
- Modify: `docs/phone-pilot/release-checklist.md`
- Test: existing regression suite plus all new R4.6-B/C tests

- [ ] Run formatting/analyze/test through GitHub Actions and require a pristine result.
- [ ] Confirm all ten stage routes, trace actions, experiment isolation, checkpoint resume, local benchmark persistence, report redaction, upgrade invariants and no placeholder metrics through automated gates.
- [ ] Bump to `0.4.17+20` and verify manifest package/versionCode/versionName.
- [ ] Use `superpowers:verification-before-completion` before any completion claim.
- [ ] Use `superpowers:finishing-a-development-branch`; keep the feature PR reviewable and do not merge to `main` without explicit user direction.
- [ ] Trigger the canonical signed arm64 workflow. Verify APK signature certificate SHA-256, package name, versionCode, ABI contents and APK SHA-256.
- [ ] Download the Actions artifact, verify it extracts, place the signed APK plus checksum manifest in the deliverables directory, and provide the APK link and GitHub run/PR evidence.

## Definition of done for this delivery

The user receives a canonically signed arm64 APK only after:

1. All ten stages are reachable and populated from real trace/store data.
2. Waterfall, lineage graph, trace rerun/copy/compare/export and responsive phone navigation work.
3. Exact ACTIVE query-vector identity is preserved without recomputation.
4. Candidate forward lineage and citation backward lineage are inspectable.
5. Heading/body, sentence parent-child, feature reranker and dynamic Evidence run as real on-demand SHADOW experiments.
6. SHADOW isolation and resumable representation build are proven by tests.
7. Built-in and persistent local-real-corpus benchmarks expose per-case results.
8. The complete regression suite and Android build pass in Actions.
9. Package, version, ABI and canonical signer are independently verified.

Physical-phone performance/thermal acceptance remains environment-dependent; the APK and automated Golden contracts must not claim `PHONE_FUNCTION_LOOP = PASS` without an actual device run.
