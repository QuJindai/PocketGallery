# PocketGallery P0C SAF / PDF / Knowledge UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add model-independent Android SAF document import, PDF text parsing, document management and minimal “我的资料 / 搜索” UI on top of the green P0B Knowledge Core, while keeping failures in PDF/emulator/UI code isolated from the proven P0B path.

**Architecture:** P0C keeps all substantive code under `com.google.ai.edge.gallery.pocketgallery.*`. SAF is an Android adapter that converts persisted `content://` URIs into bounded `DocumentInput`; PDF parsing is behind a `PdfTextExtractor` interface and uses AndroidX PDF `1.0.0-alpha19` only in the Android adapter. The existing parser/ingestor/retriever remain the domain core. A narrow upstream navigation patch exposes one PocketGallery route from the Gallery drawer; the route itself does not initialize any LLM model.

**Tech Stack:** Kotlin 2.2.0, JDK 21, Android SDK 37.0, minSdk 31, Jetpack Compose, Hilt, Room3 3.0.1, BundledSQLiteDriver 2.7.0, AndroidX PDF `1.0.0-alpha19`, JUnit 4, AndroidX instrumentation, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-08-21-pocketgallery-a-route-design.md`

## Global Constraints

- Upstream remains exactly `google-ai-edge/gallery@ec7fee19e3b7aad9991105e549d544233ea0b97f` throughout P0C.
- P0C starts from the P0B head after its current-head CI is green; no P0C change is committed back onto the P0B branch.
- Android minimum remains API 31 (Android 12+); compile/target SDK remains 37.0.
- P0C is model-independent: no LiteRT-LM initialization, model download or true-model inference is required to import, parse, list or search knowledge.
- TXT, Markdown and PDF are the only accepted document types in P0C. Office, OCR, embeddings, RAG prompting, source cards and Markdown answer export remain out of scope.
- AndroidX PDF is pinned to `1.0.0-alpha19` and must be wrapped behind PocketGallery interfaces because the API is still Alpha.
- PDF compatibility must be proven on API 31 and API 35 emulator paths before the PDF feature is treated as usable.
- Imported files are limited to 64 MiB in P0C so the existing byte-array ingestion contract cannot OOM the app. Unknown-length streams are aborted once the bound is exceeded.
- SAF read permission is persisted when the provider allows it. Failure to persist permission does not prevent immediate import, but is reported to the UI.
- Scanned/image-only PDFs with no extractable text return a clear `NO_TEXT_CONTENT` result; P0C does not silently import an empty document and does not add OCR.
- The public repository contains only synthetic fixtures; no real documents, model weights, tokens, secrets or signing keys.
- P0B emulator behavior is not refactored during P0C. New emulator scripts copy its proven explicit-AVD-home/fail-fast contract rather than modifying the green runner.

## Anti-Stall Contract

Every stage has a hard boundary:

1. **Dependency risk first:** AndroidX PDF is added and compiled before parser/UI work.
2. **Runtime risk second:** PDF text extraction must pass a tiny instrumented fixture on API 31 and API 35 before SAF/UI depend on it.
3. **No blind emulator waits:** every new emulator runner exports a unique `ANDROID_AVD_HOME`, checks `emulator -list-avds`, fails if the emulator process exits, and has a bounded boot deadline.
4. **No model coupling:** P0C tests never wait for LiteRT-LM/Gemma initialization.
5. **Fast tests before emulator:** unit/build gates run before emulator jobs so deterministic code failures surface before expensive Android boot.
6. **Logs always survive:** emulator log, `adb devices -l`, and boot properties are uploaded on failure.
7. **One-risk commits:** dependency, parser, SAF, store, ViewModel, UI, navigation and CI changes are separate commits so any regression is bisectable and revertible.

---

## File Map

### AndroidX PDF dependency / runtime adapter

- `patches/upstream/0002-add-androidx-pdf-dependencies.patch` — add pinned `pdf-core` and `pdf-document-service` dependencies only.
- `overlay/Android/src/app/src/main/java/com/google/ai/edge/gallery/pocketgallery/knowledge/pdf/PdfTextExtractor.kt` — stable PocketGallery PDF extraction contract.
- `overlay/Android/src/app/src/main/java/com/google/ai/edge/gallery/pocketgallery/knowledge/pdf/AndroidxPdfTextExtractor.kt` — AndroidX PDF implementation.
- `overlay/Android/src/app/src/main/java/com/google/ai/edge/gallery/pocketgallery/knowledge/parser/PdfDocumentParser.kt` — convert pages into normalized sections labelled `Page N`.

### SAF adapter

- `overlay/Android/src/app/src/main/java/com/google/ai/edge/gallery/pocketgallery/knowledge/intake/SafDocumentReader.kt` — metadata, bounded stream read and URI permission adapter.
- `overlay/Android/src/app/src/main/java/com/google/ai/edge/gallery/pocketgallery/knowledge/intake/DocumentImportCoordinator.kt` — SAF read → `DocumentInput` → `KnowledgeIngestor` orchestration.

### Persistence / document management

- Modify `KnowledgeDao.kt`, `KnowledgeEntities.kt`, `KnowledgeStore.kt`, `RoomKnowledgeStore.kt` for document summaries/list/delete.

### UI / state

- `overlay/Android/src/app/src/main/java/com/google/ai/edge/gallery/pocketgallery/knowledge/di/PocketGalleryKnowledgeModule.kt` — Hilt providers.
- `overlay/Android/src/app/src/main/java/com/google/ai/edge/gallery/pocketgallery/ui/knowledge/KnowledgeViewModel.kt` — import/list/delete/search state machine.
- `overlay/Android/src/app/src/main/java/com/google/ai/edge/gallery/pocketgallery/ui/knowledge/PocketGalleryKnowledgeScreen.kt` — SAF launcher and screen shell.
- `overlay/Android/src/app/src/main/java/com/google/ai/edge/gallery/pocketgallery/ui/knowledge/KnowledgeScreenContent.kt` — pure Compose content driven entirely by state/callbacks.
- `overlay/Android/src/app/src/main/res/values/pocketgallery_strings.xml` — P0C strings.

### Narrow Gallery integration

- `patches/upstream/0003-add-pocketgallery-knowledge-route.patch` — only `HomeScreen.kt` + `GalleryNavGraph.kt`; add drawer entry and route.

### Tests / verification

- Unit tests for suspend parser migration, PDF parser fake extractor, bounded SAF stream, document list/delete, coordinator and ViewModel.
- `AndroidxPdfTextExtractorInstrumentedTest.kt` — real PDF service runtime against a synthetic two-page PDF.
- `KnowledgeScreenContentInstrumentedTest.kt` — basic semantics for document/search states without a model.
- `scripts/verify/run_android_pdf_smoke.sh` — bounded API-specific PDF runtime test.
- `.github/workflows/android-debug-apk.yml` — retain P0B jobs; add P0C PDF matrix only after fast build succeeds.

---

### Task 1: Pin AndroidX PDF and prove dependency compatibility

**Files:**
- Create: `patches/upstream/0002-add-androidx-pdf-dependencies.patch`
- Modify: `scripts/verify/test_apply_overlay.sh`

**Interfaces:**
- Produces exactly these app dependencies after patching:
  - `androidx.pdf:pdf-core:1.0.0-alpha19`
  - `androidx.pdf:pdf-document-service:1.0.0-alpha19`

- [ ] **Step 1: Extend the overlay fixture test first**

Add a synthetic second patch in `test_apply_overlay.sh` and assert lexical patch ordering. The test must fail until `0002` is accepted by the real patch chain.

- [ ] **Step 2: Run the patch test RED**

Run:

```bash
bash scripts/verify/test_apply_overlay.sh
```

Expected: FAIL because the PDF dependency patch does not exist yet.

- [ ] **Step 3: Add the narrow dependency patch**

Patch only Gallery's `Android/src/app/build.gradle.kts` and add:

```kotlin
implementation("androidx.pdf:pdf-core:1.0.0-alpha19")
implementation("androidx.pdf:pdf-document-service:1.0.0-alpha19")
```

Do not add `pdf-viewer`, `pdf-viewer-fragment`, OCR or editing artifacts in P0C.

- [ ] **Step 4: Run fast verification and full compile**

Run:

```bash
bash scripts/verify/test_apply_overlay.sh
bash scripts/build/build_android_debug.sh
```

Expected: script PASS and Gradle `testDebugUnitTest assembleDebug assembleDebugAndroidTest` PASS.

- [ ] **Step 5: Commit**

```bash
git add patches/upstream/0002-add-androidx-pdf-dependencies.patch scripts/verify/test_apply_overlay.sh
git commit -m "build: pin AndroidX PDF for P0C"
```

---

### Task 2: Make parsing suspendable and add a PDF extraction adapter

**Files:**
- Modify: `knowledge/parser/DocumentParser.kt`
- Modify: `knowledge/parser/ParserRegistry.kt`
- Modify: `knowledge/intake/KnowledgeIngestor.kt`
- Modify existing parser/ingestor unit tests
- Create: `knowledge/pdf/PdfTextExtractor.kt`
- Create: `knowledge/pdf/AndroidxPdfTextExtractor.kt`
- Create: `knowledge/parser/PdfDocumentParser.kt`
- Create: `test/.../knowledge/parser/PdfDocumentParserTest.kt`
- Create: `androidTest/.../knowledge/pdf/AndroidxPdfTextExtractorInstrumentedTest.kt`

**Interfaces:**

```kotlin
data class PdfPageText(val pageNumber: Int, val text: String)

interface PdfTextExtractor {
  suspend fun extract(sourceUri: String): List<PdfPageText>
}

interface DocumentParser {
  fun supports(input: DocumentInput): Boolean
  suspend fun parse(input: DocumentInput): NormalizedDocument
}
```

`ParserRegistry.parse()` becomes `suspend`; `KnowledgeIngestor.ingest()` is already suspend and therefore remains the orchestration boundary.

- [ ] **Step 1: Convert existing parser tests to call suspend APIs**

Use `runBlocking` in JUnit 4 tests and keep every current TXT/Markdown assertion unchanged.

- [ ] **Step 2: Run unit tests RED**

Run:

```bash
./gradlew --no-daemon testDebugUnitTest
```

Expected: compile/test failure until parser contracts are suspendable.

- [ ] **Step 3: Make `DocumentParser` and `ParserRegistry.parse` suspend**

Text and Markdown implementations remain deterministic and contain no dispatcher/thread logic.

- [ ] **Step 4: Add a fake-extractor PDF parser test**

The fake returns:

```kotlin
listOf(
  PdfPageText(1, "PocketGallery first page"),
  PdfPageText(2, "PocketGallery second page"),
)
```

Assert the normalized document contains two sections labelled `Page 1` and `Page 2`, and that the combined text contains both page texts in order.

- [ ] **Step 5: Implement `PdfDocumentParser`**

Support `application/pdf` or `.pdf`; call `PdfTextExtractor`; trim page text; discard blank pages; throw `NoTextContentException` if all pages are blank.

- [ ] **Step 6: Implement the AndroidX adapter behind the interface**

Use `SandboxedPdfLoader(context)` and `Uri.parse(sourceUri)`. For each page `0 until document.pageCount`, call `getPageContent(page)` and concatenate only `PdfPageTextContent.text`. Always close the `PdfDocument` in `use`/`finally`.

- [ ] **Step 7: Add a real instrumented two-page PDF fixture test**

Decode a fixed Base64 synthetic PDF into `context.cacheDir`, open it with `Uri.fromFile`, extract text and assert both page markers are present. The test must use the real `AndroidxPdfTextExtractor`, not a fake.

- [ ] **Step 8: Run unit + AndroidTest APK compile**

Run:

```bash
./gradlew --no-daemon testDebugUnitTest assembleDebugAndroidTest
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add overlay/Android/src/app/src/main/java/com/google/ai/edge/gallery/pocketgallery/knowledge overlay/Android/src/app/src/test overlay/Android/src/app/src/androidTest
git commit -m "feat: add suspend PDF parser adapter"
```

---

### Task 3: Prove PDF runtime on API 31 and API 35 before SAF/UI work

**Files:**
- Create: `scripts/verify/run_android_pdf_smoke.sh`
- Modify: `.github/workflows/android-debug-apk.yml`

**Interfaces:**

```bash
POCKETGALLERY_ANDROID_API=31 bash scripts/verify/run_android_pdf_smoke.sh
POCKETGALLERY_ANDROID_API=35 bash scripts/verify/run_android_pdf_smoke.sh
```

- [ ] **Step 1: Copy the proven P0B emulator safety contract without refactoring P0B**

The new script must:

```bash
export ANDROID_AVD_HOME="$ROOT/.work/avd-pdf-api${API}"
```

Create one unique AVD, assert `emulator -list-avds | grep -Fxq "$AVD_NAME"`, launch in background, record `$EMULATOR_PID`, and poll both `adb` visibility and `kill -0 "$EMULATOR_PID"`.

- [ ] **Step 2: Bound all waits**

Use a 180-second adb appearance deadline and a 180-second `sys.boot_completed=1` deadline. If the process exits or either deadline expires, print:

```bash
emulator -list-avds
adb devices -l
adb shell getprop sys.boot_completed || true
tail -n 200 "$EMULATOR_LOG" || true
```

Then exit non-zero immediately.

- [ ] **Step 3: Run only the PDF extractor test**

Use:

```bash
./gradlew --no-daemon connectedDebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.class=com.google.ai.edge.gallery.pocketgallery.knowledge.pdf.AndroidxPdfTextExtractorInstrumentedTest
```

- [ ] **Step 4: Add a two-value CI matrix**

The job runs only after `android-debug` succeeds:

```yaml
strategy:
  fail-fast: false
  matrix:
    api: [31, 35]
```

Install the corresponding `system-images;android-${{ matrix.api }};default;x86_64`, run the script, and upload logs with `if: always()`.

- [ ] **Step 5: Do not proceed until both runtime jobs are green**

If API 31 fails because AndroidX PDF's backport path is unavailable, stop P0C PDF implementation and record the exact exception. Do not hide the failure by raising `minSdk`.

- [ ] **Step 6: Commit after both APIs pass**

```bash
git add scripts/verify/run_android_pdf_smoke.sh .github/workflows/android-debug-apk.yml
git commit -m "test: prove PDF extraction on API 31 and 35"
```

---

### Task 4: Add bounded SAF document reading and import orchestration

**Files:**
- Create: `knowledge/intake/SafDocumentReader.kt`
- Create: `knowledge/intake/DocumentImportCoordinator.kt`
- Create: `androidTest/.../knowledge/intake/SafDocumentReaderInstrumentedTest.kt`
- Create: `test/.../knowledge/intake/DocumentImportCoordinatorTest.kt`
- Modify: `KnowledgeIngestor.kt`

**Interfaces:**

```kotlin
data class SafDocument(
  val sourceUri: String,
  val displayName: String,
  val mimeType: String,
  val bytes: ByteArray,
  val modifiedAtEpochMs: Long?,
  val permissionPersisted: Boolean,
)

sealed interface SafReadResult {
  data class Success(val document: SafDocument) : SafReadResult
  data class TooLarge(val sizeBytes: Long?) : SafReadResult
  data class Failed(val message: String) : SafReadResult
}

class SafDocumentReader(
  private val context: Context,
  private val maxBytes: Long = 64L * 1024L * 1024L,
) {
  suspend fun read(uri: Uri): SafReadResult
}

class DocumentImportCoordinator(
  private val reader: SafDocumentReader,
  private val ingestor: KnowledgeIngestor,
) {
  suspend fun import(uri: Uri): ImportUiResult
}
```

- [ ] **Step 1: Write a bounded stream test**

Verify an input exactly at the bound succeeds and one byte above the bound returns `TooLarge` without allocating beyond the bound.

- [ ] **Step 2: Implement metadata + bounded read on `Dispatchers.IO`**

Query display name, size and last modified; resolve MIME from `ContentResolver.getType` with extension fallback. Read in 64 KiB blocks and abort once cumulative bytes exceed 64 MiB.

- [ ] **Step 3: Persist read permission when possible**

Attempt:

```kotlin
contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
```

Catch `SecurityException` and continue immediate import with `permissionPersisted=false`.

- [ ] **Step 4: Map SAF data into the existing domain**

`DocumentImportCoordinator` creates `DocumentInput` and invokes `KnowledgeIngestor.ingest`. Map duplicate, unsupported, too-large, no-text and parse/read failures into explicit UI results.

- [ ] **Step 5: Add one Android content/file read smoke**

Use an app-owned temporary TXT file and assert metadata + bytes are correct. This test verifies the Android adapter; the system picker itself remains a UI/manual acceptance step.

- [ ] **Step 6: Run tests and commit**

```bash
./gradlew --no-daemon testDebugUnitTest assembleDebugAndroidTest
```

Expected: PASS.

Commit:

```bash
git commit -m "feat: add bounded SAF knowledge import"
```

---

### Task 5: Expose document list, chunk counts and deletion

**Files:**
- Modify: `KnowledgeEntities.kt`
- Modify: `KnowledgeDao.kt`
- Modify: `KnowledgeStore.kt`
- Modify: `RoomKnowledgeStore.kt`
- Modify: `KnowledgeDatabaseInstrumentedTest.kt`

**Interfaces:**

```kotlin
data class KnowledgeDocumentSummary(
  val documentId: String,
  val sourceUri: String,
  val displayName: String,
  val mimeType: String,
  val sizeBytes: Long,
  val importedAtEpochMs: Long,
  val modifiedAtEpochMs: Long?,
  val parseStatus: String,
  val parseError: String?,
  val chunkCount: Int,
)

interface KnowledgeStore {
  suspend fun listDocuments(): List<KnowledgeDocumentSummary>
  suspend fun deleteDocument(documentId: String)
  // existing methods unchanged
}
```

- [ ] **Step 1: Add failing database assertions**

Insert two synthetic documents with different chunk counts; assert list order is newest first and counts are correct. Delete one and assert its document/chunks/FTS results disappear via the existing cascade/content-table behavior.

- [ ] **Step 2: Add DAO summary projection**

Use `LEFT JOIN knowledge_chunks`, `COUNT(c.rowid)`, `GROUP BY d.documentId`, `ORDER BY d.importedAtEpochMs DESC`.

- [ ] **Step 3: Map projection through `RoomKnowledgeStore`**

No UI/Android dependency is allowed in the store interface.

- [ ] **Step 4: Run API-35 DB smoke and unit compile**

Expected: P0B database smoke remains green with the new list/delete assertions.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat: add knowledge document management"
```

---

### Task 6: Add a model-independent ViewModel and Hilt graph

**Files:**
- Create: `knowledge/di/PocketGalleryKnowledgeModule.kt`
- Create: `ui/knowledge/KnowledgeViewModel.kt`
- Create: `test/.../ui/knowledge/KnowledgeViewModelTest.kt`

**Interfaces:**

```kotlin
data class KnowledgeUiState(
  val documents: List<KnowledgeDocumentSummary> = emptyList(),
  val searchQuery: String = "",
  val searchResults: List<KnowledgeSearchHit> = emptyList(),
  val importing: Boolean = false,
  val searching: Boolean = false,
  val message: String? = null,
)
```

ViewModel public actions:

```kotlin
fun refreshDocuments()
fun importUris(uris: List<Uri>)
fun deleteDocument(documentId: String)
fun setSearchQuery(query: String)
fun search()
fun clearMessage()
```

- [ ] **Step 1: Test the state machine with fakes**

Cover successful import, duplicate, too-large/no-text error message, delete refresh, empty search and successful search. ViewModel tests must not require AndroidX PDF, an emulator or a model.

- [ ] **Step 2: Add Hilt singleton providers**

Provide `KnowledgeDatabase`, `KnowledgeStore`, `PdfTextExtractor`, `ParserRegistry` containing Markdown/Text/PDF parsers, `KnowledgeIngestor`, `KnowledgeRetriever`, `SafDocumentReader` and `DocumentImportCoordinator`.

- [ ] **Step 3: Ensure initialization never touches LiteRT-LM**

No `ModelManagerViewModel`, `LlmSessionManager`, model path or Hugging Face dependency is injected into P0C state.

- [ ] **Step 4: Run unit tests and commit**

```bash
./gradlew --no-daemon testDebugUnitTest
```

Expected: PASS.

Commit:

```bash
git commit -m "feat: add knowledge screen state model"
```

---

### Task 7: Build “我的资料 / 搜索” minimal Compose UI

**Files:**
- Create: `ui/knowledge/KnowledgeScreenContent.kt`
- Create: `ui/knowledge/PocketGalleryKnowledgeScreen.kt`
- Create: `res/values/pocketgallery_strings.xml`
- Create: `androidTest/.../ui/knowledge/KnowledgeScreenContentInstrumentedTest.kt`

**Interfaces:**
- `KnowledgeScreenContent` is a pure state/callback composable.
- `PocketGalleryKnowledgeScreen` owns `OpenMultipleDocuments`, collects the Hilt ViewModel state and forwards callbacks.

- [ ] **Step 1: Add UI semantics tests first**

Assert that a synthetic state shows:
- tab/action “我的资料”;
- tab/action “搜索”;
- document name + chunk count;
- search query field;
- search result document name + page/section label.

- [ ] **Step 2: Implement the screen shell**

Use a normal Material3 `Scaffold`; show two tabs. Import uses:

```kotlin
rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
  viewModel.importUris(uris)
}
```

Launch with MIME array:

```kotlin
arrayOf("text/plain", "text/markdown", "application/pdf")
```

- [ ] **Step 3: Implement “我的资料”**

Show document display name, MIME/type, human-readable size, chunk count and import status. Provide delete action with a confirmation dialog. Show progress during import and snackbar/message for imported/duplicate/failure outcomes.

- [ ] **Step 4: Implement “搜索”**

Show query field, explicit search button, loading state and Top-K cards with document name, `pageOrSection` and hit text. Do not add chat/RAG affordances in P0C.

- [ ] **Step 5: Run UI AndroidTest APK compile and tests**

```bash
./gradlew --no-daemon testDebugUnitTest assembleDebugAndroidTest
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git commit -m "feat: add local knowledge browse and search UI"
```

---

### Task 8: Add a narrow Gallery drawer route without creating model coupling

**Files:**
- Create: `patches/upstream/0003-add-pocketgallery-knowledge-route.patch`
- Modify: `scripts/verify/test_apply_overlay.sh`

**Interfaces:**
- `HomeScreen` gains one callback: `onKnowledgeClicked: () -> Unit`.
- `GalleryNavGraph` gains one route constant and one `composable` that renders `PocketGalleryKnowledgeScreen`.
- No Gallery model task is created and no model is initialized on this route.

- [ ] **Step 1: Extend patch verification first**

Assert the materialized worktree contains the PocketGallery route and HomeScreen callback only after applying the third patch.

- [ ] **Step 2: Patch the Gallery drawer**

Add one drawer tile labelled “PocketGallery / 本地资料” using an existing Material icon. Its click closes the drawer and invokes `onKnowledgeClicked`.

- [ ] **Step 3: Patch Gallery navigation**

Add:

```kotlin
private const val ROUTE_POCKETGALLERY_KNOWLEDGE = "pocketgallery_knowledge"
```

Pass `onKnowledgeClicked = { navController.navigate(ROUTE_POCKETGALLERY_KNOWLEDGE) }` into HomeScreen and add the route composable.

- [ ] **Step 4: Verify no model initialization dependency**

The route must not be nested under `ROUTE_MODEL`, `CustomTaskScreen`, `ModelManager`, or any model-selection callback.

- [ ] **Step 5: Run script tests + full APK build**

```bash
bash scripts/verify/test_apply_overlay.sh
bash scripts/build/build_android_debug.sh
```

Expected: PASS and debug APK exists.

- [ ] **Step 6: Commit**

```bash
git commit -m "feat: expose PocketGallery knowledge route"
```

---

### Task 9: P0C acceptance, CI evidence and README

**Files:**
- Modify: `README.md`
- Modify only if needed: `.github/workflows/android-debug-apk.yml`

- [ ] **Step 1: Require current-head fast build**

Evidence:
- downstream script tests PASS;
- `testDebugUnitTest` PASS;
- `assembleDebug` PASS;
- `assembleDebugAndroidTest` PASS;
- APK artifact exists/uploads.

- [ ] **Step 2: Require current-head P0B DB smoke**

API-35 `KnowledgeDatabaseInstrumentedTest` remains PASS.

- [ ] **Step 3: Require current-head P0C PDF matrix**

`AndroidxPdfTextExtractorInstrumentedTest` PASS on API 31 and API 35. A failure on either API blocks the P0C PDF claim.

- [ ] **Step 4: Review public-repo safety**

Diff must contain no model weights, real documents, APK/AAB binaries, tokens, secrets or signing material. PDF fixture is synthetic Base64 only.

- [ ] **Step 5: Update README only after all gates are green**

Document exactly what P0C proves: SAF TXT/MD/PDF import, 64 MiB bound, AndroidX PDF text extraction, document list/delete, local search, minimal “我的资料 / 搜索” UI, and model-independent operation. Explicitly state that OCR and RAG remain unimplemented.

- [ ] **Step 6: Open P0C PR as draft and attach failure-prevention note**

PR title:

```text
P0C: add SAF PDF import and local knowledge UI
```

The PR body must include the API31/API35 PDF results and explain that the P0B AVD-home failure class is guarded by explicit AVD homes and visibility checks in every new emulator runner.

---

## P0C Exit Criteria

1. P0B remains green and unchanged except its final README-only closeout commit.
2. AndroidX PDF dependency is pinned and isolated behind `PdfTextExtractor`.
3. Real PDF text extraction passes on API 31 and API 35 emulator jobs.
4. TXT, Markdown and PDF can be imported from Android SAF.
5. Imports larger than 64 MiB fail cleanly before unbounded allocation.
6. Duplicate SHA-256 documents are not persisted twice.
7. Image-only PDFs fail with a clear no-text result; OCR is not falsely claimed.
8. “我的资料” lists local documents and chunk counts and can delete a document.
9. “搜索” returns existing FTS5/LIKE hits with document and page/section evidence.
10. Opening the PocketGallery knowledge route does not initialize or require a model.
11. Offline local document list/search continues to work after import.
12. GitHub Actions produces the debug APK and preserves emulator diagnostics.
13. No P0D features are mixed into P0C.

## Next Milestone Boundary

P0D starts only after P0C is green. P0D adds the Evidence Pack, `LlmProvider` adapter to Gallery's `LlmSessionManager`, knowledge Q&A, source cards and Markdown answer export. P0D must keep its RAG orchestration unit-testable with a fake `LlmProvider` so true model runtime remains a separate acceptance layer.