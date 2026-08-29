import '../core/evidence.dart';
import '../core/models.dart';
import '../observability/retrieval_trace.dart';
import '../observability/retrieval_trace_store.dart';
import '../services/knowledge_retriever.dart';
import 'chat_models.dart';
import 'chat_session_store.dart';

class ChatOrchestrator {
  ChatOrchestrator({
    required this.store,
    required this.retriever,
    required this.model,
    CitationResolver? citationResolver,
    this.traceStore,
  }) : citationResolver = citationResolver ?? CitationResolver();

  final ChatSessionStore store;
  final KnowledgeRetrievalGateway retriever;
  final ChatModelGateway model;
  final CitationResolver citationResolver;
  final RetrievalTraceStore? traceStore;

  Future<ChatSession> newSession({String title = '新会话'}) =>
      store.createSession(title: title, mode: ChatMode.auto);

  Future<ChatSession> setMode(String sessionId, ChatMode mode) =>
      store.updateSession(sessionId, mode: mode);

  Future<ChatSession> setScope(String sessionId, KnowledgeScope scope) =>
      store.updateSession(sessionId, scope: scope);

  Future<void> clearSession(String sessionId) async {
    await store.clearMessages(sessionId);
    await model.resetSession(sessionId);
  }

  Future<ChatMessage> sendMessage(String sessionId, String text) async {
    final clean = text.trim();
    if (clean.isEmpty) throw ArgumentError.value(text, 'text', 'Message is empty');

    var session = await store.getSession(sessionId);
    if (session == null) throw StateError('Unknown chat session: $sessionId');
    final prior = await store.messages(sessionId);

    final user = ChatMessage.user(
      id: store.nextMessageId(),
      sessionId: sessionId,
      text: clean,
    );
    await store.appendMessage(user);

    if (prior.isEmpty && (session.title == '新会话' || session.title.trim().isEmpty)) {
      final title = clean.replaceAll(RegExp(r'\s+'), ' ');
      session = await store.updateSession(
        sessionId,
        title: title.length > 28 ? '${title.substring(0, 28)}…' : title,
      );
    }

    RetrievalBundle? retrieval;
    var useEvidence = false;
    if (session.mode != ChatMode.modelOnly) {
      retrieval = await retriever.retrieve(clean, scope: session.scope);
      useEvidence = session.mode == ChatMode.knowledge
          ? retrieval.relevantForKnowledge
          : retrieval.relevantForAuto;
    }

    if (session.mode == ChatMode.knowledge &&
        (retrieval == null ||
            retrieval.evidence.isEmpty ||
            !retrieval.relevantForKnowledge)) {
      final traceId = await _persistTrace(
        session: session,
        query: clean,
        retrieval: retrieval,
        citations: const [],
        generationMs: 0,
      );
      final reply = ChatMessage.assistant(
        id: store.nextMessageId(),
        sessionId: sessionId,
        text: '本地资料不足：当前知识库虽然可能存在语义相近片段，但不足以可靠回答这个问题。',
        retrievalMode: retrieval?.lexicalOnly == true
            ? 'knowledge:lexical-only-insufficient'
            : 'knowledge:insufficient',
        traceId: traceId,
      );
      await store.appendMessage(reply);
      return reply;
    }

    final evidence = useEvidence
        ? retrieval!.evidence
        : const <EvidenceItem>[];
    final turnResult = await model.sendTurn(
      sessionId: sessionId,
      priorMessages: prior,
      userText: clean,
      evidence: evidence,
      forceKnowledge: session.mode == ChatMode.knowledge,
    );
    var answer = turnResult.text;

    var anchors = evidence.isEmpty
        ? const <String>[]
        : citationResolver.extract(answer, evidence);
    if (evidence.isNotEmpty && anchors.isEmpty) {
      answer = '$answer\n\n本轮本地证据来源：[${evidence.first.anchor}]';
      anchors = citationResolver.extract(answer, evidence);
    }

    final retrievalMode = session.mode == ChatMode.modelOnly
        ? 'modelOnly'
        : useEvidence
            ? '${session.mode.name}:${retrieval!.lexicalOnly ? 'lexical-only' : 'hybrid'}'
            : 'auto:modelOnly';
    final traceId = await _persistTrace(
      session: session,
      query: clean,
      retrieval: retrieval,
      citations: anchors,
      generationMs: turnResult.generation.generationMs,
    );
    final reply = ChatMessage.assistant(
      id: store.nextMessageId(),
      sessionId: sessionId,
      text: answer,
      retrievalMode: retrievalMode,
      evidenceJson: evidence.isEmpty ? null : ChatMessage.encodeEvidence(evidence),
      citedAnchorsJson:
          anchors.isEmpty ? null : ChatMessage.encodeAnchors(anchors),
      traceId: traceId,
    );
    await store.appendMessage(reply);
    return reply;
  }

  Future<String?> _persistTrace({
    required ChatSession session,
    required String query,
    required RetrievalBundle? retrieval,
    required List<String> citations,
    required int generationMs,
  }) async {
    final target = traceStore;
    final draft = retrieval?.traceDraft;
    if (target == null || draft == null) return null;
    final traceId = '${session.id}-${DateTime.now().microsecondsSinceEpoch}';
    await target.save(RetrievalTrace(
      traceId: traceId,
      sessionId: session.id,
      query: query,
      mode: session.mode.name,
      startedAt: draft.startedAt,
      completedAt: DateTime.now().toUtc(),
      scopeDocumentIds: session.scope.documentIds ?? const <String>{},
      timings: draft.timings.copyWith(generationMs: generationMs),
      lexicalHits: draft.lexicalHits,
      semanticHits: draft.semanticHits,
      hybridHits: draft.hybridHits,
      evidenceAnchors:
          retrieval!.evidence.map((item) => item.anchor).toList(growable: false),
      citations: citations,
    ));
    return traceId;
  }
}
