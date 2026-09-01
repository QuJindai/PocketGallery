import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:pocketgallery_phone_pilot/chat/chat_models.dart';
import 'package:pocketgallery_phone_pilot/chat/chat_orchestrator.dart';
import 'package:pocketgallery_phone_pilot/chat/chat_session_store.dart';
import 'package:pocketgallery_phone_pilot/core/models.dart';
import 'package:pocketgallery_phone_pilot/lineage/generation_models.dart';
import 'package:pocketgallery_phone_pilot/services/knowledge_retriever.dart';

class FakeRetriever implements KnowledgeRetrievalGateway {
  FakeRetriever(this.bundle);
  RetrievalBundle bundle;
  int calls = 0;
  @override
  Future<RetrievalBundle> retrieve(
    String query, {
    KnowledgeScope scope = const KnowledgeScope.all(),
    int limit = 8,
    RetrievalExecutionContext? execution,
  }) async {
    calls++;
    return bundle;
  }
}

class FakeModel implements ChatModelGateway {
  int calls = 0;
  List<EvidenceItem> lastEvidence = const [];
  List<ChatMessage> lastPrior = const [];
  @override
  Future<ChatTurnResult> sendTurn({
    required String sessionId,
    required List<ChatMessage> priorMessages,
    required String userText,
    required List<EvidenceItem> evidence,
    required bool forceKnowledge,
  }) async {
    calls++;
    lastEvidence = evidence;
    lastPrior = priorMessages;
    return ChatTurnResult(
      text: evidence.isEmpty ? '模型回答' : '依据资料回答 [E1]',
      budget: const ContextBudgetDecision(
        modelContextLimit: 8192,
        systemTokens: 100,
        historyTokens: 0,
        evidenceTokens: 0,
        queryTokens: 20,
        outputReserveTokens: 700,
        totalPrefillTokens: 120,
        remainingTokens: 7372,
        trimmedHistoryMessages: 0,
        trimmedEvidenceItems: 0,
        trimDetails: <String>[],
      ),
      generation: const GenerationTelemetry(generationMs: 1),
    );
  }

  @override
  Future<void> resetSession(String sessionId) async {}
  @override
  Future<void> close() async {}
}

RetrievalBundle bundle({bool relevant = false, bool evidence = false}) {
  const chunk = PgChunk(
    id: 'c',
    documentId: 'd',
    sourceName: 'd.txt',
    locator: 'text',
    ordinal: 0,
    text: 'local evidence',
  );
  final ev = evidence
      ? const [EvidenceItem(anchor: 'E1', chunk: chunk, score: 0.1)]
      : const <EvidenceItem>[];
  final hybrid = evidence
      ? const [
          HybridHit(
            chunk: chunk,
            score: 0.1,
            channels: {'fts5'},
            lexicalRank: 1,
            semanticRank: null,
          ),
        ]
      : const <HybridHit>[];
  return RetrievalBundle(
    lexicalHits: const [],
    semanticHits: const [],
    hybridHits: hybrid,
    evidence: ev,
    lexicalOnly: true,
    autoRelevantOverride: relevant,
  );
}

Future<(ChatOrchestrator, ChatSessionStore, FakeRetriever, FakeModel, String)>
fixture(ChatMode mode, RetrievalBundle b) async {
  final db = sqlite3.openInMemory();
  final store = ChatSessionStore(database: db);
  await store.initialize();
  final s = await store.createSession(title: 'test');
  await store.updateSession(s.id, mode: mode);
  final r = FakeRetriever(b);
  final m = FakeModel();
  return (
    ChatOrchestrator(store: store, retriever: r, model: m),
    store,
    r,
    m,
    s.id,
  );
}

void main() {
  test('modelOnly never invokes retrieval', () async {
    final (o, _, r, m, id) = await fixture(ChatMode.modelOnly, bundle());
    await o.sendMessage(id, '你好');
    expect(r.calls, 0);
    expect(m.calls, 1);
    expect(m.lastEvidence, isEmpty);
  });

  test('auto falls back to pure model when evidence is irrelevant', () async {
    final (o, _, r, m, id) = await fixture(
      ChatMode.auto,
      bundle(evidence: true, relevant: false),
    );
    await o.sendMessage(id, '讲个笑话');
    expect(r.calls, 1);
    expect(m.lastEvidence, isEmpty);
  });

  test('auto injects relevant local evidence', () async {
    final (o, _, _, m, id) = await fixture(
      ChatMode.auto,
      bundle(evidence: true, relevant: true),
    );
    await o.sendMessage(id, '文档结论');
    expect(m.lastEvidence.single.anchor, 'E1');
  });

  test('forced knowledge without evidence never calls model', () async {
    final (o, _, _, m, id) = await fixture(ChatMode.knowledge, bundle());
    final reply = await o.sendMessage(id, '本地资料');
    expect(m.calls, 0);
    expect(reply.text, contains('本地资料不足'));
  });

  test('second turn receives first user and assistant pair', () async {
    final (o, _, _, m, id) = await fixture(ChatMode.modelOnly, bundle());
    await o.sendMessage(id, '第一问');
    await o.sendMessage(id, '第二问');
    expect(
      m.lastPrior.map((x) => x.text).toList(),
      containsAllInOrder(['第一问', '模型回答']),
    );
  });
}
