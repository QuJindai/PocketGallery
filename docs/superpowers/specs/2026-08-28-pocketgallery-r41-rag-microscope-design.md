# PocketGallery R4.1 · RAG Microscope Design

## Goal

Turn PocketGallery from a working local RAG assistant into an observable, explainable, measurable local knowledge product. Every knowledge-backed answer must expose why a source was found, how FTS5 and Embedding contributed, how ranks changed, which evidence entered Gemma, and whether retrieval quality is objectively good.

## Frozen Compatibility Contract

- Android applicationId remains `com.qujindai.pocketgallery_phone_pilot.r3`.
- Persistent R3 signing identity remains unchanged.
- Existing Gemma 4 / EmbeddingGemma files must not be redownloaded when already active/installed.
- Existing FTS5 database, vector database, chat database, OAuth credentials, imported documents and citations remain readable.
- R4.0.3 `PHONE_FUNCTION_LOOP = PASS` behavior remains a regression gate.
- No production data is uploaded for observability; all microscope data stays local.

## Reuse Strategy

### Existing PocketGallery

Keep the current layers and instrument them instead of replacing them:

`DocumentImporter -> Chunker -> LexicalFtsStore -> SemanticStore -> KnowledgeRetriever -> HybridRanker -> EvidencePack -> Gemma -> Citation`

The microscope is an additive observability/evaluation layer.

### User's earlier design assets

Reuse the earlier A-route architecture: independent Knowledge/RAG layers, SHA-256/dedupe, FTS5, Evidence and Citation boundaries. Reuse the earlier local-AI technical design: FTS/BM25 + Vector + Metadata + RRF/Rerank. Reuse the T8U visualization rule that raw runtime values are `REAL` and projections/aggregations are `DERIVED`; PCA must be labeled as a lossy projection rather than semantic truth.

### Community patterns

- RAGFlow: retrieval-test workflow, chunk inspection, threshold/weight tuning.
- TensorBoard Embedding Projector: vector-space projection and nearest-neighbor UX.
- Ragas: retrieval quality metric definitions.
- Open WebUI / Phoenix: source trace and retrieval observability UX concepts only; no code is copied.

## Truth Labels

Every microscope field is explicitly classified:

- `REAL`: directly read or produced by runtime/index/query execution. Examples: raw BM25, cosine similarity, lexical rank, semantic rank, chunk text, vector dimension, vector norm, duration.
- `DERIVED`: computed from REAL data. Examples: normalized BM25 affinity, RRF score, PCA coordinates, hit-rate metrics, aggregate health ratios.

No generated decorative points, synthetic scores or placeholder metrics are allowed in production UI.

## Data Model

### RetrievalTrace

A trace is created for each knowledge-enabled user query and stored locally.

Fields:

- `traceId`, `sessionId`, `query`, `startedAt`, `completedAt`
- `scopeDocumentIds`
- `lexicalDurationMs`, `semanticDurationMs`, `fusionDurationMs`, `evidenceDurationMs`, `generationDurationMs`
- `lexicalHits[]`, `semanticHits[]`, `hybridHits[]`, `evidence[]`, `citations[]`
- `queryVectorFingerprint` and optional query-vector projection metadata
- `mode`: modelOnly / auto / forcedKnowledge

Each trace hit preserves chunk/document/page locator plus raw and derived rank/score fields.

### VectorObservation

Persist the exact document embedding generated during index write:

- `chunkId`, `documentId`
- `dimension`
- `vector` as Float32 BLOB
- `norm`
- `modelIdentity`
- `updatedAt`

Document vectors are generated explicitly using `FlutterGemma.getActiveEmbedder()` and written to RAG with `addDocumentWithEmbedding`, so the vector shown by the microscope is the exact vector stored for that chunk.

Query vector is generated explicitly for observability with the same active model. The current `rag.searchSimilar(query:)` remains the canonical retrieval call until flutter_gemma exposes a public vector-query API; UI must label the query vector as the same-model observation, not claim it is the internal call payload.

## Six Approved UI Surfaces

### 1. Chat · Retrieval Trace

Each knowledge-backed assistant answer has a `检索依据` action. Expanded trace shows ordered stages:

1. Import/chunk context
2. FTS5
3. Embedding
4. Hybrid/RRF
5. Evidence
6. Gemma + Citation

Each stage shows PASS/degraded state, elapsed time, input/output counts and top source. Clicking a stage opens its detailed microscope page.

### 2. FTS5 Inspector

For a selected trace/query:

- query text and normalized FTS query
- raw SQLite `bm25()` score
- normalized affinity (DERIVED)
- rank, document, chunk, locator/page
- highlighted matched terms and snippet
- Top-K control
- CJK-aware query diagnostics

R4.1 fixes the current two-CJK-character blind spot: Chinese/Japanese/Korean contiguous terms of length 2 must remain searchable even when whitespace token length rules would otherwise remove them.

### 3. Vector Microscope

- model identity and vector dimension (EmbeddingGemma: runtime dimension)
- cosine similarity and vector norm
- nearest-neighbor table
- 2D PCA map using only real stored chunk vectors plus the current query vector
- optional 3D PCA projection shown with a deterministic perspective painter
- PCA explained-variance ratios shown as DERIVED values
- document filters and Top-K neighbor emphasis

UMAP/t-SNE are not faked in R4.1. The UI may expose them as disabled `高级投影` options with an explicit `未启用` label until a tested local implementation is added.

### 4. Hybrid Rank Lab

For every fused candidate show:

- FTS rank + raw/normalized lexical score
- Vector rank + cosine similarity
- RRF lexical contribution
- RRF semantic contribution
- dual-channel bonus / exact-term bonus
- final score and final rank
- channels (`fts5`, `embedding`, `corpus`)

The current fixed constants are visible, not hidden. R4.1 may tune them only through the A/B lab; default production values remain backward-compatible unless a benchmark proves improvement.

### 5. Chunk Explorer / Index Health

Knowledge page gains an inspector for each document:

- chunks and locators/pages
- character length and overlap estimate
- text preview
- FTS indexed yes/no
- vector observation yes/no
- vector dimension/norm/model identity
- duplicate/empty/textless flags
- document SHA256

Global Index Health shows:

- document count
- chunk count
- FTS indexed count/ratio
- vector indexed count/ratio
- stale/missing vector count
- zero-chunk document count
- duplicate SHA count
- database file sizes when available

### 6. Retrieval Benchmark / A-B Lab

A local benchmark dataset stores cases with:

- id, question
- expected document IDs and optional expected chunk IDs
- tags/language

Metrics:

- Hit@1
- Hit@3
- Recall@5
- MRR
- context precision (document/chunk relevance proxy from labels)
- citation accuracy when a generated answer is included

The A/B runner can compare at minimum:

- FTS-only
- Embedding-only
- current Hybrid
- alternate Hybrid parameter set

Results are stored locally with configuration snapshot and timestamp. No metric is shown until at least one benchmark case has run.

## Architecture Additions

Create focused modules:

- `lib/observability/retrieval_trace.dart`
- `lib/observability/retrieval_trace_store.dart`
- `lib/observability/vector_observation_store.dart`
- `lib/observability/pca_projector.dart`
- `lib/observability/index_health_service.dart`
- `lib/eval/retrieval_benchmark.dart`
- `lib/eval/retrieval_evaluator.dart`
- `lib/ui/microscope/*`

Instrument existing stores/retriever/orchestrator through explicit value objects; do not duplicate retrieval logic in UI.

## Performance Rules

- Trace capture must be bounded: persist top 20 lexical/semantic/hybrid candidates maximum.
- Vector map defaults to at most 250 chunk vectors; larger corpora sample deterministically by document while always retaining current Top-K neighbors.
- PCA runs on demand off the immediate query path and caches by vector-store fingerprint.
- Vector BLOB storage uses Float32, not JSON doubles.
- No trace collection may block pure-model chat.

## Acceptance Gates

1. Existing R4.0.3 functional loop tests remain green.
2. Two-character CJK FTS query has a passing fixture.
3. Vector written to observation store is the same explicit vector passed to `addDocumentWithEmbedding`.
4. Retrieval trace contains real raw scores/ranks/timing for FTS5, Embedding and fusion.
5. PCA result is deterministic for a fixed fixture and labels DERIVED data.
6. Index Health detects missing vector observations and zero-chunk documents.
7. Benchmark metrics are validated against hand-computable fixtures.
8. Six UI surfaces are reachable without developer mode.
9. No hard-coded demo scores/coordinates in production UI.
10. Flutter analyze, all unit tests, arm64 build, applicationId, fixed signing certificate and APK SHA gates pass.
