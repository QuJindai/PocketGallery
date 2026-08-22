# PocketGallery P0B Knowledge Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the first independently testable PocketGallery knowledge subsystem: deterministic TXT/Markdown ingestion, SHA-256 deduplication, chunking, Room3/SQLite FTS5 persistence, and local Top-K retrieval while keeping the Google Gallery upstream pin untouched.

**Architecture:** PocketGallery code stays under `com.google.ai.edge.gallery.pocketgallery.knowledge` and is delivered through the downstream overlay. Pure parsing/chunking/hash logic is JVM-testable. Persistence uses Room3 3.0.1 with `BundledSQLiteDriver` and an external-content FTS5 table; a narrow upstream patch adds only the required Gradle dependencies. A dedicated Android instrumentation smoke test proves FTS5 really works on Android rather than merely compiling.

**Tech Stack:** Kotlin 2.2.0, JDK 21, Android SDK 37.0, Room3 3.0.1, androidx.sqlite 2.7.0 `BundledSQLiteDriver`, KSP 2.3.6, JUnit 4, AndroidX instrumentation, Bash/Git patching, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-08-21-pocketgallery-a-route-design.md`

## Global Constraints

- Upstream remains exactly `google-ai-edge/gallery@ec7fee19e3b7aad9991105e549d544233ea0b97f` throughout P0B.
- Android minimum remains API 31 (Android 12+); compile SDK remains 37.0.
- PocketGallery-owned Kotlin code lives in `com.google.ai.edge.gallery.pocketgallery.*`.
- Real documents, model weights, OAuth tokens, signing keys, and private data never enter the public repository; tests use synthetic fixtures only.
- P0B does not add PDF, Office formats, embeddings, vector search, RAG prompting, UI, MCP, Agent auto-tool selection, or model changes.
- Google upstream files are not copied wholesale into the overlay merely to add dependencies; tracked upstream modifications are represented as narrow patch files.
- Database runtime uses `BundledSQLiteDriver` so FTS5 availability does not depend on OEM system SQLite builds.
- P0B must keep the existing APK build green and must add a real Android FTS5 smoke test.

---

## File Map

### Downstream infrastructure

- `scripts/overlay/apply.sh` — apply tracked upstream patches, then copy PocketGallery overlay files.
- `scripts/verify/test_apply_overlay.sh` — verify both patch application and additive overlay copying.
- `patches/upstream/0001-add-room3-knowledge-dependencies.patch` — add Room3 runtime/compiler and bundled SQLite dependencies to Gallery's app Gradle file only.

### Knowledge core

- `overlay/Android/src/app/src/main/java/com/google/ai/edge/gallery/pocketgallery/knowledge/model/KnowledgeModels.kt` — public domain models and ingest/search results.
- `overlay/Android/src/app/src/main/java/com/google/ai/edge/gallery/pocketgallery/knowledge/hash/Sha256.kt` — deterministic SHA-256 helper.
- `overlay/Android/src/app/src/main/java/com/google/ai/edge/gallery/pocketgallery/knowledge/parser/DocumentParser.kt` — parser contract and normalized document/section types.
- `overlay/Android/src/app/src/main/java/com/google/ai/edge/gallery/pocketgallery/knowledge/parser/TextDocumentParser.kt` — UTF-8 TXT parser with BOM removal.
- `overlay/Android/src/app/src/main/java/com/google/ai/edge/gallery/pocketgallery/knowledge/parser/MarkdownDocumentParser.kt` — Markdown parser preserving heading-derived section identity.
- `overlay/Android/src/app/src/main/java/com/google/ai/edge/gallery/pocketgallery/knowledge/parser/ParserRegistry.kt` — MIME/name based parser selection.
- `overlay/Android/src/app/src/main/java/com/google/ai/edge/gallery/pocketgallery/knowledge/chunk/DocumentChunker.kt` — deterministic paragraph-aware chunking.
- `overlay/Android/src/app/src/main/java/com/google/ai/edge/gallery/pocketgallery/knowledge/search/KnowledgeQuery.kt` — query normalization and FTS/LIKE routing.

### Persistence

- `overlay/Android/src/app/src/main/java/com/google/ai/edge/gallery/pocketgallery/knowledge/db/KnowledgeEntities.kt` — document, chunk and FTS5 entities.
- `overlay/Android/src/app/src/main/java/com/google/ai/edge/gallery/pocketgallery/knowledge/db/KnowledgeDao.kt` — insert, dedupe lookup, delete, FTS and short-query fallback DAO operations.
- `overlay/Android/src/app/src/main/java/com/google/ai/edge/gallery/pocketgallery/knowledge/db/KnowledgeDatabase.kt` — Room3 database builder using `BundledSQLiteDriver`.
- `overlay/Android/src/app/src/main/java/com/google/ai/edge/gallery/pocketgallery/knowledge/store/KnowledgeStore.kt` — persistence abstraction used by ingestion/search logic.
- `overlay/Android/src/app/src/main/java/com/google/ai/edge/gallery/pocketgallery/knowledge/store/RoomKnowledgeStore.kt` — Room-backed store.
- `overlay/Android/src/app/src/main/java/com/google/ai/edge/gallery/pocketgallery/knowledge/intake/KnowledgeIngestor.kt` — hash → dedupe → parse → chunk → persist orchestration.
- `overlay/Android/src/app/src/main/java/com/google/ai/edge/gallery/pocketgallery/knowledge/search/KnowledgeRetriever.kt` — Top-K retrieval orchestration.

### Tests / fixtures

- `overlay/Android/src/app/src/test/java/com/google/ai/edge/gallery/pocketgallery/knowledge/hash/Sha256Test.kt`
- `overlay/Android/src/app/src/test/java/com/google/ai/edge/gallery/pocketgallery/knowledge/parser/DocumentParserTest.kt`
- `overlay/Android/src/app/src/test/java/com/google/ai/edge/gallery/pocketgallery/knowledge/chunk/DocumentChunkerTest.kt`
- `overlay/Android/src/app/src/test/java/com/google/ai/edge/gallery/pocketgallery/knowledge/intake/KnowledgeIngestorTest.kt`
- `overlay/Android/src/app/src/test/java/com/google/ai/edge/gallery/pocketgallery/knowledge/search/KnowledgeQueryTest.kt`
- `overlay/Android/src/app/src/androidTest/java/com/google/ai/edge/gallery/pocketgallery/knowledge/db/KnowledgeDatabaseInstrumentedTest.kt`
- `overlay/Android/src/app/src/test/resources/pocketgallery/knowledge/sample.txt`
- `overlay/Android/src/app/src/test/resources/pocketgallery/knowledge/sample.md`
- `scripts/verify/run_android_emulator_db_smoke.sh` — boot an API-35 x86_64 emulator and run only the P0B database instrumentation test.

### CI / docs

- `.github/workflows/android-debug-apk.yml` — retain APK gate; add P0B Android DB smoke job.
- `README.md` — record P0B capability boundary and test commands after the implementation is green.

---

### Task 1: Add narrow upstream patch support and Room3 dependencies

**Files:**
- Modify: `scripts/overlay/apply.sh`
- Modify: `scripts/verify/test_apply_overlay.sh`
- Create: `patches/upstream/0001-add-room3-knowledge-dependencies.patch`

**Interfaces:**
- Consumes: a clean materialized Gallery git worktree.
- Produces: `scripts/overlay/apply.sh <worktree> [overlay-dir] [patch-dir]`, which first applies every `*.patch` in lexical order using `git apply --check` / `git apply`, then copies additive overlay files.

- [ ] **Step 1: Extend the overlay test first**

Create a temporary git fixture containing `Android/src/app/build.gradle.kts` with `dependencies {}` plus a synthetic overlay file. Create a patch adding `implementation("example:dependency:1")`. Invoke `scripts/overlay/apply.sh` and assert both the tracked file patch and untracked overlay copy are present.

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
bash scripts/verify/test_apply_overlay.sh
```

Expected: FAIL because current `apply.sh` copies files but does not apply patches.

- [ ] **Step 3: Implement patch application**

`apply.sh` must use the repository root to default `PATCH_DIR="$ROOT/patches/upstream"`. For each `*.patch`, run:

```bash
git -C "$WORKTREE" apply --check "$patch"
git -C "$WORKTREE" apply "$patch"
```

Then retain the existing additive overlay copy behavior.

- [ ] **Step 4: Add the real dependency patch**

The patch changes only `Android/src/app/build.gradle.kts` and adds exactly:

```kotlin
implementation("androidx.room3:room3-runtime:3.0.1")
implementation("androidx.sqlite:sqlite-bundled:2.7.0")
ksp("androidx.room3:room3-compiler:3.0.1")
```

Do not modify Gallery's version catalog in P0B.

- [ ] **Step 5: Run script verification**

```bash
bash scripts/verify/test_materialize_upstream.sh
bash scripts/verify/test_apply_overlay.sh
bash scripts/verify/test_build_android_debug.sh
```

Expected: all print `PASS`.

- [ ] **Step 6: Commit**

Commit message:

```text
build: add narrow upstream patch support for Room3
```

---

### Task 2: Implement deterministic parser, hash and chunk primitives

**Files:**
- Create the model/hash/parser/chunk files listed in the File Map.
- Create `Sha256Test.kt`, `DocumentParserTest.kt`, `DocumentChunkerTest.kt` and synthetic resource files.

**Interfaces:**

```kotlin
data class DocumentInput(
  val sourceUri: String,
  val displayName: String,
  val mimeType: String,
  val bytes: ByteArray,
  val modifiedAtEpochMs: Long? = null,
)

data class NormalizedSection(val label: String?, val text: String)
data class NormalizedDocument(val text: String, val sections: List<NormalizedSection>)

data class KnowledgeChunk(
  val chunkId: String,
  val ordinal: Int,
  val pageOrSection: String?,
  val text: String,
  val charStart: Int,
  val charEnd: Int,
  val tokenEstimate: Int,
)

interface DocumentParser {
  fun supports(input: DocumentInput): Boolean
  fun parse(input: DocumentInput): NormalizedDocument
}
```

- [ ] **Step 1: Write SHA-256 failing tests**

Assert UTF-8 bytes for `PocketGallery` produce a fixed lowercase 64-hex digest; assert identical byte arrays produce identical digests and a one-byte change changes the digest.

- [ ] **Step 2: Run targeted SHA test and verify RED**

```bash
cd .work/gallery/Android/src
./gradlew --no-daemon testDebugUnitTest --tests '*Sha256Test'
```

Expected: compilation failure because `Sha256` does not exist.

- [ ] **Step 3: Implement `Sha256.hex(bytes)`**

Use `MessageDigest.getInstance("SHA-256")`; no Android API dependency.

- [ ] **Step 4: Write parser failing tests**

TXT requirements: UTF-8, optional UTF-8 BOM removed, CRLF normalized to LF, text otherwise preserved.

Markdown requirements: normalized full text remains readable; ATX headings (`#` through `######`) start new logical sections; section labels exclude the `#` markers; body before the first heading is allowed with `label=null`.

Registry requirements: accept `text/plain`, `text/markdown`, `.txt`, `.md`, `.markdown`; unsupported types fail with an explicit `UnsupportedDocumentTypeException`.

- [ ] **Step 5: Implement parsers and registry; rerun parser tests**

```bash
./gradlew --no-daemon testDebugUnitTest --tests '*DocumentParserTest'
```

Expected: PASS.

- [ ] **Step 6: Write chunker failing tests**

Default configuration:

```kotlin
DocumentChunker(maxChars = 1200, overlapChars = 150)
```

Assertions: empty/blank documents produce zero chunks; short input produces one chunk; long input produces multiple deterministic chunks; `charStart < charEnd`; adjacent chunks overlap without exceeding 150 characters; chunk IDs are deterministic SHA-256 values derived from `documentSha256 + ordinal + text`; Markdown section labels are carried to chunks when known.

- [ ] **Step 7: Implement chunker and rerun tests**

Token estimate is deterministic integer ceiling of `text.length / 4.0`; P0B does not add a tokenizer dependency.

- [ ] **Step 8: Run all local unit tests**

```bash
./gradlew --no-daemon testDebugUnitTest
```

Expected: PASS / no failures.

- [ ] **Step 9: Commit**

Commit message:

```text
feat: add deterministic knowledge parsing and chunking
```

---

### Task 3: Add Room3 schema and prove FTS5 on Android

**Files:**
- Create: `KnowledgeEntities.kt`, `KnowledgeDao.kt`, `KnowledgeDatabase.kt`, `KnowledgeDatabaseInstrumentedTest.kt`.

**Interfaces:**

`KnowledgeDocumentEntity` columns:

```text
documentId, sourceUri, displayName, mimeType, sha256(unique), sizeBytes,
importedAtEpochMs, modifiedAtEpochMs, parseStatus, parseError
```

`KnowledgeChunkEntity` columns:

```text
rowid INTEGER PRIMARY KEY AUTOGENERATE, chunkId(unique), documentId(indexed),
ordinal, pageOrSection, text, charStart, charEnd, tokenEstimate
```

The FTS table is external-content FTS5 over `KnowledgeChunkEntity.text`:

```kotlin
@Entity(tableName = "knowledge_chunks_fts")
@Fts5(
  contentEntity = KnowledgeChunkEntity::class,
  contentRowId = "rowid",
  tokenizer = FtsOptions.TOKENIZER_TRIGRAM,
)
data class KnowledgeChunkFts(val text: String)
```

Room creates synchronization triggers; writes go to `knowledge_chunks`, not directly to the FTS table.

- [ ] **Step 1: Write the Android instrumentation test first**

Use `InstrumentationRegistry.getInstrumentation().targetContext` and:

```kotlin
Room.inMemoryDatabaseBuilder(context, KnowledgeDatabase::class.java)
  .setDriver(BundledSQLiteDriver())
  .build()
```

Insert one synthetic document plus chunks containing English and Chinese text. Assert:

1. SHA lookup returns the document.
2. FTS query for `manufacturing` returns the expected chunk.
3. FTS trigram query for `智能制造` returns the Chinese chunk.
4. deleting the document cascades chunks and the FTS result disappears.

- [ ] **Step 2: Compile the instrumentation test and verify RED**

```bash
./gradlew --no-daemon assembleDebugAndroidTest
```

Expected: compilation failure because Room entities/database/DAO do not exist.

- [ ] **Step 3: Implement entities, DAO and database**

`KnowledgeDatabase` is version `1`, `exportSchema = false`, and production construction uses:

```kotlin
Room.databaseBuilder(context, KnowledgeDatabase::class.java, "pocketgallery-knowledge.db")
  .setDriver(BundledSQLiteDriver())
  .build()
```

DAO includes document insert/find/delete, chunk insert, FTS search, and text LIKE fallback. FTS search joins the FTS rowid to `knowledge_chunks.rowid` and then to `knowledge_documents.documentId`, returning document name and source metadata with each hit.

- [ ] **Step 4: Recompile Android tests**

```bash
./gradlew --no-daemon assembleDebugAndroidTest
```

Expected: PASS.

- [ ] **Step 5: Add emulator smoke script**

`scripts/verify/run_android_emulator_db_smoke.sh` installs/uses `system-images;android-35;default;x86_64`, creates `pocketgallery_p0b_api35`, boots it headless, waits for `sys.boot_completed=1`, then runs only:

```text
com.google.ai.edge.gallery.pocketgallery.knowledge.db.KnowledgeDatabaseInstrumentedTest
```

Always terminate the emulator process on script exit.

- [ ] **Step 6: Run the smoke test in CI and require PASS**

The GitHub runner, not a mock, is the acceptance environment for FTS5 runtime behavior.

- [ ] **Step 7: Commit**

Commit message:

```text
feat: add Room3 FTS5 knowledge database
```

---

### Task 4: Implement ingestion dedupe and retrieval orchestration

**Files:**
- Create: `KnowledgeStore.kt`, `RoomKnowledgeStore.kt`, `KnowledgeIngestor.kt`, `KnowledgeRetriever.kt`, `KnowledgeQuery.kt`.
- Create: `KnowledgeIngestorTest.kt`, `KnowledgeQueryTest.kt`.

**Interfaces:**

```kotlin
sealed interface IngestResult {
  data class Imported(val documentId: String, val chunkCount: Int) : IngestResult
  data class Duplicate(val existingDocumentId: String) : IngestResult
}

data class KnowledgeSearchHit(
  val chunkId: String,
  val documentId: String,
  val displayName: String,
  val sourceUri: String,
  val ordinal: Int,
  val pageOrSection: String?,
  val text: String,
  val score: Double?,
)

interface KnowledgeStore {
  suspend fun findDocumentIdBySha256(sha256: String): String?
  suspend fun insertDocumentWithChunks(document: KnowledgeDocumentRecord, chunks: List<KnowledgeChunk>)
  suspend fun searchFts(matchQuery: String, limit: Int): List<KnowledgeSearchHit>
  suspend fun searchLike(escapedNeedle: String, limit: Int): List<KnowledgeSearchHit>
}
```

- [ ] **Step 1: Write ingest tests with a fake store**

Assert the exact pipeline order is hash → dedupe lookup → parser → chunker → persistence. Duplicate bytes return `IngestResult.Duplicate` and do not parse/chunk/write again. Unsupported MIME/name returns a typed failure and does not persist partial data.

- [ ] **Step 2: Verify RED, implement minimal ingestor, verify GREEN**

```bash
./gradlew --no-daemon testDebugUnitTest --tests '*KnowledgeIngestorTest'
```

- [ ] **Step 3: Write query normalization tests**

Rules:

1. trim leading/trailing whitespace;
2. collapse internal whitespace;
3. empty query is rejected;
4. escaped double quotes are safe for FTS phrase syntax;
5. normalized query with fewer than 3 Unicode code points uses LIKE fallback because the trigram tokenizer cannot match shorter terms;
6. three-or-more code points use FTS5.

- [ ] **Step 4: Implement `KnowledgeQuery` and `KnowledgeRetriever`**

Top-K is clamped to `1..50`, default `8`. FTS queries are phrase-quoted; LIKE fallback escapes `%`, `_`, and `\\` before DAO invocation.

- [ ] **Step 5: Implement `RoomKnowledgeStore`**

Map domain records to Room entities. Keep database details out of parser/intake packages. Insert document + chunks through one Room write transaction so partial imports are not visible.

- [ ] **Step 6: Run the complete local unit suite**

```bash
./gradlew --no-daemon testDebugUnitTest
```

Expected: PASS.

- [ ] **Step 7: Commit**

Commit message:

```text
feat: add knowledge ingestion dedupe and retrieval
```

---

### Task 5: Integrate CI gates and produce the P0B APK

**Files:**
- Modify: `.github/workflows/android-debug-apk.yml`
- Modify: `README.md`

**Interfaces:**
- Existing `android-debug` job remains the APK-producing gate.
- New `knowledge-db-smoke` job runs after `android-debug` and proves Room3/FTS5 runtime behavior on API 35.

- [ ] **Step 1: Strengthen the build command**

The build path must run:

```bash
./gradlew --no-daemon testDebugUnitTest assembleDebug assembleDebugAndroidTest
```

and still assert/upload the same debug APK path.

- [ ] **Step 2: Add `knowledge-db-smoke`**

Use JDK 21 and the existing Android setup. Install the API-35 default x86_64 system image, materialize/apply the pinned Gallery baseline, and invoke `scripts/verify/run_android_emulator_db_smoke.sh`.

- [ ] **Step 3: Keep pristine Google lint informational**

Do not convert the known upstream `9 errors / 150 warnings` into PocketGallery failures. P0B-owned code quality is enforced by compiler/unit/instrumented tests; an incremental PocketGallery-only lint baseline can be added when UI/RAG files begin.

- [ ] **Step 4: Update README only after CI is green**

Document exactly what P0B now proves: TXT/MD normalization, deterministic chunking, SHA-256 dedupe, Room3/BundledSQLite FTS5, Chinese/English smoke retrieval, and no PDF/RAG/UI claim yet.

- [ ] **Step 5: Open PR and verify current-head CI**

PR title:

```text
P0B: add local knowledge core and FTS5 retrieval
```

Required evidence before merge:

- three downstream script tests PASS;
- `testDebugUnitTest` PASS;
- `assembleDebug` PASS;
- `assembleDebugAndroidTest` PASS;
- API-35 `KnowledgeDatabaseInstrumentedTest` PASS;
- APK artifact exists and uploads;
- upstream lint report still uploads separately;
- repository diff contains no model weights, secrets or real documents.

---

## P0B Exit Criteria

1. `feature/p0b-knowledge-core` is based on the merged P0A `main` commit.
2. The upstream Gallery commit is unchanged.
3. TXT and Markdown are parsed deterministically using synthetic fixtures.
4. SHA-256 dedupe prevents duplicate document persistence.
5. Deterministic chunks preserve ordinal, offsets and section labels.
6. Room3 3.0.1 database builds with `BundledSQLiteDriver` 2.7.0.
7. FTS5 runtime retrieval is proven on a real Android emulator, including a Chinese query of at least three code points.
8. Short queries route to a safe LIKE fallback rather than silently returning no trigram result.
9. Existing Gallery APK still builds and is uploaded as a GitHub artifact.
10. P0B makes no false claim that PDF, Evidence/RAG prompting, UI or Markdown answer export are implemented.

## Next Milestone Boundary

P0C begins only after P0B is green. It adds Android SAF import + PDF parsing + “我的资料/搜索” minimal UI on top of the stable Knowledge Core. P0D then adds Evidence Pack + `LlmProvider` integration + knowledge Q&A + source cards + Markdown answer export.