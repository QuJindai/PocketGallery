# PocketGallery R4 Chat-first Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade PocketGallery from a RAG validation screen into a daily-usable on-device chat assistant with persistent multi-turn Gemma 4 chat and optional local-knowledge augmentation.

**Architecture:** Add a persistent chat/session layer and a `ChatOrchestrator` between UI, Gemma, and retrieval. Split retrieval from generation so the same chat supports three modes: model-only, automatic knowledge augmentation, and forced knowledge grounding. Replace the single pilot page with a three-tab shell while preserving all R3 model files, OAuth credentials, FTS5/vector databases, Android identity, and signing chain.

**Tech Stack:** Flutter 3.47+/Dart 3.13, `flutter_gemma` 1.6.x + LiteRT-LM, `flutter_gemma_rag_sqlite`, `sqlite3`, Material 3, existing Hugging Face Device OAuth and GitHub Actions arm64/signing pipeline.

**Spec:** `docs/superpowers/specs/2026-08-27-pocketgallery-r4-chat-first-design.md`

## Global Constraints

- Android applicationId remains exactly `com.qujindai.pocketgallery_phone_pilot.r3`.
- R3 signing certificate remains exactly SHA256 `f317c1a0998e8e6b148e86fecb7996d5f64736ca5497886045ef7b8a10aa67f4`.
- Existing Gemma 4 / EmbeddingGemma model assets and application Documents directory must be reused in place.
- Existing `pocketgallery_fts5.db`, `pocketgallery_vectors.db`, Hugging Face secure-storage keys, imported documents, and indexes must not be dropped or recreated.
- Database migration is additive only; new tables/columns are allowed, destructive migration is not.
- `FlutterGemma.hasActiveModel()` / `hasActiveEmbedder()` true must bypass all corresponding network download paths.
- Default chat mode is `auto`; available modes are `modelOnly`, `auto`, and `knowledge`.
- R4 first release version is `0.4.0+7`.
- APK remains `arm64-v8a` only.
- Existing Phone Golden Test remains available under Advanced/Diagnostics.

---

## File Structure

New focused files:

- `pilot/flutter_phone_loop/lib/chat/chat_models.dart` — chat modes, sessions, messages, message evidence snapshots, model-gateway interface.
- `pilot/flutter_phone_loop/lib/chat/chat_session_store.dart` — additive SQLite persistence for sessions/messages.
- `pilot/flutter_phone_loop/lib/chat/context_budgeter.dart` — deterministic history selection under the 8192-token model budget.
- `pilot/flutter_phone_loop/lib/chat/chat_orchestrator.dart` — mode routing, retrieval decision, persistence, citation validation.
- `pilot/flutter_phone_loop/lib/services/knowledge_retriever.dart` — FTS5 + Embedding + Hybrid/Rerank + Evidence without generation.
- `pilot/flutter_phone_loop/lib/services/gemma_chat_service.dart` — persistent multi-turn FlutterGemma chat implementation.
- `pilot/flutter_phone_loop/lib/ui/main_shell.dart` — three-tab NavigationBar shell.
- `pilot/flutter_phone_loop/lib/ui/chat_page.dart` — daily-use chat UI.
- `pilot/flutter_phone_loop/lib/ui/knowledge_page.dart` — document/index management UI.
- `pilot/flutter_phone_loop/lib/ui/model_settings_page.dart` — model/OAuth/status/diagnostics UI.

Existing files modified:

- `lib/core/models.dart` — knowledge-document metadata and retrieval bundle types.
- `lib/services/lexical_fts_store.dart` — injectable DB for tests, additive document metadata, scope-aware FTS5, document deletion/listing.
- `lib/services/semantic_store.dart` — scope-aware semantic candidate filtering.
- `lib/services/knowledge_engine.dart` — expose retriever/document management while retaining diagnostic compatibility.
- `lib/main.dart` — construct R4 services and launch `MainShell`.
- `lib/ui/home_page.dart` — no longer the app root; retained temporarily only until its useful model/diagnostic logic is moved.
- `pubspec.yaml` — bump to `0.4.0+7`; no new runtime package is required.

---

### Task 1: Chat domain model and persistent session store

**Files:**
- Create: `pilot/flutter_phone_loop/lib/chat/chat_models.dart`
- Create: `pilot/flutter_phone_loop/lib/chat/chat_session_store.dart`
- Create: `pilot/flutter_phone_loop/test/r4_chat_session_store_test.dart`

**Interfaces:**
- Produces: `enum ChatMode { modelOnly, auto, knowledge }`
- Produces: `KnowledgeScope.all()` and `KnowledgeScope.documents(Set<String>)`
- Produces: `ChatSession`, `ChatMessage`, `ChatRole`
- Produces: `ChatSessionStore.createSession`, `listSessions`, `getSession`, `updateSession`, `appendMessage`, `messages`, `clearMessages`, `deleteSession`
- `ChatSessionStore({Database? database})` accepts `sqlite3.openInMemory()` for tests and opens `pocketgallery_chat.db` in app Documents otherwise.

- [ ] **Step 1: Write the failing persistence tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:pocketgallery_phone_pilot/chat/chat_models.dart';
import 'package:pocketgallery_phone_pilot/chat/chat_session_store.dart';

void main() {
  test('session mode, scope, and messages survive store re-open', () async {
    final db = sqlite3.openInMemory();
    final store = ChatSessionStore(database: db);
    await store.initialize();

    final session = await store.createSession(title: 'DSA');
    await store.updateSession(
      session.id,
      mode: ChatMode.knowledge,
      scope: KnowledgeScope.documents({'doc-a'}),
    );
    await store.appendMessage(ChatMessage.user(
      id: 'm1', sessionId: session.id, text: '31 03 51 01',
    ));
    await store.appendMessage(ChatMessage.assistant(
      id: 'm2', sessionId: session.id, text: '车辆仍在处理中 [E1]',
      evidenceJson: '[{"anchor":"E1","chunkId":"c1"}]',
      citedAnchorsJson: '["E1"]',
      retrievalMode: 'knowledge',
    ));

    final loaded = await store.getSession(session.id);
    final messages = await store.messages(session.id);
    expect(loaded!.mode, ChatMode.knowledge);
    expect(loaded.scope.documentIds, {'doc-a'});
    expect(messages.map((m) => m.text),
        ['31 03 51 01', '车辆仍在处理中 [E1]']);
    db.dispose();
  });

  test('schema creation is additive and does not reuse R3 knowledge DB names', () async {
    final source = await File('lib/chat/chat_session_store.dart').readAsString();
    expect(source, contains('pocketgallery_chat.db'));
    expect(source, isNot(contains('DROP TABLE')));
    expect(source, isNot(contains('pocketgallery_fts5.db')));
    expect(source, isNot(contains('pocketgallery_vectors.db')));
  });
}
```

- [ ] **Step 2: Run the test and verify RED**

Run:
```bash
cd pilot/flutter_phone_loop
flutter test test/r4_chat_session_store_test.dart
```
Expected: FAIL because `chat_models.dart` and `chat_session_store.dart` do not exist.

- [ ] **Step 3: Implement the domain types and additive SQLite schema**

Core model shape:
```dart
enum ChatMode { modelOnly, auto, knowledge }
enum ChatRole { user, assistant }

class KnowledgeScope {
  const KnowledgeScope._(this.documentIds);
  const KnowledgeScope.all() : documentIds = null;
  const KnowledgeScope.documents(Set<String> ids) : documentIds = ids;
  final Set<String>? documentIds;
  bool get isAll => documentIds == null;
}

class ChatSession {
  const ChatSession({
    required this.id,
    required this.title,
    required this.mode,
    required this.scope,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id;
  final String title;
  final ChatMode mode;
  final KnowledgeScope scope;
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

SQLite tables:
```sql
CREATE TABLE IF NOT EXISTS chat_sessions (
  session_id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  mode TEXT NOT NULL,
  knowledge_scope_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS chat_messages (
  message_id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  role TEXT NOT NULL,
  text TEXT NOT NULL,
  created_at TEXT NOT NULL,
  retrieval_mode TEXT,
  evidence_json TEXT,
  cited_anchors_json TEXT,
  FOREIGN KEY(session_id) REFERENCES chat_sessions(session_id) ON DELETE CASCADE
);
```
Use timestamp+counter IDs (`s_${DateTime.now().microsecondsSinceEpoch}` / `m_...`) so no new UUID dependency is needed.

- [ ] **Step 4: Run store tests and full regression**

```bash
flutter test test/r4_chat_session_store_test.dart
flutter test
```
Expected: new tests PASS and all R2/R3 regression tests remain PASS.

- [ ] **Step 5: Commit**

```bash
git add pilot/flutter_phone_loop/lib/chat pilot/flutter_phone_loop/test/r4_chat_session_store_test.dart
git commit -m "feat: add persistent local chat sessions"
```

---

### Task 2: Document metadata and scoped FTS5 retrieval

**Files:**
- Modify: `pilot/flutter_phone_loop/lib/core/models.dart`
- Modify: `pilot/flutter_phone_loop/lib/services/lexical_fts_store.dart`
- Create: `pilot/flutter_phone_loop/test/r4_knowledge_scope_test.dart`

**Interfaces:**
- Produces: `KnowledgeDocument { documentId, sourceName, chunkCount, textAvailable }`
- Produces: `LexicalFtsStore.listDocuments()`
- Produces: `LexicalFtsStore.removeDocument(String documentId)`
- Changes: `LexicalFtsStore.search(String query, {int topK = 12, KnowledgeScope scope = const KnowledgeScope.all()})`
- Changes: `LexicalFtsStore({Database? database})` for deterministic in-memory tests.

- [ ] **Step 1: Write RED tests for document metadata and scope**

```dart
test('FTS5 scope only returns requested documents', () async {
  final db = sqlite3.openInMemory();
  final store = LexicalFtsStore(database: db);
  await store.initialize();
  await store.replaceDocument(ImportedDocument(
    documentId: 'a', sourceName: 'a.txt', sha256: 'a',
    chunks: [PgChunk(id: 'a1', documentId: 'a', sourceName: 'a.txt', locator: 'text', ordinal: 0, text: 'vehicle model calibration result')],
  ));
  await store.replaceDocument(ImportedDocument(
    documentId: 'b', sourceName: 'b.txt', sha256: 'b',
    chunks: [PgChunk(id: 'b1', documentId: 'b', sourceName: 'b.txt', locator: 'text', ordinal: 0, text: 'vehicle model network test')],
  ));

  final hits = await store.search(
    'vehicle model',
    scope: const KnowledgeScope.documents({'b'}),
  );
  expect(hits, isNotEmpty);
  expect(hits.every((h) => h.chunk.documentId == 'b'), isTrue);
});

test('zero-chunk imports still appear in document metadata', () async {
  final store = LexicalFtsStore(database: sqlite3.openInMemory());
  await store.initialize();
  await store.replaceDocument(const ImportedDocument(
    documentId: 'scan', sourceName: 'scan.pdf', sha256: 'scan', chunks: [],
  ));
  final docs = await store.listDocuments();
  expect(docs.single.documentId, 'scan');
  expect(docs.single.chunkCount, 0);
  expect(docs.single.textAvailable, isFalse);
});
```

- [ ] **Step 2: Run the test and verify RED**

```bash
flutter test test/r4_knowledge_scope_test.dart
```
Expected: FAIL because document metadata, DB injection, and `scope` are not implemented.

- [ ] **Step 3: Implement additive metadata/backfill and SQL scope filtering**

Add table:
```sql
CREATE TABLE IF NOT EXISTS pg_documents (
  document_id TEXT PRIMARY KEY,
  source_name TEXT NOT NULL,
  sha256 TEXT NOT NULL DEFAULT '',
  chunk_count INTEGER NOT NULL DEFAULT 0
);
```
After table creation, backfill R3 documents without touching chunks:
```sql
INSERT OR IGNORE INTO pg_documents(document_id, source_name, chunk_count)
SELECT document_id, MIN(source_name), COUNT(*)
FROM pg_chunks
GROUP BY document_id;
```

For document scope, append SQL such as:
```dart
final ids = scope.documentIds?.toList() ?? const <String>[];
final scopeSql = ids.isEmpty && !scope.isAll
    ? ' AND 1 = 0 '
    : scope.isAll
        ? ''
        : ' AND document_id IN (${List.filled(ids.length, '?').join(',')}) ';
```
The final query keeps `MATCH ?`, scope arguments, BM25 ordering, and `LIMIT ?` in that order.

`removeDocument` deletes corresponding FTS rows, plain chunk rows, and metadata in one transaction; semantic deletion is handled by `KnowledgeEngine` later.

- [ ] **Step 4: Run scoped store tests and regressions**

```bash
flutter test test/r4_knowledge_scope_test.dart
flutter test
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add pilot/flutter_phone_loop/lib/core/models.dart pilot/flutter_phone_loop/lib/services/lexical_fts_store.dart pilot/flutter_phone_loop/test/r4_knowledge_scope_test.dart
git commit -m "feat: add scoped knowledge document metadata"
```

---

### Task 3: Scope-aware semantic retrieval and reusable KnowledgeRetriever

**Files:**
- Modify: `pilot/flutter_phone_loop/lib/services/semantic_store.dart`
- Create: `pilot/flutter_phone_loop/lib/services/knowledge_retriever.dart`
- Create: `pilot/flutter_phone_loop/test/r4_knowledge_retriever_test.dart`

**Interfaces:**
- Changes: `SemanticStore.search(String query, {int topK = 12, KnowledgeScope scope = const KnowledgeScope.all()})`
- Produces: `RetrievalBundle` with `lexicalHits`, `semanticHits`, `hybridHits`, `evidence`, `lexicalOnly`, `relevantForAuto`
- Produces: `KnowledgeRetriever.retrieve(String query, {KnowledgeScope scope = const KnowledgeScope.all(), int limit = 8})`
- Auto relevance threshold: `0.03`; a dual-channel top hit is relevant regardless of exact threshold.

- [ ] **Step 1: Write RED tests for deterministic automatic-mode relevance**

Use pure synthetic hits so tests never need the embedding runtime:
```dart
test('auto retrieval accepts dual-channel evidence', () {
  final bundle = RetrievalBundle(
    lexicalHits: const [], semanticHits: const [],
    hybridHits: [HybridHit(
      chunk: chunk, score: 0.02,
      channels: {'fts5', 'embedding'}, lexicalRank: 1, semanticRank: 1,
    )],
    evidence: [EvidenceItem(anchor: 'E1', chunk: chunk, score: 0.02)],
    lexicalOnly: false,
  );
  expect(bundle.relevantForAuto, isTrue);
});

test('auto retrieval rejects weak single-channel noise', () {
  final bundle = RetrievalBundle(
    lexicalHits: const [], semanticHits: const [],
    hybridHits: [HybridHit(
      chunk: chunk, score: 0.018,
      channels: {'fts5'}, lexicalRank: 1, semanticRank: null,
    )],
    evidence: [EvidenceItem(anchor: 'E1', chunk: chunk, score: 0.018)],
    lexicalOnly: true,
  );
  expect(bundle.relevantForAuto, isFalse);
});
```
Also add a source-contract test asserting semantic candidate oversampling happens before document filtering.

- [ ] **Step 2: Run tests and verify RED**

```bash
flutter test test/r4_knowledge_retriever_test.dart
```
Expected: FAIL because `RetrievalBundle` and `KnowledgeRetriever` do not exist.

- [ ] **Step 3: Implement semantic scope and retrieval bundle**

Semantic scope uses a sufficiently large candidate set before filtering:
```dart
final candidateK = scope.isAll ? topK : (topK * 8).clamp(topK, 96);
final rows = await FlutterGemma.rag.searchSimilar(
  query: query,
  topK: candidateK,
  threshold: 0.0,
);
// resolve chunk, then filter by documentId, then take(topK)
```

`RetrievalBundle.relevantForAuto`:
```dart
bool get relevantForAuto {
  if (evidence.isEmpty || hybridHits.isEmpty) return false;
  final top = hybridHits.first;
  return top.channels.length > 1 || top.score >= 0.03;
}
```

`KnowledgeRetriever.retrieve` always runs FTS5; runs semantic only when `FlutterGemma.hasActiveEmbedder()`; fuses with existing `HybridRanker`; builds Evidence with existing `EvidencePackBuilder`.

- [ ] **Step 4: Run tests and full suite**

```bash
flutter test test/r4_knowledge_retriever_test.dart
flutter test
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add pilot/flutter_phone_loop/lib/services/semantic_store.dart pilot/flutter_phone_loop/lib/services/knowledge_retriever.dart pilot/flutter_phone_loop/test/r4_knowledge_retriever_test.dart
git commit -m "feat: split scoped local knowledge retrieval"
```

---

### Task 4: Context budgeter and real multi-turn Gemma chat service

**Files:**
- Create: `pilot/flutter_phone_loop/lib/chat/context_budgeter.dart`
- Create: `pilot/flutter_phone_loop/lib/services/gemma_chat_service.dart`
- Create: `pilot/flutter_phone_loop/test/r4_gemma_chat_contract_test.dart`

**Interfaces:**
- Produces: `ContextBudgeter.selectHistory(List<ChatMessage> messages, {int evidenceTokens = 0})`
- Produces: `abstract class ChatModelGateway`
- Produces: `GemmaChatService implements ChatModelGateway`
- Produces: `sendTurn({required sessionId, required priorMessages, required userText, required evidence, required bool forceKnowledge})`
- Produces: `resetSession(String sessionId)` and `close()`.

- [ ] **Step 1: Write RED tests for history budgeting and multi-turn contract**

```dart
test('budgeter keeps newest turns and discards oldest first', () {
  final messages = List.generate(20, (i) => ChatMessage.user(
    id: 'm$i', sessionId: 's', text: '第$i轮 ' + ('内容' * 250),
  ));
  final selected = const ContextBudgeter().selectHistory(messages);
  expect(selected.last.id, 'm19');
  expect(selected.length, lessThan(messages.length));
  expect(selected.first.id, isNot('m0'));
});

test('Gemma chat service uses one persistent InferenceChat per active session', () async {
  final source = await File('lib/services/gemma_chat_service.dart').readAsString();
  expect(source, contains('InferenceChat? _chat'));
  expect(source, contains('_activeSessionId'));
  expect(source, contains('addQueryChunk'));
  expect(source, contains('generateChatResponse'));
  expect(source, contains('isUser: false'));
});
```

- [ ] **Step 2: Run tests and verify RED**

```bash
flutter test test/r4_gemma_chat_contract_test.dart
```
Expected: FAIL because files/interfaces do not exist.

- [ ] **Step 3: Implement conservative 8192-token history budgeting**

Use a deterministic estimator with no tokenizer dependency:
```dart
int estimateTokens(String text) {
  final cjk = RegExp(r'[\u3400-\u9FFF]').allMatches(text).length;
  final nonCjk = text.length - cjk;
  return cjk + (nonCjk / 4).ceil() + 8;
}
```
Budget constants:
```dart
static const modelMaxTokens = 8192;
static const systemReserve = 700;
static const outputReserve = 700;
static const evidenceReserveMax = 1900;
static const safetyReserve = 600;
```
Select newest messages backwards until the available history budget is exhausted; reverse the selected list before replay.

- [ ] **Step 4: Implement `GemmaChatService` using FlutterGemma native chat history**

Load active model once:
```dart
_model ??= await FlutterGemma.getActiveModel(
  maxTokens: 8192,
  preferredBackend: PreferredBackend.gpu,
);
```
Create chat with a general system instruction that understands per-turn mode markers:
```text
You are PocketGallery, an on-device assistant. Continue the user's multi-turn conversation naturally.
When a user turn contains [LOCAL_KNOWLEDGE], use that evidence for local factual claims and cite [E#].
When a turn contains [FORCED_KNOWLEDGE], answer local factual claims only from the supplied evidence.
Never invent an [E#] that is not present in the supplied evidence.
```

When session changes or app restarts, create a fresh `InferenceChat` and replay budgeted stored messages with:
```dart
await _chat!.addQueryChunk(Message.text(
  text: message.text,
  isUser: message.role == ChatRole.user,
));
```
For the current turn, inject evidence only into the model-facing user payload; persistent user message remains clean:
```dart
final payload = evidence.isEmpty
    ? userText
    : '${forceKnowledge ? '[FORCED_KNOWLEDGE]' : '[LOCAL_KNOWLEDGE]'}\n'
      '${const EvidencePackBuilder().toPromptContext(evidence)}\n\n'
      'USER MESSAGE:\n$userText';
```
`InferenceChat.generateChatResponse()` already commits assistant text to native chat history; return `TextResponse.token.trim()`.

- [ ] **Step 5: Run tests and commit**

```bash
flutter test test/r4_gemma_chat_contract_test.dart
flutter test
git add pilot/flutter_phone_loop/lib/chat/context_budgeter.dart pilot/flutter_phone_loop/lib/services/gemma_chat_service.dart pilot/flutter_phone_loop/test/r4_gemma_chat_contract_test.dart
git commit -m "feat: add persistent multi-turn Gemma chat"
```

---

### Task 5: ChatOrchestrator with model-only, auto, and forced-knowledge modes

**Files:**
- Create: `pilot/flutter_phone_loop/lib/chat/chat_orchestrator.dart`
- Create: `pilot/flutter_phone_loop/test/r4_chat_orchestrator_test.dart`

**Interfaces:**
- Consumes: `ChatSessionStore`, `KnowledgeRetriever`, `ChatModelGateway`, `CitationResolver`
- Produces: `ChatOrchestrator.sendMessage(String sessionId, String text)` returning stored assistant `ChatMessage`
- Produces: `newSession()`, `clearSession()`, `setMode()`, `setScope()` convenience methods.

- [ ] **Step 1: Write RED orchestration tests with fakes**

Cover all routing rules:
```dart
test('modelOnly never invokes retrieval', () async {
  final fx = Fixture(mode: ChatMode.modelOnly);
  await fx.orchestrator.sendMessage(fx.sessionId, '你好');
  expect(fx.retriever.calls, 0);
  expect(fx.model.calls, 1);
  expect(fx.model.lastEvidence, isEmpty);
});

test('auto falls back to pure model when evidence is weak', () async {
  final fx = Fixture(mode: ChatMode.auto, relevant: false);
  await fx.orchestrator.sendMessage(fx.sessionId, '给我讲个笑话');
  expect(fx.retriever.calls, 1);
  expect(fx.model.lastEvidence, isEmpty);
});

test('auto injects relevant local evidence', () async {
  final fx = Fixture(mode: ChatMode.auto, relevant: true);
  await fx.orchestrator.sendMessage(fx.sessionId, '这份文档的结论是什么');
  expect(fx.model.lastEvidence.single.anchor, 'E1');
});

test('forced knowledge with no evidence never calls model', () async {
  final fx = Fixture(mode: ChatMode.knowledge, evidence: const []);
  final reply = await fx.orchestrator.sendMessage(fx.sessionId, '回答本地资料');
  expect(fx.model.calls, 0);
  expect(reply.text, contains('本地资料不足'));
});
```
Add a second-turn test proving the model gateway receives the first user+assistant pair in `priorMessages`.

- [ ] **Step 2: Run tests and verify RED**

```bash
flutter test test/r4_chat_orchestrator_test.dart
```
Expected: FAIL because `ChatOrchestrator` does not exist.

- [ ] **Step 3: Implement send flow exactly once**

Algorithm:
```dart
final session = await store.getSession(sessionId) ?? throw StateError(...);
final prior = await store.messages(sessionId);
final user = ChatMessage.user(...);
await store.appendMessage(user);

RetrievalBundle? retrieval;
var useEvidence = false;
if (session.mode != ChatMode.modelOnly) {
  retrieval = await retriever.retrieve(text, scope: session.scope);
  useEvidence = session.mode == ChatMode.knowledge || retrieval.relevantForAuto;
}

if (session.mode == ChatMode.knowledge &&
    (retrieval == null || retrieval.evidence.isEmpty)) {
  final reply = ChatMessage.assistant(... text: '本地资料不足，当前知识库范围内没有找到足够证据。');
  await store.appendMessage(reply);
  return reply;
}

final evidence = useEvidence ? retrieval!.evidence : const <EvidenceItem>[];
var answer = await model.sendTurn(...);
```
If Evidence was used, resolve anchors. If the model emitted no valid anchor, append a neutral source footer rather than inventing claim content:
```dart
if (evidence.isNotEmpty && citationResolver.extract(answer, evidence).isEmpty) {
  answer = '$answer\n\n本轮本地证据来源：[${evidence.first.anchor}]';
}
```
Persist `evidence_json` and `cited_anchors_json` on the assistant message so old citations remain stable.

- [ ] **Step 4: Run orchestrator and regression tests**

```bash
flutter test test/r4_chat_orchestrator_test.dart
flutter test
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add pilot/flutter_phone_loop/lib/chat/chat_orchestrator.dart pilot/flutter_phone_loop/test/r4_chat_orchestrator_test.dart
git commit -m "feat: orchestrate chat with optional local knowledge"
```

---

### Task 6: Refactor KnowledgeEngine into compatibility facade and document manager

**Files:**
- Modify: `pilot/flutter_phone_loop/lib/services/knowledge_engine.dart`
- Modify: `pilot/flutter_phone_loop/lib/services/golden_test_runner.dart`
- Create: `pilot/flutter_phone_loop/test/r4_knowledge_engine_compat_test.dart`

**Interfaces:**
- `KnowledgeEngine.retriever` exposes `KnowledgeRetriever`.
- `KnowledgeEngine.listDocuments()` delegates to lexical metadata.
- `KnowledgeEngine.removeDocument(documentId)` removes semantic IDs first when embedder is active, then FTS/plain metadata.
- `KnowledgeEngine.rebuildDocumentEmbedding(documentId)` and `rebuildAllEmbeddings()` are idempotent.
- Existing `importPath`, `ask`, `lexicalStore`, `semanticStore`, `ranker`, and diagnostic Gemma path remain usable by Golden Test.

- [ ] **Step 1: Write RED compatibility tests**

```dart
test('R4 keeps R3 diagnostic interfaces while exposing retriever', () async {
  final source = await File('lib/services/knowledge_engine.dart').readAsString();
  expect(source, contains('final KnowledgeRetriever retriever'));
  expect(source, contains('Future<ImportedDocument> importPath'));
  expect(source, contains('Future<KnowledgeAnswer> ask'));
  expect(source, contains('Future<List<KnowledgeDocument>> listDocuments'));
  expect(source, contains('Future<void> removeDocument'));
  expect(source, contains('Future<void> rebuildAllEmbeddings'));
});
```

- [ ] **Step 2: Run test and verify RED**

```bash
flutter test test/r4_knowledge_engine_compat_test.dart
```
Expected: FAIL until new facade methods exist.

- [ ] **Step 3: Implement compatibility facade**

`ask()` becomes a thin diagnostic wrapper over `retriever.retrieve(question)` plus existing `GemmaService.answer`, preserving old `KnowledgeAnswer` output. Do not route daily chat through this method.

`removeDocument`:
```dart
final ids = await lexicalStore.chunkIdsForDocument(documentId);
if (FlutterGemma.hasActiveEmbedder() && ids.isNotEmpty) {
  await semanticStore.removeIds(ids);
}
await lexicalStore.removeDocument(documentId);
```

`rebuildDocumentEmbedding` fetches chunks for that document, removes their old vector IDs, then adds them; `rebuildAllEmbeddings` calls existing `syncSemanticIndex` after clearing vector store only when explicitly invoked from diagnostics.

Update Golden Test only where method signatures gained optional scope arguments; do not weaken F1-F6 gates.

- [ ] **Step 4: Run full suite**

```bash
flutter test
flutter analyze
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add pilot/flutter_phone_loop/lib/services/knowledge_engine.dart pilot/flutter_phone_loop/lib/services/golden_test_runner.dart pilot/flutter_phone_loop/test/r4_knowledge_engine_compat_test.dart
git commit -m "refactor: expose knowledge retrieval and document management"
```

---

### Task 7: Three-tab app shell and Chat-first UI

**Files:**
- Create: `pilot/flutter_phone_loop/lib/ui/main_shell.dart`
- Create: `pilot/flutter_phone_loop/lib/ui/chat_page.dart`
- Modify: `pilot/flutter_phone_loop/lib/main.dart`
- Create: `pilot/flutter_phone_loop/test/r4_chat_ui_test.dart`

**Interfaces:**
- `MainShell` receives `KnowledgeEngine`, `ChatSessionStore`, `ChatOrchestrator`.
- Navigation destinations: `聊天`, `知识库`, `模型 / 设置`.
- Initial selected index is `0` (chat).
- `ChatPage` supports current session, history picker, new session, clear session, mode switch, document scope selector, send button, message bubbles, citation chips.

- [ ] **Step 1: Write RED widget/source tests for Chat-first behavior**

```dart
testWidgets('R4 launches on chat tab with three knowledge modes', (tester) async {
  await tester.pumpWidget(testHarness());
  expect(find.text('聊天'), findsWidgets);
  expect(find.text('纯模型'), findsOneWidget);
  expect(find.text('自动'), findsOneWidget);
  expect(find.text('强制知识库'), findsOneWidget);
  expect(find.text('Run Phone Golden Test'), findsNothing);
});

test('main no longer boots HomePage', () async {
  final main = await File('lib/main.dart').readAsString();
  expect(main, contains('MainShell'));
  expect(main, isNot(contains('home: HomePage')));
});
```

- [ ] **Step 2: Run tests and verify RED**

```bash
flutter test test/r4_chat_ui_test.dart
```
Expected: FAIL because `MainShell`/`ChatPage` do not exist.

- [ ] **Step 3: Implement `MainShell` and Chat UI**

Navigation skeleton:
```dart
Scaffold(
  body: IndexedStack(index: index, children: [chatPage, knowledgePage, modelPage]),
  bottomNavigationBar: NavigationBar(
    selectedIndex: index,
    onDestinationSelected: (value) => setState(() => index = value),
    destinations: const [
      NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: '聊天'),
      NavigationDestination(icon: Icon(Icons.library_books_outlined), label: '知识库'),
      NavigationDestination(icon: Icon(Icons.tune), label: '模型 / 设置'),
    ],
  ),
);
```

Chat page mode selector uses `SegmentedButton<ChatMode>` with three segments. Default is `ChatMode.auto`. The app bar has `新建会话` and `会话历史`; long pilot status text does not occupy the chat page.

Assistant message evidence renders as clickable `ActionChip(label: Text('[E1]'))`; tapping opens a bottom sheet with source name, locator, and chunk text from the message's persisted Evidence snapshot.

- [ ] **Step 4: Run UI and regression tests**

```bash
flutter test test/r4_chat_ui_test.dart
flutter test
flutter analyze
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add pilot/flutter_phone_loop/lib/ui/main_shell.dart pilot/flutter_phone_loop/lib/ui/chat_page.dart pilot/flutter_phone_loop/lib/main.dart pilot/flutter_phone_loop/test/r4_chat_ui_test.dart
git commit -m "feat: make PocketGallery chat-first"
```

---

### Task 8: Knowledge Library page with import, scope, delete, and reindex

**Files:**
- Create: `pilot/flutter_phone_loop/lib/ui/knowledge_page.dart`
- Modify: `pilot/flutter_phone_loop/lib/ui/main_shell.dart`
- Create: `pilot/flutter_phone_loop/test/r4_knowledge_ui_test.dart`

**Interfaces:**
- `KnowledgePage(engine: KnowledgeEngine)`.
- Displays source name, chunk count, `FTS5 READY`, Embedding state, and zero-chunk warning.
- Actions: import TXT/MD/PDF, select/unselect document for scope, delete, rebuild selected embedding, rebuild all embeddings.

- [ ] **Step 1: Write RED UI tests**

```dart
test('knowledge page contains required management actions', () async {
  final source = await File('lib/ui/knowledge_page.dart').readAsString();
  expect(source, contains('导入 TXT / MD / PDF'));
  expect(source, contains('重建 Embedding'));
  expect(source, contains('删除文档'));
  expect(source, contains('0 chunks'));
  expect(source, contains('扫描件/图片型 PDF'));
});
```

- [ ] **Step 2: Run and verify RED**

```bash
flutter test test/r4_knowledge_ui_test.dart
```
Expected: FAIL because the page does not exist.

- [ ] **Step 3: Implement document management page**

Import keeps existing behavior:
```dart
final paths = await engine.importer.pickDocumentPaths();
for (final path in paths) {
  await engine.importPath(path);
}
await _reloadDocuments();
```

Document list displays:
- `N chunks · FTS5 READY` when `N > 0`;
- `0 chunks · 未提取到文本（可能是扫描件/图片型 PDF）` when zero;
- `Embedding READY` only if embedder is active and indexing is available; otherwise `Embedding 待补建`.

Deletion requires one confirmation dialog, then `engine.removeDocument(documentId)`. It never deletes model files.

- [ ] **Step 4: Run UI/full tests**

```bash
flutter test test/r4_knowledge_ui_test.dart
flutter test
flutter analyze
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add pilot/flutter_phone_loop/lib/ui/knowledge_page.dart pilot/flutter_phone_loop/lib/ui/main_shell.dart pilot/flutter_phone_loop/test/r4_knowledge_ui_test.dart
git commit -m "feat: add local knowledge library management"
```

---

### Task 9: Model/Settings page and move Pilot diagnostics out of main flow

**Files:**
- Create: `pilot/flutter_phone_loop/lib/ui/model_settings_page.dart`
- Modify: `pilot/flutter_phone_loop/lib/ui/main_shell.dart`
- Modify: `pilot/flutter_phone_loop/lib/ui/home_page.dart`
- Create: `pilot/flutter_phone_loop/test/r4_model_settings_ui_test.dart`

**Interfaces:**
- `ModelSettingsPage(engine: KnowledgeEngine)` owns `ModelSetupService` lifecycle/OAuth state.
- Top-level shows Gemma/Embedding readiness and model setup only.
- `ExpansionTile(title: Text('高级 / 诊断'))` contains Phone Golden Test and detailed diagnostic state.

- [ ] **Step 1: Write RED tests for diagnostics relocation**

```dart
test('Golden Test is advanced-only in R4', () async {
  final settings = await File('lib/ui/model_settings_page.dart').readAsString();
  final chat = await File('lib/ui/chat_page.dart').readAsString();
  expect(settings, contains('高级 / 诊断'));
  expect(settings, contains('Run Phone Golden Test'));
  expect(chat, isNot(contains('Run Phone Golden Test')));
});
```

- [ ] **Step 2: Run and verify RED**

```bash
flutter test test/r4_model_settings_ui_test.dart
```
Expected: FAIL until model settings page exists.

- [ ] **Step 3: Move, do not rewrite, proven R3 model setup/OAuth logic**

Reuse existing `ModelSetupService`, pending OAuth lifecycle resume, device-code clipboard behavior, download progress, and `syncSemanticIndex()` callbacks. Do not change model URLs or secure-storage key names.

Use a compact status layout:
```text
Gemma 4          READY
EmbeddingGemma   READY / 授权中 / 下载中
本地知识索引      READY / lexical-only
```

Inside Advanced/Diagnostics preserve `GoldenTestRunner(engine).run()` and show F1-F6 result rows plus `PHONE_FUNCTION_LOOP` status.

After migration, `home_page.dart` may become a thin deprecated wrapper or be unused; no production route should point to it.

- [ ] **Step 4: Run full tests**

```bash
flutter test test/r4_model_settings_ui_test.dart
flutter test
flutter analyze
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add pilot/flutter_phone_loop/lib/ui/model_settings_page.dart pilot/flutter_phone_loop/lib/ui/main_shell.dart pilot/flutter_phone_loop/lib/ui/home_page.dart pilot/flutter_phone_loop/test/r4_model_settings_ui_test.dart
git commit -m "feat: move model and diagnostics into settings"
```

---

### Task 10: Upgrade contract, version bump, CI, APK, and phone-ready artifact

**Files:**
- Modify: `pilot/flutter_phone_loop/pubspec.yaml`
- Create: `pilot/flutter_phone_loop/test/r4_upgrade_contract_test.dart`
- Modify only if required by test discovery: `.github/workflows/pocketgallery-phone-pilot-apk.yml`
- Update generated evidence snapshot only if project convention requires it; static manifest snapshots remain non-blocking evidence rather than source-of-truth gates.

**Interfaces:**
- Version `0.4.0+7`.
- Package remains `com.qujindai.pocketgallery_phone_pilot.r3`.
- Signing cache key remains `pocketgallery-r3-signing-v1`.
- APK signer certificate remains `f317c1a0998e8e6b148e86fecb7996d5f64736ca5497886045ef7b8a10aa67f4`.

- [ ] **Step 1: Write final RED upgrade contract**

```dart
test('R4 is an in-place R3 upgrade and never redownloads active models', () async {
  final pubspec = await File('pubspec.yaml').readAsString();
  final bootstrap = await File('scripts/bootstrap_android.sh').readAsString();
  final setup = await File('lib/services/model_setup_service.dart').readAsString();
  final main = await File('lib/main.dart').readAsString();

  expect(pubspec, contains('version: 0.4.0+7'));
  expect(bootstrap, contains('com.qujindai.pocketgallery_phone_pilot.r3'));
  expect(setup, contains('if (!FlutterGemma.hasActiveModel())'));
  expect(setup, contains('if (!FlutterGemma.hasActiveEmbedder())'));
  expect(main, contains('MainShell'));
});

test('R4 chat data migration is additive', () async {
  final store = await File('lib/chat/chat_session_store.dart').readAsString();
  final fts = await File('lib/services/lexical_fts_store.dart').readAsString();
  expect('$store\n$fts', isNot(contains('DROP TABLE')));
  expect(fts, contains('INSERT OR IGNORE INTO pg_documents'));
});
```

- [ ] **Step 2: Run RED test before bump**

```bash
flutter test test/r4_upgrade_contract_test.dart
```
Expected: FAIL on version until `pubspec.yaml` is bumped.

- [ ] **Step 3: Bump version and run complete local/static gate set**

Change:
```yaml
version: 0.4.0+7
```
Then run:
```bash
flutter analyze
flutter test
bash scripts/bootstrap_android.sh
```
Expected: all PASS; bootstrap still emits R3 applicationId.

- [ ] **Step 4: Push and require final GitHub Actions success**

The workflow must complete all hard gates:
```text
Restore persistent R3 signing identity    PASS
Prepare persistent R3 signing identity    PASS
Analyze                                   PASS
Unit tests                                PASS
Build arm64 debug APK                     PASS
Verify R3 package, ABI and signing cert   PASS
Hash APK                                  PASS
Upload artifact                           PASS
```
Verify log values:
```text
APK_ABIS=arm64-v8a
APK_PACKAGE=com.qujindai.pocketgallery_phone_pilot.r3
APK_SIGNER_SHA256=f317c1a0998e8e6b148e86fecb7996d5f64736ca5497886045ef7b8a10aa67f4
R3_KEY_SHA256=f317c1a0998e8e6b148e86fecb7996d5f64736ca5497886045ef7b8a10aa67f4
```
Download artifact, recompute ZIP and APK SHA256 independently, and confirm APK contains only `arm64-v8a` native libraries.

- [ ] **Step 5: Commit final release metadata**

```bash
git add pilot/flutter_phone_loop/pubspec.yaml pilot/flutter_phone_loop/test/r4_upgrade_contract_test.dart
git commit -m "release: prepare PocketGallery R4 chat-first APK"
```

Final deliverable names:
```text
PocketGallery-Phone-Pilot-R4-chat-first-arm64-debug.apk
PocketGallery-Phone-Pilot-R4-chat-first-arm64-debug.apk.sha256
PocketGallery-Phone-Pilot-R4-chat-first-arm64-artifact.zip
```

---

## Plan Self-Review

### Spec coverage

- Chat-first default route: Task 7.
- Direct Gemma multi-turn chat: Tasks 4-5.
- Model-only / auto / forced knowledge: Task 5 and Task 7.
- Automatic fallback to plain model when evidence is irrelevant: Tasks 3 and 5.
- All knowledge / selected documents: Tasks 2-3 and Task 7.
- Stable clickable per-message citations: Tasks 5 and 7.
- Persistent sessions/restart recovery: Tasks 1 and 4.
- Knowledge library management: Tasks 2, 6, 8.
- Model/OAuth/diagnostics separated from chat: Task 9.
- Existing Golden Test retained: Tasks 6 and 9.
- R3 model/data/OAuth/signing compatibility: Tasks 1-3, 6, 9, 10.
- No repeated model downloads: Task 10 plus existing R3 model-cache gate.
- arm64/signing/SHA artifact: Task 10.

### Placeholder scan

No TBD/TODO/“implement later” steps remain. Collection UI is intentionally outside R4 first release per the approved spec; only the data model boundary is preserved through `KnowledgeScope`.

### Type consistency

`KnowledgeScope` is defined once in `chat_models.dart` and consumed by both lexical and semantic stores. `RetrievalBundle` is produced only by `KnowledgeRetriever`; `ChatOrchestrator` consumes it. `ChatModelGateway` is implemented by `GemmaChatService`, allowing orchestration tests to use fakes without loading a real model. Daily chat never calls `KnowledgeEngine.ask()`; that method remains a diagnostic compatibility facade for the existing Golden Test.
