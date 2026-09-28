# PocketGallery R4.6-A Runtime Lineage Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the truthful R4.6 runtime-lineage foundation so one real knowledge-enabled chat turn uses one captured query embedding, a PocketGallery-owned explicit vector search path, inspectable retrieval/router/evidence/context/generation lineage, and a non-destructive migration from the R4.5 phone state.

**Architecture:** R4.6-A adds an additive `pocketgallery_lineage.db`, a separate `pocketgallery_vectors_v46.db`, a PocketGallery-owned retrieval runtime, and an immutable runtime event recorder. The R4.5 lexical DB remains the lexical source of truth and the R4.5 vector/observation stores remain rollback sources; existing healthy Float32 body embeddings are migrated into the new ACTIVE vector index without re-embedding. R4.6-A provides only the dashboard/navigation shell needed to inspect the foundation; the full 10-stage microscope is R4.6-B and Retrieval Evolution Lab strategies are R4.6-C.

**Tech Stack:** Flutter/Dart, SQLite via `sqlite3`, `flutter_gemma`/EmbeddingGemma, public `flutter_gemma_rag_sqlite` `SqliteVectorStore`, existing FTS5/BM25 store, existing HybridRanker, Android arm64 GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-08-29-pocketgallery-r46-runtime-lineage-retrieval-evolution-design.md`

## Global Constraints

- Development branch: `feature/phone-pilot-r46-runtime-lineage`, based on R4.5 `f79146cacf7d8013f17f1fcc9a47122e0f8e4738`.
- Android `applicationId` remains `com.qujindai.pocketgallery_phone_pilot.r3`.
- Canonical signing certificate SHA-256 remains `81af4a5ef94c236774f0e193b2a4b248805b36c14cc36e2a56df8e451a712541`.
- R4.6-A version is `0.4.15+16`; Android `versionCode` must be `2016`.
- Installed Gemma 4 and EmbeddingGemma assets must be reused. No upgrade-triggered model download.
- OAuth/pending device authorization, chats, knowledge documents, FTS5 DB and R4.5 model state must survive an in-place upgrade.
- Existing `pocketgallery_vectors.db` and `pocketgallery_observability.db` are rollback sources and must not be cleared, renamed, or destructively migrated.
- New ACTIVE vector DB is `pocketgallery_vectors_v46.db`.
- New lineage DB is `pocketgallery_lineage.db`.
- ACTIVE query embedding is generated exactly once per retrieval turn and the exact returned Float64/Dart vector values are passed to explicit vector search and persisted as the REAL query embedding.
- `Chunk` and `Embedding` are distinct identities. `embedding_id` is never equal to `chunk_id` by construction.
- A single chunk may own multiple embedding rows even though R4.6-A only builds the ACTIVE `body` representation.
- Runtime data uses independent labels: `REAL|DERIVED` truth kind and `ACTIVE|SHADOW|EXPERIMENTAL` lane.
- SHADOW/EXPERIMENTAL algorithms are not implemented in A. Schema/interfaces may reserve them; runtime stays `ACTIVE` with R4.5-compatible behavior.
- No post-hoc recomputation may be shown as REAL.
- No fake UMAP/t-SNE, TTFT, token count, tok/s, quality score, parse offset or citation confidence.
- New imports made after R4.6-A must capture exact parse/section/chunk lineage from import time; old documents with unavailable source files use `provenance_quality=legacy` and NULL for unknown offsets.
- Cross-store readiness follows `prepared -> lexical_committed -> lineage_committed -> vector_committed -> ready`. Do not infer readiness from row counts alone.
- Every task is RED-first TDD: focused failing test, verify the intended failure, minimal implementation, focused+related regression pass, commit.
- All R2–R4.5 tests remain regression gates.
- No merge to `main` or stacked upstream branches as part of this plan.
- Physical phone runtime acceptance remains required before claiming `PHONE_FUNCTION_LOOP = PASS` for R4.6-A.

---

## File Structure Locked for R4.6-A

### New lineage domain/storage

- `pilot/flutter_phone_loop/lib/lineage/lineage_ids.dart` — deterministic, collision-resistant IDs for embeddings, traces, candidates, evidence, events, build jobs.
- `pilot/flutter_phone_loop/lib/lineage/lineage_models.dart` — immutable R4.6 lineage records/enums shared by runtime, store and UI.
- `pilot/flutter_phone_loop/lib/lineage/lineage_store.dart` — owns `pocketgallery_lineage.db`, schema, CRUD, retention and transaction boundaries inside that DB only.
- `pilot/flutter_phone_loop/lib/lineage/import_lineage.dart` — exact/legacy parse-section-chunk lineage objects and conversion helpers.
- `pilot/flutter_phone_loop/lib/lineage/r45_vector_migration.dart` — resumable migration of healthy R4.5 body vectors into R4.6 embeddings/index.
- `pilot/flutter_phone_loop/lib/lineage/runtime_lineage_recorder.dart` — ordered runtime event/candidate/router/evidence/budget/generation/citation recorder.
- `pilot/flutter_phone_loop/lib/lineage/generation_models.dart` — prompt-budget and generation telemetry returned by the model gateway.
- `pilot/flutter_phone_loop/lib/lineage/vector_index_health_service.dart` — Generated/Persisted/Indexed/Search-Verified ACTIVE health.

### New retrieval runtime

- `pilot/flutter_phone_loop/lib/retrieval/active_vector_index.dart` — PocketGallery-owned explicit vector-index contract.
- `pilot/flutter_phone_loop/lib/retrieval/sqlite_active_vector_index.dart` — adapter over public `flutter_gemma_rag_sqlite` `SqliteVectorStore` using `queryEmbedding`.
- `pilot/flutter_phone_loop/lib/retrieval/query_embedding_runtime.dart` — exactly-once ACTIVE query embedding generation and persistence.
- `pilot/flutter_phone_loop/lib/retrieval/retrieval_execution_context.dart` — trace/turn/runtime context passed through retrieval.
- `pilot/flutter_phone_loop/lib/retrieval/router_policy.dart` — explicit R4.5-compatible Auto/Knowledge routing decision plus rule evidence.
- `pilot/flutter_phone_loop/lib/retrieval/evidence_policy.dart` — selected/dropped evidence outcome with reasons while preserving current EvidencePackBuilder compatibility.
- `pilot/flutter_phone_loop/lib/retrieval/retrieval_runtime.dart` — ACTIVE R4.6 orchestration of FTS, exact query embedding, explicit vector search, fusion, router and evidence.

### Modified production files

- `pilot/flutter_phone_loop/lib/core/chunker.dart`
- `pilot/flutter_phone_loop/lib/services/document_importer.dart`
- `pilot/flutter_phone_loop/lib/services/knowledge_engine.dart`
- `pilot/flutter_phone_loop/lib/services/knowledge_retriever.dart`
- `pilot/flutter_phone_loop/lib/chat/chat_models.dart`
- `pilot/flutter_phone_loop/lib/chat/context_budgeter.dart`
- `pilot/flutter_phone_loop/lib/services/gemma_chat_service.dart`
- `pilot/flutter_phone_loop/lib/chat/chat_orchestrator.dart`
- `pilot/flutter_phone_loop/lib/main.dart`
- `pilot/flutter_phone_loop/lib/ui/chat_page.dart`
- `pilot/flutter_phone_loop/lib/ui/knowledge_page.dart`
- `pilot/flutter_phone_loop/lib/ui/microscope/chunk_explorer_page.dart`
- `pilot/flutter_phone_loop/lib/services/golden_test_runner.dart`
- `pilot/flutter_phone_loop/pubspec.yaml`
- `.github/workflows/pocketgallery-phone-pilot-apk.yml`

### New UI shell

- `pilot/flutter_phone_loop/lib/ui/microscope/rag_lineage_dashboard_page.dart`

### New tests

- `pilot/flutter_phone_loop/test/r46_lineage_store_test.dart`
- `pilot/flutter_phone_loop/test/r46_vector_index_test.dart`
- `pilot/flutter_phone_loop/test/r46_vector_migration_test.dart`
- `pilot/flutter_phone_loop/test/r46_import_lineage_test.dart`
- `pilot/flutter_phone_loop/test/r46_query_embedding_identity_test.dart`
- `pilot/flutter_phone_loop/test/r46_runtime_lineage_recorder_test.dart`
- `pilot/flutter_phone_loop/test/r46_retrieval_runtime_test.dart`
- `pilot/flutter_phone_loop/test/r46_router_evidence_lineage_test.dart`
- `pilot/flutter_phone_loop/test/r46_context_generation_lineage_test.dart`
- `pilot/flutter_phone_loop/test/r46_chat_lineage_integration_test.dart`
- `pilot/flutter_phone_loop/test/r46_vector_health_test.dart`
- `pilot/flutter_phone_loop/test/r46_lineage_ui_test.dart`
- `pilot/flutter_phone_loop/test/r46_upgrade_golden_contract_test.dart`

---

### Task 1: Lineage identity model and additive SQLite store

**Files:**
- Create: `pilot/flutter_phone_loop/lib/lineage/lineage_ids.dart`
- Create: `pilot/flutter_phone_loop/lib/lineage/lineage_models.dart`
- Create: `pilot/flutter_phone_loop/lib/lineage/lineage_store.dart`
- Test: `pilot/flutter_phone_loop/test/r46_lineage_store_test.dart`

**Interfaces:**
- Produces `LineageIds.bodyEmbeddingId(String chunkId)`, `queryEmbeddingId(String traceId)`, `traceId(String sessionId, String turnId)`, and record IDs for events/candidates/evidence/build jobs.
- Produces enums `TruthKind`, `RetrievalLane`, `EmbeddingRepresentation`, `VectorCommitStatus`, `TraceStatus`, `BuildState`.
- Produces `LineageEmbedding`, `LineageTrace`, `TraceEventRecord`, `CandidateRecord`, `RouterDecisionRecord`, `EvidenceRecord`, `PromptBudgetRecord`, `GenerationStatsRecord`, `CitationRecord`, `BuildJobRecord`.
- Produces `LineageStore.initialize()`, per-record put/read methods, `eventsForTrace`, `candidatesForTrace`, `embeddingsForChunk`, `embeddingById`, `traceById`, `latestTraces`, `pruneCompletedTraces`.

- [ ] **Step 1: Write failing identity/schema tests**

```dart
// test/r46_lineage_store_test.dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_ids.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_models.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_store.dart';

void main() {
  test('chunk and embedding identities are distinct and one chunk can own many embeddings', () async {
    final db = sqlite3.openInMemory();
    final store = LineageStore(database: db);
    await store.initialize();

    const chunkId = 'doc:7';
    final bodyId = LineageIds.embeddingId(
      sourceKind: 'chunk', sourceId: chunkId,
      representation: EmbeddingRepresentation.body,
    );
    final headingId = LineageIds.embeddingId(
      sourceKind: 'chunk', sourceId: chunkId,
      representation: EmbeddingRepresentation.heading,
    );
    expect(bodyId, isNot(chunkId));
    expect(headingId, isNot(chunkId));
    expect(bodyId, isNot(headingId));

    await store.putEmbedding(LineageEmbedding.test(
      embeddingId: bodyId, sourceKind: 'chunk', sourceId: chunkId,
      chunkId: chunkId, representation: EmbeddingRepresentation.body,
      vector: const [1.0, 0.0], modelIdentity: 'EmbeddingGemma-test',
      taskMode: 'retrieval_document',
    ));
    await store.putEmbedding(LineageEmbedding.test(
      embeddingId: headingId, sourceKind: 'chunk', sourceId: chunkId,
      chunkId: chunkId, representation: EmbeddingRepresentation.heading,
      vector: const [0.0, 1.0], modelIdentity: 'EmbeddingGemma-test',
      taskMode: 'retrieval_document',
    ));
    expect(await store.embeddingsForChunk(chunkId), hasLength(2));
    db.close();
  });

  test('query embedding is first class without a chunk identity', () async {
    final db = sqlite3.openInMemory();
    final store = LineageStore(database: db);
    await store.initialize();
    final id = LineageIds.queryEmbeddingId('trace-1');
    await store.putEmbedding(LineageEmbedding.test(
      embeddingId: id, sourceKind: 'query', sourceId: 'trace-1',
      chunkId: null, representation: EmbeddingRepresentation.query,
      vector: const [0.2, 0.8], modelIdentity: 'EmbeddingGemma-test',
      taskMode: 'retrieval_query',
    ));
    final row = await store.embeddingById(id);
    expect(row!.chunkId, isNull);
    expect(row.representation, EmbeddingRepresentation.query);
    db.close();
  });

  test('lineage schema contains resumable build state and strategy scoped decisions', () async {
    final db = sqlite3.openInMemory();
    final store = LineageStore(database: db);
    await store.initialize();
    final tables = db.select("SELECT name FROM sqlite_master WHERE type='table'")
        .map((r) => r['name'] as String).toSet();
    expect(tables, containsAll(<String>{
      'pg_lineage_documents','pg_lineage_sections','pg_lineage_chunks',
      'pg_embeddings','pg_vector_index_entries','pg_traces','pg_trace_events',
      'pg_candidates','pg_router_decisions','pg_evidence','pg_prompt_budgets',
      'pg_generation_stats','pg_citations','pg_experiment_runs','pg_build_jobs',
    }));
    final routerSql = db.select("SELECT sql FROM sqlite_master WHERE name='pg_router_decisions'").single['sql'] as String;
    expect(routerSql, contains('strategy_id'));
    expect(routerSql, contains('lane'));
    db.close();
  });
}
```

- [ ] **Step 2: Run focused tests and verify RED**

Run from `pilot/flutter_phone_loop`:

```bash
flutter test test/r46_lineage_store_test.dart
```

Expected: FAIL because `lineage/*` types/files do not exist.

- [ ] **Step 3: Implement deterministic IDs and immutable domain records**

Use SHA-256 over a versioned canonical identity string rather than raw concatenation. The externally readable ID keeps a short semantic prefix and enough hash to avoid collisions:

```dart
// lib/lineage/lineage_ids.dart
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'lineage_models.dart';

abstract final class LineageIds {
  static String _id(String prefix, String canonical) {
    final digest = sha256.convert(utf8.encode('r46|$canonical')).toString();
    return '$prefix-${digest.substring(0, 24)}';
  }

  static String embeddingId({
    required String sourceKind,
    required String sourceId,
    required EmbeddingRepresentation representation,
    int? spanStart,
    int? spanEnd,
  }) => _id('emb', '$sourceKind|$sourceId|${representation.name}|${spanStart ?? -1}|${spanEnd ?? -1}');

  static String bodyEmbeddingId(String chunkId) => embeddingId(
    sourceKind: 'chunk', sourceId: chunkId,
    representation: EmbeddingRepresentation.body,
  );

  static String queryEmbeddingId(String traceId) => embeddingId(
    sourceKind: 'query', sourceId: traceId,
    representation: EmbeddingRepresentation.query,
  );

  static String traceId(String sessionId, String turnId) =>
      _id('tr', '$sessionId|$turnId');
  static String eventId(String traceId, int seq) => _id('evt', '$traceId|$seq');
  static String candidateId(String traceId, String strategyId, String chunkId) =>
      _id('cand', '$traceId|$strategyId|$chunkId');
  static String evidenceId(String traceId, String strategyId, String chunkId) =>
      _id('ev', '$traceId|$strategyId|$chunkId');
  static String buildJobId(String documentId, String strategyId) =>
      _id('job', '$documentId|$strategyId');
}
```

Define enums and records in `lineage_models.dart`. `LineageEmbedding.test(...)` is a test-only convenience factory in normal Dart code, implemented by calculating Float32 bytes, norm and SHA in the same way as production. Do not make tests manually fabricate inconsistent metadata.

- [ ] **Step 4: Implement `LineageStore` schema exactly as frozen in the spec**

`LineageStore` accepts optional `Database` for tests; production opens `${getApplicationDocumentsDirectory()}/pocketgallery_lineage.db`. Enable WAL and foreign keys. Create every table listed in the test and the columns/uniqueness constraints from spec sections 7.1–7.14 plus `pg_build_jobs` from the self-reviewed spec. Add indices on `(trace_id, seq)`, `(chunk_id, representation_type)`, `(trace_id, lane, strategy_id)`, and `(document_id, state)`.

Critical write methods must use `INSERT ... ON CONFLICT ... DO UPDATE` only for mutable build/index state; completed trace/event/history rows are append/immutable. `putEmbedding` validates non-empty vector, finite non-zero norm and BLOB length before writing.

- [ ] **Step 5: Run focused and existing persistence tests**

```bash
flutter test test/r46_lineage_store_test.dart test/r41_trace_store_test.dart test/r4_chat_session_store_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add pilot/flutter_phone_loop/lib/lineage pilot/flutter_phone_loop/test/r46_lineage_store_test.dart
git commit -m "feat: add R4.6 lineage store foundations"
```

---

### Task 2: PocketGallery-owned explicit ACTIVE vector index

**Files:**
- Create: `pilot/flutter_phone_loop/lib/retrieval/active_vector_index.dart`
- Create: `pilot/flutter_phone_loop/lib/retrieval/sqlite_active_vector_index.dart`
- Modify: `pilot/flutter_phone_loop/pubspec.yaml`
- Test: `pilot/flutter_phone_loop/test/r46_vector_index_test.dart`

**Interfaces:**

```dart
abstract interface class ActiveVectorIndex {
  Future<void> initialize();
  Future<void> add(VectorIndexRecord record);
  Future<void> remove(String embeddingId);
  Future<List<VectorSearchHit>> searchByEmbedding({
    required List<double> queryEmbedding,
    required int topK,
    required KnowledgeScope scope,
  });
  Future<VectorIndexProbe> probe();
  Future<void> close();
}
```

`VectorIndexRecord` includes `embeddingId`, `chunkId`, `documentId`, `content`, `embedding`, `modelIdentity`. `VectorSearchHit` includes `embeddingId`, `chunkId`, `documentId`, `similarity`, `rank`.

- [ ] **Step 1: Write failing adapter contract tests**

Use a fake backend abstraction injected into `SqliteActiveVectorIndex` so the test proves the same explicit vector is passed to `queryEmbedding` and that index identity is `embedding_id`, not `chunk_id`.

```dart
test('explicit vector adapter indexes by embedding id and searches the supplied query vector', () async {
  final backend = RecordingVectorBackend();
  final index = SqliteActiveVectorIndex.forTest(backend);
  await index.initialize();
  const query = [0.25, 0.75];
  await index.add(const VectorIndexRecord(
    embeddingId: 'emb-body-1', chunkId: 'chunk-1', documentId: 'doc-1',
    content: '端侧模型性能测试', embedding: [1.0, 0.0],
    modelIdentity: 'EmbeddingGemma-test',
  ));
  backend.nextHits = const [BackendVectorHit(
    id: 'emb-body-1', similarity: 0.81,
    metadata: {'chunkId':'chunk-1','documentId':'doc-1'},
  )];
  final hits = await index.searchByEmbedding(
    queryEmbedding: query, topK: 5, scope: const KnowledgeScope.all());
  expect(identical(backend.lastQueryEmbedding, query), isTrue);
  expect(backend.lastAddedId, 'emb-body-1');
  expect(hits.single.chunkId, 'chunk-1');
});
```

- [ ] **Step 2: Run and verify RED**

```bash
flutter test test/r46_vector_index_test.dart
```

Expected: FAIL because the R4.6 vector adapter does not exist.

- [ ] **Step 3: Implement adapter and backend seam**

Production `SqliteVectorBackend` wraps public `SqliteVectorStore` from `flutter_gemma_rag_sqlite` and configures metadata fields `chunkId`, `documentId`, `modelIdentity`. Initialize it at `pocketgallery_vectors_v46.db`. Call:

```dart
await store.addDocument(
  id: record.embeddingId,
  content: record.content,
  embedding: record.embedding,
  metadata: {
    'chunkId': record.chunkId,
    'documentId': record.documentId,
    'modelIdentity': record.modelIdentity,
  },
);

final rows = await store.searchSimilar(
  queryEmbedding: queryEmbedding,
  topK: candidateK,
);
```

Do not use a text-query helper anywhere in the ACTIVE adapter. Scope filtering may initially oversample and filter metadata exactly as R4.5 semantic scope did; record this as explicit behavior, not hidden inference.

`flutter_gemma_rag_sqlite` is already a direct dependency in `pubspec.yaml`; keep it direct and bump only if the locked/public API version requires it. Do not add another vector package.

- [ ] **Step 4: Run focused tests**

```bash
flutter test test/r46_vector_index_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add pilot/flutter_phone_loop/lib/retrieval/active_vector_index.dart pilot/flutter_phone_loop/lib/retrieval/sqlite_active_vector_index.dart pilot/flutter_phone_loop/pubspec.yaml pilot/flutter_phone_loop/test/r46_vector_index_test.dart
git commit -m "feat: add explicit R4.6 vector index adapter"
```

---

### Task 3: Resumable R4.5 body-vector migration without re-embedding

**Files:**
- Create: `pilot/flutter_phone_loop/lib/lineage/r45_vector_migration.dart`
- Modify: `pilot/flutter_phone_loop/lib/services/knowledge_engine.dart`
- Test: `pilot/flutter_phone_loop/test/r46_vector_migration_test.dart`

**Interfaces:**

```dart
class R45VectorMigration {
  Future<VectorMigrationReport> migrateActiveBodyVectors({
    required String activeModelIdentity,
    required int expectedDimension,
    void Function(VectorMigrationProgress progress)? onProgress,
  });
}
```

The migration consumes `LexicalFtsStore`, R4.5 `VectorObservationStore`, R4.6 `LineageStore`, and `ActiveVectorIndex`. An `EmbeddingGenerator` callback is used only when observation data are missing/stale/invalid.

- [ ] **Step 1: Write failing migration tests**

Cover four rows: healthy existing vector, missing vector, stale-model vector, invalid zero-norm vector. Assert the healthy vector is copied byte/value-for-value and never sent to the embedding generator. Assert rerunning after a partial failure only processes incomplete entries.

```dart
test('healthy R4.5 body vector migrates without embedding generation', () async {
  final generator = RecordingEmbeddingGenerator();
  final report = await fixture(generator: generator).migration.migrateActiveBodyVectors(
    activeModelIdentity: 'EmbeddingGemma-test', expectedDimension: 2);
  expect(generator.documentCalls, 0);
  expect(report.reused, 1);
  final embedding = await fixtureStore.embeddingById(LineageIds.bodyEmbeddingId('c1'));
  expect(embedding!.vector, [0.6, 0.8]);
});
```

- [ ] **Step 2: Run and verify RED**

```bash
flutter test test/r46_vector_migration_test.dart
```

Expected: FAIL because migration service does not exist.

- [ ] **Step 3: Implement health validation and checkpoint state**

A reusable R4.5 observation is valid only if:

```dart
bool reusable(VectorObservation v, String model, int dimension) =>
    v.modelIdentity == model &&
    v.dimension == dimension &&
    v.vector.length == dimension &&
    v.norm.isFinite && v.norm > 0 &&
    v.vector.every((x) => x.isFinite);
```

For every chunk:
1. upsert `pg_build_jobs` state `prepared`;
2. ensure legacy document/chunk lineage rows exist;
3. reuse valid observation or generate only missing/stale/invalid body vector with `TaskType.retrievalDocument`;
4. persist `pg_embeddings` body row;
5. upsert `pg_vector_index_entries` `pending`;
6. add to `ActiveVectorIndex`;
7. mark vector entry `committed`, build job `vector_committed`, then `ready` when lexical/lineage prerequisites are satisfied.

If any add/generation fails, mark the specific job/entry failed but keep completed rows. Never call `clear()` on the R4.5 vector or observation stores.

- [ ] **Step 4: Wire migration into `KnowledgeEngine.initialize()` as an explicit resumable boot migration**

`KnowledgeEngine.initialize()` initializes old stores first, then lineage store/vector index, then calls migration only when EmbeddingGemma is active. If the embedder is not active, initialize lineage but leave vector migration pending; model setup/repair can resume it later. Do not make app startup redownload a model.

- [ ] **Step 5: Run focused and repair regressions**

```bash
flutter test test/r46_vector_migration_test.dart test/r44_embedding_repair_regression_test.dart test/r3_model_cache_contract_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add pilot/flutter_phone_loop/lib/lineage/r45_vector_migration.dart pilot/flutter_phone_loop/lib/services/knowledge_engine.dart pilot/flutter_phone_loop/test/r46_vector_migration_test.dart
git commit -m "feat: migrate R4.5 body vectors without re-embedding"
```

---

### Task 4: Exact parse/section/chunk lineage for all new R4.6 imports

**Files:**
- Create: `pilot/flutter_phone_loop/lib/lineage/import_lineage.dart`
- Modify: `pilot/flutter_phone_loop/lib/core/chunker.dart`
- Modify: `pilot/flutter_phone_loop/lib/services/document_importer.dart`
- Modify: `pilot/flutter_phone_loop/lib/services/knowledge_engine.dart`
- Test: `pilot/flutter_phone_loop/test/r46_import_lineage_test.dart`

**Interfaces:**

```dart
class LineageImportResult {
  final ImportedDocument document;
  final LineageDocumentRecord lineageDocument;
  final List<LineageSectionRecord> sections;
  final List<LineageChunkRecord> chunks;
}

Future<LineageImportResult> importPathWithLineage(String path);
Future<ImportedDocument> importPath(String path) async =>
    (await importPathWithLineage(path)).document;
```

- [ ] **Step 1: Write failing import lineage tests**

Create temporary TXT and Markdown files. Assert Markdown headings become sections, chunk offsets point to real spans, boundary reason is populated, and TXT/PDF empty text produces an explicit parse/zero-chunk diagnostic rather than invented offsets.

```dart
test('new markdown import records exact heading and chunk provenance', () async {
  final file = File('${tmp.path}/a.md');
  await file.writeAsString('# 端侧测试\n\n第一段内容。\n\n## 功耗\n\n功耗测试方法。');
  final result = await importer.importPathWithLineage(file.path);
  expect(result.lineageDocument.provenanceQuality, ProvenanceQuality.exact);
  expect(result.sections.map((x) => x.heading), containsAll(['端侧测试','功耗']));
  expect(result.chunks, isNotEmpty);
  expect(result.chunks.every((c) => c.startOffset != null && c.endOffset != null), isTrue);
  expect(result.chunks.every((c) => c.boundaryReason.isNotEmpty), isTrue);
});
```

- [ ] **Step 2: Run and verify RED**

```bash
flutter test test/r46_import_lineage_test.dart
```

Expected: FAIL because importer/chunker do not expose lineage.

- [ ] **Step 3: Extend chunker without breaking `PgChunk` compatibility**

Add a new `ChunkSlice`/`ChunkLineageDraft` result containing `PgChunk`, source section ID, normalized start/end offsets, overlap and boundary reason. Keep existing `chunkSections(...) -> List<PgChunk>` by delegating to `chunkSectionsWithLineage(...).map((x) => x.chunk)`.

Boundary reason values in A are concrete: `section_end`, `sentence_punctuation`, `hard_limit`. Do not label a hard limit as semantic boundary.

- [ ] **Step 4: Implement TXT/MD/PDF parse lineage**

- TXT: one exact text section with offsets and char count.
- MD: detect ATX headings `#{1,6} `; create heading-owned paragraph-group sections while preserving exact source offsets.
- PDF: keep current `pdfrx` extraction but record page count, per-page extracted char count and page state `text|empty|parse_failed`. No OCR claim.
- Parse failures record error code/detail in lineage result and rethrow only when current import behavior already treats the import as failed.

- [ ] **Step 5: Persist exact lineage through `KnowledgeEngine.importPath`**

Cross-store order:
1. create/update build job `prepared`;
2. write existing lexical document/chunks, mark `lexical_committed`;
3. write exact lineage rows, mark `lineage_committed`;
4. build ACTIVE body embeddings/index if embedder ready, mark `vector_committed`;
5. mark `ready` only when required ACTIVE work is committed.

If vector indexing is unavailable, lexical + lineage remain valid and job stays resumable instead of rolling back/import failing.

- [ ] **Step 6: Run import, scope and zero-chunk regressions**

```bash
flutter test test/r46_import_lineage_test.dart test/r31_phone_recovery_test.dart test/r4_knowledge_scope_test.dart test/r402_chat_attachment_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add pilot/flutter_phone_loop/lib/lineage/import_lineage.dart pilot/flutter_phone_loop/lib/core/chunker.dart pilot/flutter_phone_loop/lib/services/document_importer.dart pilot/flutter_phone_loop/lib/services/knowledge_engine.dart pilot/flutter_phone_loop/test/r46_import_lineage_test.dart
git commit -m "feat: capture exact R4.6 import lineage"
```

---

### Task 5: Exactly-once ACTIVE query embedding identity

**Files:**
- Create: `pilot/flutter_phone_loop/lib/retrieval/query_embedding_runtime.dart`
- Test: `pilot/flutter_phone_loop/test/r46_query_embedding_identity_test.dart`

**Interfaces:**

```dart
abstract interface class EmbeddingGenerator {
  Future<List<double>> generateQuery(String text);
  Future<List<double>> generateDocument(String text);
}

class CapturedQueryEmbedding {
  final LineageEmbedding embedding;
  final List<double> vector;
}

class QueryEmbeddingRuntime {
  Future<CapturedQueryEmbedding> generateOnce({
    required String traceId,
    required String query,
  });
}
```

Production generator calls active EmbeddingGemma with `TaskType.retrievalQuery`; document fallback generation uses `TaskType.retrievalDocument`.

- [ ] **Step 1: Write failing exactly-once test**

```dart
test('one captured query vector is persisted and passed unchanged to search', () async {
  final generator = RecordingEmbeddingGenerator(const [0.1, 0.2, 0.3]);
  final runtime = QueryEmbeddingRuntime(generator: generator, store: lineageStore);
  final captured = await runtime.generateOnce(traceId: 'tr-1', query: '端侧模型如何测试');
  await fakeIndex.searchByEmbedding(
    queryEmbedding: captured.vector, topK: 5, scope: const KnowledgeScope.all());
  expect(generator.queryCalls, 1);
  expect(identical(fakeIndex.lastQueryEmbedding, captured.vector), isTrue);
  final persisted = await lineageStore.embeddingById(captured.embedding.embeddingId);
  expect(persisted!.vectorSha256, captured.embedding.vectorSha256);
  expect(persisted.taskMode, 'retrieval_query');
});
```

- [ ] **Step 2: Run and verify RED**

```bash
flutter test test/r46_query_embedding_identity_test.dart
```

Expected: FAIL because the runtime does not exist.

- [ ] **Step 3: Implement production generator and query capture**

Generate the query exactly once, measure generation duration, calculate norm + Float32 SHA, persist `source_kind=query`, `representation=query`, `source_id=traceId`, then return the same in-memory vector list. Do not call `SemanticStore.observeQueryVector()` from the new ACTIVE path.

- [ ] **Step 4: Run focused test**

```bash
flutter test test/r46_query_embedding_identity_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add pilot/flutter_phone_loop/lib/retrieval/query_embedding_runtime.dart pilot/flutter_phone_loop/test/r46_query_embedding_identity_test.dart
git commit -m "feat: use one captured query vector for active retrieval"
```

---

### Task 6: Immutable ordered Runtime Lineage Recorder

**Files:**
- Create: `pilot/flutter_phone_loop/lib/lineage/runtime_lineage_recorder.dart`
- Test: `pilot/flutter_phone_loop/test/r46_runtime_lineage_recorder_test.dart`

**Interfaces:**

```dart
class RuntimeLineageRecorder {
  Future<LineageTrace> startTrace(...);
  Future<void> event(...);
  Future<void> candidates(...);
  Future<void> routerDecision(...);
  Future<void> evidence(...);
  Future<void> promptBudget(...);
  Future<void> generation(...);
  Future<void> citations(...);
  Future<void> completeTrace(String traceId, {required String finalMode});
  Future<void> failTrace(String traceId, {required String stage, required Object error});
}
```

- [ ] **Step 1: Write failing event-order/failure/retention tests**

Assert:
- `trace.started` is seq 1;
- later seq are monotonic;
- a failed trace keeps earlier events;
- candidate persistence is capped at configured 50/channel/strategy and cap metadata is itself recorded;
- pruning keeps newest 200 completed traces but never removes persistent chunk body embeddings.

- [ ] **Step 2: Run and verify RED**

```bash
flutter test test/r46_runtime_lineage_recorder_test.dart
```

Expected: FAIL because recorder does not exist.

- [ ] **Step 3: Implement recorder with one SQLite transaction per logical batch**

Use the lineage DB's own transactions for event batch + corresponding candidate/decision rows. `failTrace` stores a normalized error code from runtime type plus bounded detail text; never include OAuth tokens or credentials in payload JSON.

- [ ] **Step 4: Run focused test**

```bash
flutter test test/r46_runtime_lineage_recorder_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add pilot/flutter_phone_loop/lib/lineage/runtime_lineage_recorder.dart pilot/flutter_phone_loop/test/r46_runtime_lineage_recorder_test.dart
git commit -m "feat: persist R4.6 runtime lineage event stream"
```

---

### Task 7: R4.6 ACTIVE RetrievalRuntime with explicit router/evidence decisions

**Files:**
- Create: `pilot/flutter_phone_loop/lib/retrieval/retrieval_execution_context.dart`
- Create: `pilot/flutter_phone_loop/lib/retrieval/router_policy.dart`
- Create: `pilot/flutter_phone_loop/lib/retrieval/evidence_policy.dart`
- Create: `pilot/flutter_phone_loop/lib/retrieval/retrieval_runtime.dart`
- Modify: `pilot/flutter_phone_loop/lib/services/knowledge_retriever.dart`
- Modify: existing retrieval fakes/tests that implement `KnowledgeRetrievalGateway`
- Test: `pilot/flutter_phone_loop/test/r46_retrieval_runtime_test.dart`
- Test: `pilot/flutter_phone_loop/test/r46_router_evidence_lineage_test.dart`

**Interfaces:**

```dart
class RetrievalExecutionContext {
  final String traceId;
  final String sessionId;
  final String turnId;
  final String strategyId; // active.r45-body-hybrid
  final RetrievalLane lane; // ACTIVE in A
}

abstract class KnowledgeRetrievalGateway {
  Future<RetrievalBundle> retrieve(
    String query, {
    KnowledgeScope scope = const KnowledgeScope.all(),
    int limit = 8,
    RetrievalExecutionContext? execution,
  });
}
```

`RouterPolicy.evaluate(...) -> RouterDecision`; `EvidencePolicy.select(...) -> EvidenceSelectionResult` with both selected and dropped candidates/reasons.

- [ ] **Step 1: Write RED tests for exact query vector and R4.5-compatible routing**

Test a real in-memory lexical store plus fake query generator/index. Assert:
- FTS executes;
- query generator called once;
- exact query vector passed to index;
- vector hit maps `embedding_id -> chunk_id`;
- HybridRanker retains R4.5 deterministic rank behavior;
- `router.evaluated` values equal the values that drove `relevantForAuto`;
- weak semantic-only remains Model;
- strong/gapped semantic-only can be Knowledge;
- dual-channel remains Knowledge;
- dropped evidence candidates have concrete `relative_score_cutoff`, `max_evidence`, or `token_budget` reason.

- [ ] **Step 2: Run and verify RED**

```bash
flutter test test/r46_retrieval_runtime_test.dart test/r46_router_evidence_lineage_test.dart
```

Expected: FAIL because R4.6 RetrievalRuntime/policies do not exist.

- [ ] **Step 3: Extract explicit R4.5-compatible `RouterPolicy`**

Use the frozen thresholds already in `RetrievalBundle`:

```dart
static const autoStrong = 0.62;
static const autoFloor = 0.52;
static const autoGap = 0.035;
static const knowledgeStrong = 0.58;
static const knowledgeFloor = 0.50;
static const knowledgeGap = 0.025;
```

Return a decision object containing raw inputs, threshold profile, each PASS/FAIL flag, final `useKnowledge`, and a stable reason code such as `dual_channel`, `lexical_hit`, `semantic_strong`, `semantic_gap`, `insufficient_semantic`.

- [ ] **Step 4: Extract explicit evidence selection while preserving current normal-Q&A and corpus-summary behavior**

For normal Q&A, retain R4.5 default max 3 and relative score cutoff. For corpus-summary intent, retain cross-document coverage and allow the existing higher coverage behavior under the later context token budget. `EvidencePackBuilder.build()` remains available for older callers/tests by delegating to the selection policy's selected list.

- [ ] **Step 5: Implement `RetrievalRuntime` ACTIVE path**

Order:
1. record query normalization/FTS timing;
2. run lexical inspect;
3. if embedder ready, call `QueryEmbeddingRuntime.generateOnce`;
4. call `ActiveVectorIndex.searchByEmbedding` with that vector;
5. resolve vector hits by `chunk_id` via lexical store;
6. fuse via current `HybridRanker`;
7. select evidence;
8. evaluate router;
9. persist candidates/router/evidence/events using recorder;
10. return `RetrievalBundle` carrying the same outward behavior needed by ChatOrchestrator.

When `execution == null`, allow existing tests/tools to use a compatibility path, but production ChatOrchestrator must always supply execution for knowledge-enabled turns after Task 9.

- [ ] **Step 6: Preserve corpus-summary and scope regressions**

```bash
flutter test test/r46_retrieval_runtime_test.dart test/r46_router_evidence_lineage_test.dart test/r401_phone_realworld_recovery_test.dart test/r4_knowledge_retriever_test.dart test/r4_knowledge_scope_test.dart test/r45_retrieval_quality_regression_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add pilot/flutter_phone_loop/lib/retrieval pilot/flutter_phone_loop/lib/services/knowledge_retriever.dart pilot/flutter_phone_loop/test/r46_retrieval_runtime_test.dart pilot/flutter_phone_loop/test/r46_router_evidence_lineage_test.dart pilot/flutter_phone_loop/test/r4_knowledge_retriever_test.dart pilot/flutter_phone_loop/test/r4_chat_orchestrator_test.dart
git commit -m "feat: record retrieval routing and evidence decisions"
```

---

### Task 8: Context-budget and generation telemetry from the real model path

**Files:**
- Create: `pilot/flutter_phone_loop/lib/lineage/generation_models.dart`
- Modify: `pilot/flutter_phone_loop/lib/chat/context_budgeter.dart`
- Modify: `pilot/flutter_phone_loop/lib/chat/chat_models.dart`
- Modify: `pilot/flutter_phone_loop/lib/services/gemma_chat_service.dart`
- Modify: model fakes in existing tests
- Test: `pilot/flutter_phone_loop/test/r46_context_generation_lineage_test.dart`

**Interfaces:**

```dart
class ContextBudgetDecision {
  final int modelContextLimit;
  final int systemTokens;
  final int historyTokens;
  final int evidenceTokens;
  final int queryTokens;
  final int outputReserveTokens;
  final int totalPrefillTokens;
  final int remainingTokens;
  final int trimmedHistoryMessages;
  final int trimmedEvidenceItems;
  final List<String> trimDetails;
}

class ChatTurnResult {
  final String text;
  final ContextBudgetDecision budget;
  final GenerationTelemetry generation;
}

abstract interface class ChatModelGateway {
  Future<ChatTurnResult> sendTurn(...);
}
```

`GenerationTelemetry` has `generationMs` required and `ttftMs`, `outputTokens`, `decodeTokensPerSecond`, `backend` nullable. Null means backend did not expose it; never estimate it and label REAL.

- [ ] **Step 1: Write failing budget telemetry tests**

Assert returned budget includes current query and Evidence, total prefill never exceeds model context minus output reserve, trim counts match actual history/evidence trimming, and generation telemetry leaves unsupported metrics null.

- [ ] **Step 2: Run and verify RED**

```bash
flutter test test/r46_context_generation_lineage_test.dart
```

Expected: FAIL because current gateway returns `String` and budgeter does not return a decision object.

- [ ] **Step 3: Make ContextBudgeter return the chosen history plus accounting**

Add `ContextSelection selectHistoryWithDecision(...)`; keep existing `selectHistory(...)` delegating to it for compatibility. Compute token estimates using the same estimator currently used by production. `remainingTokens = modelMaxTokens - outputReserve - totalPrefill`, clamped only after asserting non-negative in tests.

- [ ] **Step 4: Update GemmaChatService to return `ChatTurnResult`**

Keep fresh native chat per turn and the current Prefill/session-closed protections. Measure REAL `generationMs` around the actual response call. If the backend cannot expose first-token timing or reliable token count at the public API used here, return null for those fields.

- [ ] **Step 5: Update all fake model gateways and run long-chat regressions**

```bash
flutter test test/r46_context_generation_lineage_test.dart test/r4_gemma_chat_contract_test.dart test/r43_realworld_phone_regression_test.dart test/r4_chat_orchestrator_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add pilot/flutter_phone_loop/lib/lineage/generation_models.dart pilot/flutter_phone_loop/lib/chat/context_budgeter.dart pilot/flutter_phone_loop/lib/chat/chat_models.dart pilot/flutter_phone_loop/lib/services/gemma_chat_service.dart pilot/flutter_phone_loop/test/r46_context_generation_lineage_test.dart pilot/flutter_phone_loop/test/r4_gemma_chat_contract_test.dart pilot/flutter_phone_loop/test/r4_chat_orchestrator_test.dart
git commit -m "feat: capture context budget and generation telemetry"
```

---

### Task 9: Integrate ChatOrchestrator with the new lineage lifecycle

**Files:**
- Modify: `pilot/flutter_phone_loop/lib/chat/chat_orchestrator.dart`
- Modify: `pilot/flutter_phone_loop/lib/main.dart`
- Modify: `pilot/flutter_phone_loop/lib/ui/chat_page.dart`
- Test: `pilot/flutter_phone_loop/test/r46_chat_lineage_integration_test.dart`
- Modify: existing orchestration tests/fakes as required

**Interfaces:**
- `ChatOrchestrator` receives `RuntimeLineageRecorder`, `LineageStore`, and the R4.6 `RetrievalRuntime` as its production retriever.
- The assistant `ChatMessage.traceId` is the R4.6 lineage trace ID for new turns.
- Historical R4.1–R4.5 `RetrievalTraceStore` remains readable only as fallback for old messages.

- [ ] **Step 1: Write failing end-to-end fake-runtime lineage test**

The test sends one Auto knowledge turn and verifies ordered events include:

```text
trace.started
fts.search_completed
embedding.query_completed
vector.search_completed
candidate.pool_built
fusion.completed
router.evaluated
evidence.selected
context.budgeted
generation.completed
citation.resolved
trace.completed
```

Also test a model exception: trace becomes `failed`, earlier events remain, and the exception still reaches the existing UI error path.

- [ ] **Step 2: Run and verify RED**

```bash
flutter test test/r46_chat_lineage_integration_test.dart
```

Expected: FAIL because ChatOrchestrator still creates/persists the legacy trace after retrieval.

- [ ] **Step 3: Move trace/turn identity creation before retrieval**

Use persisted user message ID as `turnId` so identity is stable. Start trace before retrieval for Auto/Knowledge modes. Construct `RetrievalExecutionContext` and pass it into `retrieve`. For `modelOnly`, no RAG lineage trace is required in A unless a later generation-only trace feature is explicitly added.

- [ ] **Step 4: Persist prompt/generation/citation lineage from the returned real model result**

After retrieval and before model call, let GemmaChatService return the real `ContextBudgetDecision`; recorder stores it. Record generation telemetry and citation resolution. Complete trace with the final route. On any failure, call `failTrace` in `catch`/`finally` without masking the original error.

- [ ] **Step 5: Update ChatPage trace navigation**

For a new R4.6 trace ID, open `RagLineageDashboardPage`. For older messages, if R4.6 lineage store has no row, fall back to current `RetrievalTraceStore` + `RetrievalTracePage`. Do not break historical chat traces.

- [ ] **Step 6: Run orchestration/UI regressions**

```bash
flutter test test/r46_chat_lineage_integration_test.dart test/r4_chat_orchestrator_test.dart test/r4_chat_ui_test.dart test/r402_chat_attachment_test.dart test/r43_realworld_phone_regression_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add pilot/flutter_phone_loop/lib/chat/chat_orchestrator.dart pilot/flutter_phone_loop/lib/main.dart pilot/flutter_phone_loop/lib/ui/chat_page.dart pilot/flutter_phone_loop/test/r46_chat_lineage_integration_test.dart pilot/flutter_phone_loop/test/r4_chat_orchestrator_test.dart
git commit -m "feat: integrate chat with R4.6 runtime lineage"
```

---

### Task 10: Four-state ACTIVE vector health and searchable-index probe

**Files:**
- Create: `pilot/flutter_phone_loop/lib/lineage/vector_index_health_service.dart`
- Modify: `pilot/flutter_phone_loop/lib/observability/index_health_service.dart`
- Modify: `pilot/flutter_phone_loop/lib/ui/microscope/chunk_explorer_page.dart`
- Test: `pilot/flutter_phone_loop/test/r46_vector_health_test.dart`

**Interfaces:**

```dart
class ActiveVectorHealth {
  final int required;
  final int generated;
  final int persisted;
  final int indexed;
  final bool searchVerified;
  final int pending;
  final int failed;
  final int staleModel;
  bool get ready;
}
```

- [ ] **Step 1: Write failing health truthfulness tests**

Test states:
- embedding row only => not READY;
- persisted + pending index => not READY;
- committed but probe fails => not READY;
- active model mismatch => not READY;
- all required body embeddings committed + probe succeeds => READY;
- missing SHADOW representations do not affect ACTIVE ready.

- [ ] **Step 2: Run and verify RED**

```bash
flutter test test/r46_vector_health_test.dart
```

Expected: FAIL because current index health equates observation rows with vector coverage.

- [ ] **Step 3: Implement `VectorIndexHealthService`**

Count required ACTIVE body embeddings from current lexical chunks, Generated/Persisted from `pg_embeddings`, Indexed from committed `pg_vector_index_entries` for `active.r45-body-hybrid`, model mismatch from embedding metadata, and call `ActiveVectorIndex.probe()` for Search Verified. `ready` is exactly the conjunction frozen in the spec.

- [ ] **Step 4: Integrate with existing Chunk Explorer without removing legacy diagnostics**

Keep current FTS and R4.5 observation metrics but relabel the old vector count as `Legacy observation`. Add a separate dense `R4.6 ACTIVE Vector` block with `Generated / Persisted / Indexed / Search Verified / Pending / Failed`. Do not claim `Vector READY` from observation count.

- [ ] **Step 5: Run health/index regressions**

```bash
flutter test test/r46_vector_health_test.dart test/r41_index_health_test.dart test/r44_embedding_repair_regression_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add pilot/flutter_phone_loop/lib/lineage/vector_index_health_service.dart pilot/flutter_phone_loop/lib/observability/index_health_service.dart pilot/flutter_phone_loop/lib/ui/microscope/chunk_explorer_page.dart pilot/flutter_phone_loop/test/r46_vector_health_test.dart
git commit -m "feat: verify searchable R4.6 vector health"
```

---

### Task 11: R4.6-A RAG Lineage dashboard shell and truthful navigation

**Files:**
- Create: `pilot/flutter_phone_loop/lib/ui/microscope/rag_lineage_dashboard_page.dart`
- Modify: `pilot/flutter_phone_loop/lib/ui/knowledge_page.dart`
- Modify: `pilot/flutter_phone_loop/lib/ui/chat_page.dart`
- Test: `pilot/flutter_phone_loop/test/r46_lineage_ui_test.dart`

**Interfaces:**
- `RagLineageDashboardPage({required KnowledgeEngine engine, required LineageStore lineageStore, String? traceId})`.
- If `traceId` is null, page shows latest traces and system lineage/index summary; if set, shows that trace.

- [ ] **Step 1: Write failing UI contract tests**

Assert source contains/Widget test renders:
- horizontal 10-stage strip: `文档解析`, `切片`, `FTS5`, `Embedding`, `向量空间`, `候选池`, `融合/重排`, `路由决策`, `证据与上下文`, `生成与引用`;
- explicit teaching card text `Chunk ≠ Vector` and `Chunk → Embedding`;
- `REAL`, `DERIVED`, `ACTIVE` badges;
- absent runtime values render `未捕获`/`backend 未暴露`, never fabricated `0 ms`;
- Knowledge page exposes `RAG Lineage` entry;
- existing Chat/Knowledge/Model tabs remain unchanged.

- [ ] **Step 2: Run and verify RED**

```bash
flutter test test/r46_lineage_ui_test.dart
```

Expected: FAIL because dashboard page does not exist.

- [ ] **Step 3: Implement dashboard shell only**

The A dashboard reads captured lineage rows. It includes:
- trace header: query, final mode, ACTIVE strategy, status, elapsed time from captured timestamps;
- horizontally scrolling 10-stage cards whose status derives from actual event kinds;
- simple timing waterfall using captured event durations only;
- `Chunk ≠ Vector` relationship card showing a real chunk ID and its distinct body embedding ID when available;
- compact Router/Evidence/Context/Generation summaries from actual lineage rows;
- navigation placeholders for B deep pages are disabled and labelled `R4.6-B` rather than opening fake screens.

Do not port the desktop mockup literally; phone portrait stacks cards and preserves information density.

- [ ] **Step 4: Wire Knowledge entry and Chat trace entry**

Knowledge page keeps current Index Health and Benchmark. Add a third entry `RAG Lineage`. Chat new traces open this dashboard; historical traces keep legacy fallback.

- [ ] **Step 5: Run UI and legacy microscope regressions**

```bash
flutter test test/r46_lineage_ui_test.dart test/r41_microscope_ui_test.dart test/r4_knowledge_ui_test.dart test/r4_chat_ui_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add pilot/flutter_phone_loop/lib/ui/microscope/rag_lineage_dashboard_page.dart pilot/flutter_phone_loop/lib/ui/knowledge_page.dart pilot/flutter_phone_loop/lib/ui/chat_page.dart pilot/flutter_phone_loop/test/r46_lineage_ui_test.dart
git commit -m "feat: add R4.6 lineage dashboard shell"
```

---

### Task 12: Version, Phone Golden A-gates, CI and release verification

**Files:**
- Modify: `pilot/flutter_phone_loop/pubspec.yaml`
- Modify: `pilot/flutter_phone_loop/lib/services/golden_test_runner.dart`
- Modify: `pilot/flutter_phone_loop/lib/ui/model_settings_page.dart` only if needed to render added Golden rows
- Modify: `.github/workflows/pocketgallery-phone-pilot-apk.yml`
- Test: `pilot/flutter_phone_loop/test/r46_upgrade_golden_contract_test.dart`

**Interfaces:**
- Version `0.4.15+16` / Android versionCode `2016`.
- Phone Golden adds required A-stage gates:
  - `F8_RUNTIME_LINEAGE`
  - `F9_QUERY_VECTOR_IDENTITY`
  - `F10_CONTEXT_BUDGET`
- `F11_CITATION_LINEAGE` is reserved for R4.6-B unless A has exact source-lineage/citation data sufficient to test it truthfully. It must not be marked PASS as a placeholder.

- [ ] **Step 1: Write failing upgrade/Golden/CI contract tests**

```dart
test('R4.6-A advances in-place version and keeps identity/signing/model guards', () async {
  final pubspec = await File('pubspec.yaml').readAsString();
  final workflow = await File('../../.github/workflows/pocketgallery-phone-pilot-apk.yml').readAsString();
  final setup = await File('lib/services/model_setup_service.dart').readAsString();
  expect(pubspec, contains('version: 0.4.15+16'));
  expect(workflow, contains('feature/phone-pilot-r46-runtime-lineage'));
  expect(workflow, contains('test "$VERSION_CODE" -ge 2016'));
  expect(workflow, contains('81af4a5ef94c236774f0e193b2a4b248805b36c14cc36e2a56df8e451a712541'));
  expect(setup, contains('if (!FlutterGemma.hasActiveModel())'));
  expect(setup, contains('if (!FlutterGemma.hasActiveEmbedder())'));
});

test('Phone Golden requires R4.6-A lineage identity and budget gates', () async {
  final golden = await File('lib/services/golden_test_runner.dart').readAsString();
  expect(golden, contains('F8_RUNTIME_LINEAGE'));
  expect(golden, contains('F9_QUERY_VECTOR_IDENTITY'));
  expect(golden, contains('F10_CONTEXT_BUDGET'));
  expect(golden, isNot(contains("F11_CITATION_LINEAGE', passed: true")));
});
```

- [ ] **Step 2: Run and verify RED**

```bash
flutter test test/r46_upgrade_golden_contract_test.dart
```

Expected: FAIL because version/Golden/CI gates are not yet R4.6-A.

- [ ] **Step 3: Bump version and extend CI branch/version gates**

Set:

```yaml
version: 0.4.15+16
```

Add `feature/phone-pilot-r46-runtime-lineage` to the Phone Pilot workflow push branch list. Change APK version check to `-ge 2016`. Preserve application ID and canonical signer exactly; do not rename signing key/cache or generate a new keystore.

- [ ] **Step 4: Add Phone Golden F8–F10 using real runtime records**

F8: after the real chat turn, load its R4.6 `traceId` and require trace status complete plus required ACTIVE event kinds.

F9: require the query embedding ID stored for the trace to equal the `embedding_id` referenced by the ACTIVE vector-search event/candidate lineage, and fingerprint/value metadata to come from the captured query embedding row. Do not re-run EmbeddingGemma inside this assertion.

F10: require a persisted prompt-budget row with `total_prefill_tokens + output_reserve_tokens <= model_context_limit`, non-negative remaining capacity and internally consistent component sum.

Overall `PHONE_FUNCTION_LOOP = PASS` is printed only if every required F1–F10 passes. If F8/F9/F10 fails, show the exact failing stage.

- [ ] **Step 5: Run the entire Flutter verification suite fresh**

From `pilot/flutter_phone_loop`:

```bash
flutter analyze
flutter test
```

Expected: Analyze 0 issues; all R2–R4.6-A tests pass, with zero skipped regressions that are supposed to run in CI.

- [ ] **Step 6: Build and independently inspect arm64 APK locally/CI**

```bash
flutter build apk --debug --target-platform android-arm64 --split-per-abi
cp build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk build/app/outputs/flutter-apk/app-debug.apk
AAPT="$(find "$ANDROID_HOME/build-tools" -type f -name aapt | sort -V | tail -1)"
"$AAPT" dump badging build/app/outputs/flutter-apk/app-debug.apk | head -1
unzip -Z1 build/app/outputs/flutter-apk/app-debug.apk | grep -E '^lib/[^/]+/.*\.so$' | sed -E 's#^lib/([^/]+)/.*#\1#' | sort -u
APKSIGNER="$(find "$ANDROID_HOME/build-tools" -type f -name apksigner | sort -V | tail -1)"
"$APKSIGNER" verify --verbose --print-certs build/app/outputs/flutter-apk/app-debug.apk
sha256sum build/app/outputs/flutter-apk/app-debug.apk
```

Expected:
- package `com.qujindai.pocketgallery_phone_pilot.r3`;
- versionCode `2016`;
- only `arm64-v8a`;
- signer SHA-256 exactly `81af4a5ef94c236774f0e193b2a4b248805b36c14cc36e2a56df8e451a712541`;
- APK SHA produced and saved in artifact sidecar.

- [ ] **Step 7: Run both GitHub Actions workflows on the exact R4.6-A head**

Required workflows:
- `PocketGallery Phone Pilot APK`
- `Android Debug APK`

Do not use an older green run. Confirm the workflow head SHA equals the final R4.6-A commit and every required step is success. Download the Phone Pilot artifact, independently verify ZIP digest, APK SHA, package/version/ABI/signature again, then produce direct APK + `.sha256` + evidence links for the user.

- [ ] **Step 8: Record physical-phone acceptance boundary**

CI completion is **not** physical runtime completion. User should install R4.6-A as an in-place update without uninstalling, confirm models/OAuth/knowledge/chat state persist, run Phone Golden F1–F10, and inspect at least one real `RAG Lineage` trace. Until real phone evidence is supplied, report `BUILD/REGRESSION = PASS` and `PHONE_FUNCTION_LOOP = UNVERIFIED`, not PASS.

- [ ] **Step 9: Commit final gate changes**

```bash
git add pilot/flutter_phone_loop/pubspec.yaml pilot/flutter_phone_loop/lib/services/golden_test_runner.dart pilot/flutter_phone_loop/lib/ui/model_settings_page.dart .github/workflows/pocketgallery-phone-pilot-apk.yml pilot/flutter_phone_loop/test/r46_upgrade_golden_contract_test.dart
git commit -m "build: gate R4.6-A phone pilot"
```

---

## Plan Self-Review Checklist

Before execution begins, the implementing agent must confirm:

- [ ] Every R4.6-A acceptance item from the frozen spec maps to a task above.
- [ ] No R4.6-B full deep-stage page or R4.6-C experiment algorithm is implemented early.
- [ ] No task calls `clear()` on R4.5 production vector/observation data during migration.
- [ ] No healthy R4.5 body vector is re-embedded during migration.
- [ ] ACTIVE retrieval never calls a text-query vector helper after the query vector has been captured.
- [ ] Query vector generation occurs exactly once per knowledge-enabled turn.
- [ ] New import lineage records exact data; legacy data uses NULL/legacy labels instead of invented offsets.
- [ ] Vector READY requires Generated + Persisted + Indexed + Search Verified.
- [ ] Unsupported generation metrics remain NULL/not-exposed instead of guessed.
- [ ] Existing historical R4.1–R4.5 traces remain readable through fallback navigation.
- [ ] Package ID, signer, model cache and OAuth persistence gates remain unchanged.
- [ ] Version is monotonic: `0.4.15+16` / versionCode `2016`.
- [ ] Physical phone PASS is not claimed from CI alone.

## R4.6-A Exit Criteria

R4.6-A is ready for R4.6-B planning only when all of the following are true:

1. A real knowledge-enabled chat turn creates a complete or failed-but-inspectable R4.6 trace from `trace.started` through generation/citation lifecycle.
2. `Chunk` and `Embedding` have distinct persistent identities and one chunk can own multiple embedding rows.
3. The exact ACTIVE query vector is generated once, persisted, and passed unchanged to explicit vector search.
4. Existing healthy R4.5 body vectors migrate without re-embedding and without altering rollback DBs.
5. New TXT/MD/PDF imports record truthful parse/section/chunk provenance; unavailable legacy details remain explicitly unknown.
6. Router and Evidence decisions persist values, rule outcomes, selections and drop reasons.
7. Context budget from the real model path is persisted and proves prefill stays within model capacity.
8. Vector health is based on generated/persisted/indexed/search-verified ACTIVE state, not observation-row count.
9. Dashboard shell displays the truthful ten-stage topology and real captured status without fabricating B-stage details.
10. Full Flutter regression suite, arm64 build, package/version/ABI/signing/SHA gates and native Android regression pass on the exact final head.
11. A signed in-place APK is produced for phone acceptance, but phone runtime remains explicitly unverified until actual device evidence exists.
