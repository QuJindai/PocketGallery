# PocketGallery R4.6 Runtime Lineage + Retrieval Evolution Design

- Status: **DESIGN FROZEN — awaiting user review before implementation planning**
- Date: 2026-08-29
- Baseline: `feature/phone-pilot-r41-rag-microscope@f79146cacf7d8013f17f1fcc9a47122e0f8e4738` (R4.5 retrieval-quality baseline)
- Development branch: `feature/phone-pilot-r46-runtime-lineage`
- Product scope: Android arm64 Phone Pilot, Flutter, on-device Gemma 4 + EmbeddingGemma + FTS5/RAG
- Approved direction: **B + C**
  - **B — Runtime Lineage Core:** capture the real RAG execution path rather than reconstructing it after the fact.
  - **C — Retrieval Evolution Lab:** add multi-vector, sentence-level, reranking, parent-child retrieval and dynamic evidence as isolated ACTIVE/SHADOW/EXPERIMENTAL strategies.

## 1. Problem statement

R4.1–R4.5 established a useful RAG microscope, index-health view and A/B benchmark, but the current observability model is not yet rigorous enough to answer the most important debugging question: **“What exactly happened in this real answer, and why?”**

The biggest conceptual defect is that the UI can make `Chunk` and `Vector` appear equivalent because the current body-vector observation table uses `chunk_id` as the primary key and the default indexing policy is one body embedding per chunk. That is an implementation cardinality, not an object identity.

The correct model is:

```text
Document
  -> Page / Section
    -> Chunk C137 (text object)
      -> Embedding V137-body (numeric representation)
      -> Embedding V137-heading (optional representation)
      -> Embedding V137-sentence-01 (optional representation)

Query Q42 (text object)
  -> Query Embedding VQ42 (numeric representation)

VQ42 + indexed document embeddings
  -> candidate pool
  -> fusion / rerank
  -> router
  -> evidence
  -> prompt context
  -> Gemma
  -> citation lineage back to Document/Page/Chunk
```

Therefore **Chunk != Vector**. R4.6 makes this separation explicit in schema, runtime APIs and UI.

A second defect is truthfulness: the current vector microscope can recalculate a query embedding after retrieval instead of guaranteeing that the displayed vector is the exact vector used by the search. Similarly, current vector-health coverage is based primarily on the observation store, which can theoretically diverge from the actual searchable vector backend if a multi-step write is interrupted.

R4.6 must turn the microscope from a collection of diagnostic pages into a **runtime lineage system**.

## 2. Goals

R4.6 SHALL:

1. Capture one end-to-end, immutable lineage record for every knowledge-enabled chat turn.
2. Make `Document`, `Section`, `Chunk`, `Embedding`, `Candidate`, `Evidence`, `Prompt Budget`, `Generation`, and `Citation` distinct first-class objects.
3. Generate the ACTIVE query embedding exactly once and use that exact vector for both vector search and trace capture.
4. Distinguish vector generation from persistence, index commit and searchable-index health.
5. Explain Auto routing with captured values and explicit rule outcomes.
6. Explain candidate movement from FTS/Vector ranks through fusion/rerank to Evidence.
7. Show the exact evidence and context-budget decisions that shaped the final Gemma prompt.
8. Preserve the R4.5 production path as a safe baseline while experiments run in isolated lanes.
9. Support one chunk producing multiple representations without changing the identity of the chunk itself.
10. Add local, on-device experiment capabilities without requiring a new external model download.
11. Preserve all upgrade, OAuth, model-cache, knowledge-base, chat-history and signing guarantees established through R4.5.
12. Remain usable on a phone while preserving the dense information architecture of the approved R4.6 visual prototype.

## 3. Non-goals

R4.6 SHALL NOT:

- Replace EmbeddingGemma as the production embedding model.
- Require a new cross-encoder/reranker model download.
- Introduce cloud inference or upload private documents by default.
- Rebuild every existing healthy body embedding on upgrade.
- Delete or destructively migrate the R4.5 FTS/vector/chat databases.
- Make SHADOW experiments delay the normal chat answer by default.
- Enable UMAP/t-SNE with fabricated or placeholder coordinates.
- Claim a projected vector-space plot is semantic ground truth.
- Promote an experimental strategy to default ACTIVE automatically without regression gates.

A model-based cross-encoder reranker can be a later version. R4.6's first lightweight reranker is a local feature reranker using already-available retrieval signals.

## 4. Upgrade invariants

The following are hard invariants:

- Android `applicationId` remains `com.qujindai.pocketgallery_phone_pilot.r3`.
- Canonical signing certificate remains unchanged.
- R4.6 uses a monotonically higher `versionCode` than R4.5.
- Installed Gemma 4 and EmbeddingGemma assets are reused; no upgrade-triggered model redownload.
- OAuth tokens/pending authorization state remain preserved during an in-place upgrade.
- Existing chat sessions and knowledge documents remain readable.
- Existing R4.5 FTS5 database remains the lexical source of truth until an explicitly tested migration replaces it.
- Existing R4.5 vector/observation stores remain intact during the R4.6 migration.
- All R2–R4.5 regression tests remain gates.
- No experiment can mutate ACTIVE answer selection unless its lane is explicitly `EXPERIMENTAL` and selected by the user.

## 5. Two orthogonal labels: truth and execution lane

R4.6 SHALL not mix the concepts of “truthfulness” and “experiment status”. Every displayed datum has two independent dimensions.

### 5.1 Truth kind

- `REAL`: captured directly from the ACTIVE or experiment runtime.
- `DERIVED`: deterministically computed from REAL values (for example RRF contribution, PCA coordinate, quality metric).

No production screen may label a reconstructed value as REAL.

### 5.2 Execution lane

- `ACTIVE`: the strategy that actually determines the answer.
- `SHADOW`: a strategy run only for comparison; it cannot change evidence or the answer.
- `EXPERIMENTAL`: an explicitly user-selected alternative that is allowed to determine the answer for that turn/session.

Examples:

- ACTIVE + REAL: cosine returned from the vector search used for the answer.
- ACTIVE + DERIVED: RRF score used to fuse two ACTIVE ranks.
- SHADOW + REAL: cosine from a sentence-level shadow search.
- SHADOW + DERIVED: shadow MMR/diversity score.

## 6. Runtime architecture

### 6.1 High-level flow

```text
ChatOrchestrator
  -> RetrievalRuntime
      -> LineageRecorder.startTrace()
      -> Parse/Chunk lineage lookup
      -> FtsCandidateProvider
      -> QueryEmbeddingRuntime.generateOnce()
      -> ActiveVectorIndex.searchByEmbedding(queryVector)
      -> CandidatePoolBuilder
      -> FusionPolicy
      -> RerankPolicy
      -> RouterPolicy
      -> EvidencePolicy
      -> LineageRecorder.captureRetrievalDecision()
  -> ContextAssembler
      -> ContextBudgeter
      -> LineageRecorder.capturePromptBudget()
  -> GemmaChatService
      -> LineageRecorder.captureGeneration()
  -> CitationResolver
      -> LineageRecorder.captureCitationLineage()
  -> LineageRecorder.completeTrace()
```

### 6.2 The exact query-vector rule

The ACTIVE query embedding MUST be generated once per retrieval turn by `QueryEmbeddingRuntime`. The returned vector object contains:

- `embeddingId`
- model identity
- task mode used by the embedding runtime
- dimension
- norm
- vector fingerprint
- generation duration
- vector bytes/value in the local lineage store subject to retention policy

That exact vector is then passed to the vector-index adapter as `queryEmbedding`.

The vector backend SHALL expose a PocketGallery-owned interface similar to:

```dart
abstract interface class ActiveVectorIndex {
  Future<void> add(VectorIndexRecord record);
  Future<List<VectorSearchHit>> searchByEmbedding({
    required List<double> queryEmbedding,
    required int topK,
    required KnowledgeScope scope,
  });
  Future<VectorIndexHealth> health();
}
```

The implementation SHALL use the explicit `queryEmbedding` search capability exposed by the local `flutter_gemma_rag_sqlite` vector-store layer rather than calling a text-query helper that re-embeds internally. R4.6 owns the query embedding and therefore can prove that the vector displayed by the microscope is the vector used by retrieval.

The production R4.6 vector database file is `pocketgallery_vectors_v46.db`; the R4.5 vector DB remains untouched as a rollback source until R4.6 phone acceptance is complete.

### 6.3 Vector-index migration without re-embedding healthy chunks

R4.6 introduces a PocketGallery-managed ACTIVE vector index whose entries are keyed by `embedding_id`, not by `chunk_id`.

A “healthy existing body vector” means:

- observation row exists;
- model identity equals the active EmbeddingGemma identity;
- dimension is the expected active dimension;
- vector BLOB decodes successfully;
- norm is finite and non-zero.

Upgrade migration order:

1. Read existing chunks from the R4.5 lexical store.
2. Read existing healthy body vectors from `VectorObservationStore`.
3. Create R4.6 `pg_embeddings` body rows using those existing Float32 values.
4. Insert the same values into `pocketgallery_vectors_v46.db` with a new `embedding_id`.
5. Only generate embeddings for missing/stale/invalid body representations.
6. Checkpoint each successful insert.
7. Keep the old vector DB and observation DB unchanged for rollback until R4.6 is accepted.

This migration does **not** redownload EmbeddingGemma and does not recompute healthy body vectors.

### 6.4 Legacy-document lineage

PocketGallery does not currently retain every original imported source file. Exact page/section offsets cannot therefore be reconstructed for all existing documents.

Existing documents migrate with `provenance_quality = legacy`:

- document identity, source name, SHA and current chunk text are preserved;
- `section_id` is synthesized from existing locator/page metadata where possible;
- unavailable raw offsets are stored as NULL, never invented;
- the UI clearly labels legacy provenance;
- re-importing a source file is optional and upgrades lineage quality to `exact`.

New R4.6 imports record exact parse/section/chunk lineage from the start.

### 6.5 Cross-store consistency

R4.6 spans the existing lexical DB, the lineage DB and the new vector DB, so a single SQLite transaction cannot be assumed across all stores. Consistency is maintained with an explicit per-document build state rather than pretending the writes are atomic.

Document/index operations use the state sequence:

```text
prepared -> lexical_committed -> lineage_committed -> vector_committed -> ready
```

If the app is killed or a write fails, the build job remains incomplete and repair resumes from the last committed checkpoint. `ready` is never inferred from partial row counts.

## 7. Persistent data model

R4.6 adds `pocketgallery_lineage.db`. It is additive and independent from the current FTS/chat DBs.

### 7.1 `pg_lineage_documents`

```text
document_id TEXT PRIMARY KEY
source_name TEXT NOT NULL
sha256 TEXT NOT NULL
file_type TEXT NOT NULL
size_bytes INTEGER
page_count INTEGER
parse_status TEXT NOT NULL
parse_error_code TEXT
parse_error_detail TEXT
extracted_char_count INTEGER NOT NULL DEFAULT 0
empty_page_count INTEGER NOT NULL DEFAULT 0
provenance_quality TEXT NOT NULL     -- exact | legacy
imported_at TEXT NOT NULL
```

### 7.2 `pg_lineage_sections`

```text
section_id TEXT PRIMARY KEY
document_id TEXT NOT NULL
page_no INTEGER
heading TEXT
section_type TEXT NOT NULL           -- page | heading | paragraph-group | text
start_offset INTEGER
end_offset INTEGER
char_count INTEGER NOT NULL
parse_status TEXT NOT NULL
```

### 7.3 `pg_lineage_chunks`

This table is a lineage mirror/mapping, not a replacement for the current FTS chunk table in R4.6.

```text
chunk_id TEXT PRIMARY KEY
document_id TEXT NOT NULL
section_id TEXT
locator TEXT NOT NULL
ordinal INTEGER NOT NULL
start_offset INTEGER
end_offset INTEGER
char_count INTEGER NOT NULL
token_count INTEGER
overlap_from_previous INTEGER NOT NULL DEFAULT 0
chunk_strategy TEXT NOT NULL
boundary_reason TEXT
provenance_quality TEXT NOT NULL
```

### 7.4 `pg_embeddings`

This is the key identity correction. `embedding_id` is independent from `chunk_id`.

```text
embedding_id TEXT PRIMARY KEY
source_kind TEXT NOT NULL             -- chunk | query
source_id TEXT NOT NULL               -- chunk_id or query/turn identity
document_id TEXT
chunk_id TEXT
representation_type TEXT NOT NULL     -- body | heading | sentence | query
span_start INTEGER
span_end INTEGER
model_identity TEXT NOT NULL
task_mode TEXT NOT NULL
dimension INTEGER NOT NULL
norm REAL NOT NULL
vector_f32 BLOB NOT NULL
vector_sha256 TEXT NOT NULL
generation_ms INTEGER NOT NULL
generated_at TEXT NOT NULL
truth_kind TEXT NOT NULL DEFAULT 'REAL'
```

One chunk can therefore have:

```text
C137 -> E137-body
C137 -> E137-heading
C137 -> E137-sentence-01
C137 -> E137-sentence-02
```

A query is represented separately:

```text
Q-trace-42 -> EQ-trace-42
```

### 7.5 `pg_vector_index_entries`

```text
index_entry_id TEXT PRIMARY KEY
embedding_id TEXT NOT NULL
backend_id TEXT NOT NULL
strategy_id TEXT NOT NULL
lane TEXT NOT NULL                   -- ACTIVE | SHADOW | EXPERIMENTAL
commit_status TEXT NOT NULL          -- pending | committed | failed
committed_at TEXT
failure_code TEXT
failure_detail TEXT
```

The vector-health page SHALL no longer equate “embedding exists” with “searchable vector index is healthy”.

### 7.6 `pg_traces`

```text
trace_id TEXT PRIMARY KEY
session_id TEXT NOT NULL
turn_id TEXT NOT NULL
query_text TEXT NOT NULL
requested_mode TEXT NOT NULL
final_mode TEXT NOT NULL
scope_json TEXT NOT NULL
active_strategy_id TEXT NOT NULL
started_at TEXT NOT NULL
completed_at TEXT
status TEXT NOT NULL                 -- running | complete | failed
failure_stage TEXT
failure_code TEXT
```

### 7.7 `pg_trace_events`

Events are the canonical runtime audit stream.

```text
event_id TEXT PRIMARY KEY
trace_id TEXT NOT NULL
seq INTEGER NOT NULL
stage TEXT NOT NULL
kind TEXT NOT NULL
truth_kind TEXT NOT NULL             -- REAL | DERIVED
lane TEXT NOT NULL                    -- ACTIVE | SHADOW | EXPERIMENTAL
strategy_id TEXT NOT NULL
timestamp_us INTEGER NOT NULL
duration_us INTEGER
payload_json TEXT NOT NULL
UNIQUE(trace_id, seq)
```

### 7.8 `pg_candidates`

```text
candidate_id TEXT PRIMARY KEY
trace_id TEXT NOT NULL
strategy_id TEXT NOT NULL
lane TEXT NOT NULL
chunk_id TEXT NOT NULL
embedding_id TEXT
source_channels TEXT NOT NULL         -- fts5 | vector | fts5+vector | parent-child
fts_rank INTEGER
raw_bm25 REAL
vector_rank INTEGER
raw_cosine REAL
fusion_rank INTEGER
fusion_score REAL
rerank_rank INTEGER
rerank_score REAL
final_rank INTEGER
selected_for_evidence INTEGER NOT NULL DEFAULT 0
drop_reason TEXT
```

### 7.9 `pg_router_decisions`

Router decisions can exist for ACTIVE and comparison strategies, so identity is strategy-scoped rather than trace-scoped.

```text
decision_id TEXT PRIMARY KEY
trace_id TEXT NOT NULL
strategy_id TEXT NOT NULL
lane TEXT NOT NULL
fts_hit_count INTEGER NOT NULL
top1_cosine REAL
top2_cosine REAL
top1_top2_gap REAL
dual_channel INTEGER NOT NULL
lexical_gate_pass INTEGER NOT NULL
semantic_strength_gate_pass INTEGER NOT NULL
semantic_gap_gate_pass INTEGER NOT NULL
final_use_knowledge INTEGER NOT NULL
rule_profile TEXT NOT NULL
decision_reason TEXT NOT NULL
UNIQUE(trace_id, strategy_id, lane)
```

### 7.10 `pg_evidence`

Evidence selection can also be evaluated in SHADOW without affecting the answer.

```text
evidence_id TEXT PRIMARY KEY
trace_id TEXT NOT NULL
strategy_id TEXT NOT NULL
lane TEXT NOT NULL
anchor TEXT
candidate_id TEXT NOT NULL
chunk_id TEXT NOT NULL
selection_rank INTEGER NOT NULL
score REAL NOT NULL
token_count INTEGER NOT NULL
selection_reason TEXT NOT NULL
```

For ACTIVE/EXPERIMENTAL answer-producing lanes, `anchor` is `E1..En`. SHADOW evidence can omit an answer anchor while still recording the selection set. Dropped candidates remain in `pg_candidates` with `drop_reason`; they are not silently discarded from lineage.

### 7.11 `pg_prompt_budgets`

Only the lane that actually produces the answer owns the prompt budget for a trace.

```text
trace_id TEXT PRIMARY KEY
strategy_id TEXT NOT NULL
lane TEXT NOT NULL
model_context_limit INTEGER NOT NULL
system_tokens INTEGER NOT NULL
history_tokens INTEGER NOT NULL
evidence_tokens INTEGER NOT NULL
query_tokens INTEGER NOT NULL
output_reserve_tokens INTEGER NOT NULL
total_prefill_tokens INTEGER NOT NULL
remaining_tokens INTEGER NOT NULL
trimmed_history_messages INTEGER NOT NULL
trimmed_evidence_items INTEGER NOT NULL
trim_detail_json TEXT NOT NULL
```

### 7.12 `pg_generation_stats`

```text
trace_id TEXT PRIMARY KEY
strategy_id TEXT NOT NULL
lane TEXT NOT NULL
ttft_ms INTEGER
generation_ms INTEGER NOT NULL
output_tokens INTEGER
decode_tokens_per_second REAL
backend TEXT
native_session_rebuilt INTEGER NOT NULL
session_reset_reason TEXT
```

### 7.13 `pg_citations`

```text
citation_id TEXT PRIMARY KEY
trace_id TEXT NOT NULL
anchor TEXT NOT NULL
evidence_id TEXT
chunk_id TEXT
document_id TEXT
section_id TEXT
page_no INTEGER
citation_status TEXT NOT NULL          -- resolved | missing | invalid
```

### 7.14 `pg_experiment_runs`

```text
experiment_run_id TEXT PRIMARY KEY
trace_id TEXT NOT NULL
strategy_id TEXT NOT NULL
lane TEXT NOT NULL
status TEXT NOT NULL
started_at TEXT NOT NULL
completed_at TEXT
metric_json TEXT
failure_code TEXT
```

### 7.15 `pg_build_jobs`

This table provides resumable migration and experiment-vector construction.

```text
job_id TEXT PRIMARY KEY
job_type TEXT NOT NULL                 -- active-migration | heading-build | sentence-build
strategy_id TEXT NOT NULL
document_id TEXT
status TEXT NOT NULL                   -- pending | running | complete | failed | cancelled
total_items INTEGER NOT NULL
completed_items INTEGER NOT NULL
checkpoint_json TEXT NOT NULL
current_source TEXT
failure_code TEXT
failure_detail TEXT
created_at TEXT NOT NULL
updated_at TEXT NOT NULL
```

## 8. Trace event model

The event stream SHALL contain, at minimum, the following event kinds when applicable:

```text
trace.started
parse.summary
chunk.lineage_loaded
fts.query_normalized
fts.search_completed
embedding.query_started
embedding.query_completed
vector.search_completed
candidate.pool_built
fusion.completed
rerank.completed
router.evaluated
evidence.selected
context.budgeted
generation.started
generation.first_token
generation.completed
citation.resolved
shadow.started
shadow.completed
trace.completed
trace.failed
```

Rules:

1. Sequence numbers are monotonic inside a trace.
2. A failed trace is still persisted and inspectable.
3. Payloads contain IDs and bounded metadata, not fabricated scores.
4. Raw vectors are stored in `pg_embeddings`, not duplicated into every event payload.
5. Candidate lists are capped for persistence; the cap is recorded explicitly.
6. Timing uses monotonic elapsed time for durations and UTC timestamps for identity/audit.

Retention defaults:

- 200 completed traces.
- 50 persisted candidates per channel/strategy per trace.
- 500 trace events per trace.
- Query vectors and experimental vectors are deleted with the trace when retention evicts it unless they belong to the persistent knowledge index.
- No trace export happens automatically.

## 9. Vector health semantics

R4.6 SHALL replace the ambiguous single `Vector ✓` concept with a four-stage model:

1. **Generated** — embedding vector exists.
2. **Persisted** — vector is durably stored in `pg_embeddings`.
3. **Indexed** — vector backend add/commit succeeded for the relevant strategy/lane.
4. **Search Verified** — ACTIVE index health probe succeeds and logical/indexed counts match the representation set required by the current ACTIVE strategy.

A global `Vector READY` badge is allowed only when:

- every representation required by the current ACTIVE strategy is persisted (R4.6 baseline requires body representations);
- every required ACTIVE representation is committed to the ACTIVE vector index;
- active model identity matches the index model identity;
- vector backend initialization passes;
- search probe passes;
- no pending/failed required ACTIVE index entries remain.

SHADOW representation gaps never make the production index unhealthy; they appear separately under experiment health.

## 10. Retrieval Evolution Lab (C layer)

### 10.1 Strategy descriptor

Every strategy is described by immutable runtime configuration:

```dart
class RetrievalStrategyDescriptor {
  final String id;
  final RetrievalLane lane;
  final Set<RepresentationType> representations;
  final CandidatePolicy candidatePolicy;
  final FusionPolicy fusionPolicy;
  final RerankPolicy rerankPolicy;
  final EvidencePolicy evidencePolicy;
  final ParentChildPolicy parentChildPolicy;
}
```

The ACTIVE descriptor is snapshotted into each trace. Changing settings later never changes historical traces.

### 10.2 Initial strategies

#### ACTIVE baseline

`active.r45-body-hybrid`

- body chunk embedding
- R4.5 CJK-aware FTS5
- body-vector cosine
- RRF/hybrid behavior compatible with R4.5
- R4.5 Auto routing thresholds/gap logic
- R4.5 conservative Evidence behavior

This strategy exists as the rollback/control lane.

#### SHADOW A — heading + body multi-vector

`shadow.heading-body-multivector`

- one body representation per chunk
- one heading representation when a real heading/section title exists
- representation-level candidate hits collapse to the parent chunk before Evidence
- the lineage UI shows which representation caused the chunk to enter the pool

#### SHADOW B — sentence-level parent-child

`shadow.sentence-parent-child`

- sentence spans are derived from a chunk without changing chunk identity
- only meaningful sentences are embedded
- hard limit: at most 4 sentence representations per chunk in R4.6
- sentence hit returns its parent chunk to the candidate pool
- sentence indexing is incremental/resumable and opt-in from the Experiment Center

#### SHADOW/EXPERIMENTAL C — Lightweight Feature Reranker

`rerank.features-v1`

No new model asset is required. It reranks the top fused candidates using captured features:

- normalized lexical affinity
- raw cosine
- dual-channel agreement
- query-term/character-window coverage
- heading/title match when available
- exact-term bonus
- source-diversity penalty/bonus

Every feature contribution is persisted so the reranker remains explainable.

#### SHADOW/EXPERIMENTAL D — Parent-child retrieval

`parent-child-v1`

- child representation can be sentence or heading
- the selected Evidence object remains a normal chunk
- the microscope records both child hit and parent promotion

#### ACTIVE-capable E — Dynamic Evidence

`evidence.dynamic-v1`

- 1–3 evidence chunks for normal Q&A by default
- total Evidence tokens must fit the ContextBudgeter reserve
- repeated/nearly identical chunks from the same local neighborhood are penalized
- source diversity is preferred when scores are sufficiently close
- corpus-summary intent uses a separate coverage policy and may keep more cross-document evidence under an explicit token budget

## 11. Shadow execution rules

SHADOW must not make normal chat slower by default.

Default behavior:

- ACTIVE path runs synchronously and produces the answer.
- SHADOW strategies are **on-demand** from the trace/Experiment Center.
- A user may enable a sampled background shadow mode later, but R4.6 does not enable it by default.
- Shadow uses the captured query embedding when its strategy is compatible with the same representation/model.
- Shadow can generate extra heading/sentence embeddings incrementally, with visible progress and checkpoints.
- Shadow writes only shadow candidate/metric rows; it cannot mutate ACTIVE evidence, chat message or citation records.

## 12. Promotion gate for experiments

No SHADOW/EXPERIMENTAL strategy becomes the default ACTIVE strategy automatically.

Promotion requires all of the following:

1. R2–R4.6 regression suite passes.
2. Built-in retrieval benchmark passes without a statistically obvious regression.
3. `Hit@1` and `MRR` are not worse than the current ACTIVE baseline by more than 0.02 absolute.
4. At least two quality dimensions improve (for example Context Precision, Router Accuracy, Citation Grounding, Recall@5).
5. Phone Golden Test passes.
6. In-place upgrade/package/signing/model-cache gates pass.
7. User explicitly approves promotion of the strategy.

An experiment may still be useful and remain SHADOW if it fails the promotion gate.

## 13. RAG Lineage microscope: 10 primary stages

The approved UI information architecture is a single runtime pipeline with drill-down, not a disconnected list of pages.

### Stage 1 — Document / Parse

Displays:

- file identity, SHA, type, size, page count
- per-page/section parse status
- extracted character count
- empty pages
- parse error code/detail
- exact vs legacy provenance
- parse duration for new imports
- reason for a 0-chunk result when known

For legacy zero-chunk documents whose source file is unavailable, the UI says `legacy · exact parse reason unavailable`; it does not invent a reason.

### Stage 2 — Section / Chunk

Displays:

- Document -> Page/Section -> Chunk lineage
- chunk text
- character count and token estimate/count
- start/end offsets when exact
- overlap
- boundary reason
- chunk strategy
- adjacent chunk relationship

`Chunk` is presented as a text object, never as a vector.

### Stage 3 — FTS5

Displays:

- raw query
- normalized query
- CJK window/term expansion
- hit counts per query term/window where available
- raw SQLite BM25
- rank
- highlighted snippet
- lexical timing
- no-hit explanation

### Stage 4 — Embedding

Displays:

- explicit `Chunk -> Embedding` edges
- representation type (`body`, `heading`, `sentence`)
- embedding ID distinct from chunk ID
- model identity
- task mode
- dimension
- norm
- generation duration
- vector fingerprint
- Generated/Persisted/Indexed states

This stage is the primary place where the UI teaches and proves `Chunk != Vector`.

### Stage 5 — Vector Space

Displays:

- the exact captured ACTIVE query embedding
- nearest neighbors and REAL cosine
- Top1 / Top2 / gap
- candidate representation type
- 2D/3D PCA derived from a declared sample
- sample policy and sample coverage
- ACTIVE vs SHADOW overlays when requested

PCA remains `DERIVED`; ordering truth remains the real search result.

Sampling policy SHALL prioritize:

1. ACTIVE candidate hits for this trace.
2. Shadow candidate hits currently being compared.
3. Additional deterministic stratified samples across documents.

It SHALL not simply take the first 250 rows by database ordering.

### Stage 6 — Candidate Pool

Displays a merged candidate table and Venn/summary counts:

- FTS-only
- Vector-only
- dual-channel
- parent-child promoted
- representation that caused entry
- raw ranks/scores
- why a candidate was kept or truncated

### Stage 7 — Fusion / Rerank

Displays candidate rank motion:

```text
FTS #8 ----\
            -> Fusion #2 -> Rerank #1 -> Evidence E1
Vector #1 -/
```

For each candidate:

- FTS rank/BM25
- vector rank/cosine
- fusion score/contributions
- rerank features/contributions
- final rank
- rank delta

A Sankey/rank-trajectory view is `DERIVED` from the captured ranks.

### Stage 8 — Auto Router

Displays the actual decision table:

- FTS hit count
- Top1 cosine
- Top2 cosine
- gap
- dual-channel status
- rule thresholds/profile
- PASS/FAIL for each rule
- final `Auto -> Knowledge` or `Auto -> Model`
- human-readable decision reason

### Stage 9 — Evidence + Context Budget

Displays:

- candidate -> selected Evidence mapping
- selected and dropped candidates
- selection/drop reason
- Evidence anchor
- token count per Evidence item
- source coverage/diversity
- System / History / Evidence / Query / Output Reserve token budget
- total prefill budget and remaining capacity
- which history/evidence items were trimmed

The user must be able to understand why E1/E2/E3 were included and why E4/E5 were not.

### Stage 10 — Gemma + Citation

Displays:

- generation duration
- TTFT when runtime supports capturing it
- output tokens when runtime supports capturing it
- decode tok/s when token timing/count is available
- backend
- native session rebuilt/reset reason
- citation resolution
- `Citation -> Evidence -> Chunk -> Section/Page -> Document` lineage
- missing/invalid citation diagnostics

Unavailable runtime metrics display `not exposed by backend`; they are never estimated and labeled REAL.

## 14. Page structure and responsive behavior

The approved prototype is dense. The phone implementation preserves density without copying a desktop dashboard literally.

### 14.1 Main product navigation

Existing three-tab product shell remains:

```text
Chat | Knowledge | Model / Settings
```

`Knowledge -> RAG Microscope` becomes the entry to `RAG Lineage`.

On wide/tablet layouts, a NavigationRail may expose the microscope subpages. On phone portrait, subpages use normal AppBar/back navigation.

### 14.2 `RagLineageDashboardPage`

Component tree:

```text
Scaffold
  AppBar(Trace picker, mode, total time, export-local-summary)
  TraceHeaderCard
  HorizontalStageStrip(10 stages)
  StageSummaryGrid
  WaterfallCard
  LineageGraphCard
  ActiveVsShadowSummaryCard
  TraceActionsCard
```

Phone behavior:

- 10-stage strip scrolls horizontally.
- summary cards stack vertically.
- metric groups use dense 2–4 column Wrap grids.
- landscape/tablet uses two-pane detail when space permits.

### 14.3 `DocumentParseMicroscopePage`

```text
DocumentIdentityCard
ParseCoverageCard
PageSectionList
ParseFailureDiagnosticCard
RawTextPreviewCard
```

### 14.4 `ChunkLineagePage`

```text
ChunkStrategyCard
DocumentSectionChunkGraph
ChunkMetricGrid
ChunkList
  ChunkDetailCard
  NeighborOverlapView
```

### 14.5 `FtsMicroscopePage`

```text
QueryNormalizationCard
TermWindowCard
TopKControl
FtsRankList
  Bm25BreakdownCard
  HighlightedSnippet
HistoricalTraceRankCard
```

### 14.6 `EmbeddingMicroscopePage`

```text
ChunkVsVectorExplanationCard
RepresentationSummaryCard
EmbeddingStateGrid
ChunkToEmbeddingLineageList
EmbeddingDetailCard
```

### 14.7 `VectorSpacePage`

```text
QueryEmbeddingCard
TopNeighborList
GapMetricCard
ProjectionControls
PcaProjectionCanvas
SamplePolicyCard
ActiveShadowOverlayLegend
```

### 14.8 `CandidatePoolPage`

```text
CandidateCountSummary
ChannelIntersectionView
CandidateTable
RepresentationOriginBadge
KeepDropReasonPanel
```

### 14.9 `RankTrajectoryPage`

```text
StrategyHeader
RankFlowVisualization
CandidateSelector
CandidateScoreBreakdown
FeatureContributionTable
TopKControl
```

### 14.10 `RouterDecisionPage`

```text
FinalDecisionHeroCard
RuleEvaluationTable
ThresholdProfileCard
CandidateConfidenceSummary
DecisionReasonCard
```

### 14.11 `EvidenceContextPage`

```text
EvidenceSelectionFlow
SelectedEvidenceCards
DroppedCandidateCards
ContextBudgetStackedBar
TokenBudgetTable
TrimmedContentPanel
```

### 14.12 `GenerationCitationPage`

```text
GenerationMetricGrid
CitationList
CitationLineageGraph
GroundingDiagnostics
AnswerPreview
```

### 14.13 `RetrievalExperimentCenterPage`

```text
ActiveStrategyCard
StrategyList
  LaneBadge
  RepresentationBadge
  BuildStatus
  RunShadowButton
ExperimentBuildProgress
MetricComparisonTable
PromotionGateCard
```

### 14.14 `RetrievalBenchmarkPage`

Retains built-in deterministic cases and adds dataset selection:

- Built-in Golden regression dataset.
- Local Real Corpus dataset.

A trace can be saved as a local real-corpus benchmark case by choosing expected document/chunk labels. This is optional and local only.

Per-case failures become inspectable; the UI SHALL no longer show only aggregate metrics.

## 15. Real-corpus benchmark model

`LocalBenchmarkCase` stores:

```text
case_id
question
expected_document_ids
expected_chunk_ids (optional)
tags
created_from_trace_id (optional)
created_at
```

Metrics:

- Hit@1
- Hit@3
- Recall@5
- MRR
- Context Precision
- Router Accuracy
- Citation Grounding Rate

The built-in Golden dataset remains a deterministic CI/phone regression gate. Local Real Corpus cases measure the user's actual knowledge-base behavior and are not packaged into the repository.

## 16. Import/parse improvements required by the microscope

R4.6 adds parse diagnostics without forcing OCR.

### TXT / MD

- record UTF-8 read success/failure
- record total chars
- Markdown heading detection creates real sections
- paragraph groups preserve heading ancestry

### PDF

- record page count
- record extracted chars per page
- classify page as `text`, `empty`, or `parse-failed`
- preserve page locator
- do not claim OCR support in R4.6

A scanned/image PDF with no text layer is shown as such when the parser returns no page text. OCR is a separate future capability.

## 17. Chunking evolution

The R4.5 fixed character chunker remains the ACTIVE compatibility strategy initially.

R4.6 records the missing metadata needed to compare chunk strategies:

- section ancestry
- token count
- boundary type/reason
- overlap
- start/end span

R4.6 may expose alternative chunk strategies in SHADOW indexing, but it does not silently re-chunk the production library on upgrade.

## 18. Error handling

### 18.1 Trace failure

If retrieval or generation fails:

- persist `trace.failed` with stage/code;
- keep all prior REAL events;
- show partial lineage rather than an empty/error-only page;
- never convert a failed stage into a fake zero metric.

### 18.2 Vector migration/index failure

- per-entry checkpointing
- retry only missing/failed entries
- old R4.5 vector data remains available for rollback
- no full clear before replacement index is healthy

### 18.3 Shadow failure

- never fail the ACTIVE answer
- persist experiment failure independently
- show `SHADOW FAILED` with cause

### 18.4 Storage pressure

- trace retention evicts oldest completed traces first
- persistent knowledge embeddings are never evicted by trace retention
- shadow representations can be deleted/rebuilt separately from ACTIVE body vectors

### 18.5 Import/build consistency failure

- `pg_build_jobs` preserves the last successful checkpoint;
- `ready` is never set if lexical, lineage or required ACTIVE vector commit is incomplete;
- restart reconciles build state against actual stores and resumes only missing work;
- a failed new import remains visible as a failed/incomplete build and never silently appears as a healthy document.

## 19. Test architecture

R4.6 follows RED-first TDD. New gates must cover behavior, not merely source-string presence wherever practical.

### 19.1 Identity and schema tests

- `Chunk` and `Embedding` IDs are distinct.
- one chunk can persist multiple embedding rows.
- query embedding exists without a chunk row.
- lineage schema migration is additive.
- R4.5 DBs remain readable/unchanged.

### 19.2 Exact query-vector tests

- query embedding generator is invoked exactly once for ACTIVE retrieval.
- exact returned vector is passed to vector search.
- trace references that embedding ID/fingerprint.
- microscope reads the captured embedding, not a newly generated value.

### 19.3 Vector health tests

- generated but unindexed != READY.
- persisted but failed commit != READY.
- stale model identity != READY.
- missing representation required by a promoted ACTIVE multi-vector strategy != READY.
- healthy committed index + probe => READY.
- SHADOW missing vectors do not fail ACTIVE health.

### 19.4 Candidate-lineage tests

- FTS-only candidate recorded correctly.
- vector-only candidate records embedding ID.
- dual-channel candidate merges without losing raw ranks.
- drop reason persists when Top-K truncates a candidate.
- parent-child promotion preserves child representation and parent chunk IDs.

### 19.5 Router tests

- rule inputs are captured.
- PASS/FAIL fields match the actual decision.
- weak semantic-only retrieval remains Auto -> Model.
- strong/gapped semantic result can become Auto -> Knowledge.
- dual-channel strong evidence remains accepted.
- ACTIVE and SHADOW router decisions can coexist for one trace without overwriting each other.

### 19.6 Evidence/context tests

- selected/dropped reasons are persisted.
- ordinary Q&A stays within dynamic evidence cap/token budget.
- corpus summary preserves cross-document coverage.
- ContextBudgeter reports System/History/Evidence/Query/Reserve counts.
- trimmed history/evidence is recorded.
- prefill budget cannot exceed the model limit.
- SHADOW evidence sets do not change ACTIVE prompt evidence.

### 19.7 Experiment isolation tests

- SHADOW cannot change answer evidence.
- SHADOW failure cannot fail ACTIVE answer.
- strategy config is snapshotted per trace.
- heading/body multi-vector collapses to parent chunk.
- sentence representation count is capped at 4 per chunk.
- experiment build is resumable.

### 19.8 UI contract tests

- all ten stages reachable from a trace.
- every score/metric badge uses correct REAL/DERIVED label.
- ACTIVE/SHADOW/EXPERIMENTAL lane is visible.
- Embedding page explicitly renders Chunk -> Embedding relationship.
- Router page shows why decision was made.
- Evidence page shows selected and dropped candidates.
- Context page shows token budget.
- Citation can navigate back to source chunk/section/document.

### 19.9 Regression gates

All existing gates remain, including:

- FTS5
- Embedding
- Hybrid/RRF
- Evidence/citation
- OAuth persistence
- no model redownload on upgrade
- fixed signing/in-place upgrade
- long-chat Prefill/session recovery
- missing-vector incremental repair
- Golden corpus cleanup
- R4.5 Chinese FTS/Auto routing

### 19.10 Phone Golden extension

R4.6 adds lineage checks after the existing real chat loop:

- `F8_RUNTIME_LINEAGE`: completed trace exists for the real chat turn.
- `F9_QUERY_VECTOR_IDENTITY`: captured query embedding is the same ID used by ACTIVE vector candidates.
- `F10_CONTEXT_BUDGET`: prompt budget is within model capacity.
- `F11_CITATION_LINEAGE`: cited anchor resolves to Evidence -> Chunk -> Document.

The Golden UI reports partial failures by stage; it never prints `PHONE_FUNCTION_LOOP = PASS` if any required stage fails.

## 20. Delivery phases

### R4.6-A — Runtime lineage foundation

Deliver:

- additive lineage DB and resumable build-state table
- IDs/schema/migrations
- exact one-time ACTIVE query embedding path
- PocketGallery-owned explicit vector-search adapter
- new `pocketgallery_vectors_v46.db`
- R4.5 body-vector migration from existing observation values
- event recorder
- Router decision capture
- Evidence/context-budget capture
- vector health four-state model
- first lineage dashboard shell

Acceptance:

- any knowledge-enabled chat creates a complete/failed inspectable trace
- query vector shown is exactly the ACTIVE search vector
- Chunk and Embedding identities are distinct
- no model redownload
- no full body re-embedding when healthy observation values exist
- interrupted migration/import resumes from checkpoints
- R4.5 functionality remains green

### R4.6-B — Full 10-stage microscope

Deliver:

- Parse page
- Chunk lineage page
- FTS page upgrade
- Embedding page
- Vector Space sample fix
- Candidate Pool page
- Rank trajectory page
- Router page
- Evidence/Context page
- Generation/Citation page
- Waterfall and lineage graph
- responsive phone layout matching approved visual hierarchy

Acceptance:

- answer can be traced backward to document/page/chunk
- a candidate can be traced forward from FTS/Vector into or out of Evidence
- every runtime stage exposes timing/status when available
- no post-hoc recomputation is labeled REAL

### R4.6-C — Retrieval Evolution Lab

Deliver:

- strategy/lane API
- heading+body multi-vector SHADOW
- sentence parent-child SHADOW
- feature reranker
- dynamic evidence policy
- experiment center
- ACTIVE vs SHADOW comparison
- built-in and local-real-corpus benchmark support

Acceptance:

- SHADOW never changes the normal answer
- extra representations build incrementally/resumably
- experiment metrics and candidate differences are inspectable per case
- default ACTIVE remains rollback-compatible with R4.5 until explicit promotion

## 21. UI acceptance checklist

The R4.6 UI is accepted only if:

1. On phone portrait, the user can reach all ten stages without desktop-only assumptions.
2. The main trace page shows a horizontal 10-stage strip, timing waterfall and lineage summary.
3. `Chunk -> Embedding` is visible as an edge, not implied equality.
4. Vector point count states its sample policy and does not masquerade as total-vector count.
5. Router decision includes actual values, thresholds and reason.
6. Evidence displays both selected and rejected candidates.
7. Context Budget exposes actual token allocation and trimming.
8. Citation resolves all the way back to the original document hierarchy where provenance is available.
9. SHADOW data is visually distinct from ACTIVE data.
10. No placeholder quality score, fake UMAP/t-SNE, fake TTFT, or fabricated runtime metric appears.

## 22. Performance constraints

Observability must not dominate retrieval.

Initial budgets:

- lineage event writes are batched or transactionally lightweight;
- ACTIVE trace capture adds no second embedding pass;
- candidate persistence caps prevent unbounded DB growth;
- PCA is on-demand only;
- SHADOW is on-demand by default;
- sentence/heading embedding builds expose progress, checkpoint and cancellation/resume;
- no full vector-space projection runs during ordinary chat.

Generation remains the dominant latency on current phone workloads; R4.6 must not add unnecessary synchronous experiment work to that path.

## 23. Privacy and export

- All lineage and experiment data stays local by default.
- Full raw document text is not exported automatically.
- “Export report” exports a user-triggered diagnostic bundle with explicit contents.
- Raw vectors are excluded from export by default; fingerprints/metadata are sufficient for most diagnostics.
- OAuth tokens and model authorization credentials are never written into lineage payloads.

## 24. Rollback

R4.6 remains reversible:

- R4.5 FTS/chat/model data are not destructively replaced.
- R4.6 lineage and `pocketgallery_vectors_v46.db` stores are separate.
- disabling R4.6 strategy runtime can return retrieval to the R4.5-compatible ACTIVE adapter while retaining lineage DB for diagnostics.
- experiments are independently removable without deleting production chunks or body embeddings.

## 25. Definition of done

R4.6 is not complete merely because screens render.

It is complete when:

1. The exact runtime lineage for a real knowledge answer is captured end-to-end.
2. The user can prove from the UI that Chunk and Vector are different objects.
3. The exact query vector used by ACTIVE search is inspectable without recomputation.
4. Vector health reflects actual ACTIVE index commit/probe state rather than observation-row count alone.
5. Candidate, fusion, rerank, router, evidence and prompt-budget decisions are explainable.
6. Citations resolve backward to Evidence and source lineage.
7. ACTIVE/SHADOW experiment isolation is enforced by tests.
8. At least heading+body multi-vector, sentence parent-child, feature reranker and dynamic evidence can run in the lab.
9. All previous phone regressions remain gated.
10. A signed arm64 in-place update passes CI and real-device acceptance before any “PHONE_FUNCTION_LOOP = PASS” claim is made.

---

## Design decision summary

R4.6 deliberately chooses **truthful runtime lineage before algorithm promotion**. The experiment layer is built on top of the same captured objects, so every new retrieval idea must answer not only “did the metric change?” but also “which real candidates moved, why, what Evidence changed, and did the final grounded answer improve?”

This is the architectural boundary for the implementation plan. No implementation work should begin until this spec is reviewed and approved.
