import '../core/evidence.dart';
import '../core/models.dart';
import '../services/knowledge_retriever.dart';
import 'chat_models.dart';
import 'chat_session_store.dart';

class ChatOrchestrator {
  ChatOrchestrator({
    required this.store,
    required this.retriever,
    required this.model,
    CitationResolver? citationResolver,
  }) : citationResolver = citationResolver ?? CitationResolver();

  final ChatSessionStore store;
  final KnowledgeRetrievalGateway retriever;
  final ChatModelGateway model;
  final CitationResolver citationResolver;

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
      useEvidence = session.mode == ChatMode.knowledge || retrieval.relevantForAuto;
    }

    if (session.mode == ChatMode.knowledge &&
        (retrieval == null || retrieval.evidence.isEmpty)) {
      final reply = ChatMessage.assistant(
        id: store.nextMessageId(),
        sessionId: sessionId,
        text: '本地资料不足，当前知识库范围内没有找到足够证据。',
        retrievalMode: retrieval?.lexicalOnly == true
            ? 'knowledge:lexical-only'
            : 'knowledge',
      );
      await store.appendMessage(reply);
      return reply;
    }

    final evidence = useEvidence
        ? retrieval!.evidence
        : const <EvidenceItem>[];
    var answer = await model.sendTurn(
      sessionId: sessionId,
      priorMessages: prior,
      userText: clean,
      evidence: evidence,
      forceKnowledge: session.mode == ChatMode.knowledge,
    );

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
    final reply = ChatMessage.assistant(
      id: store.nextMessageId(),
      sessionId: sessionId,
      text: answer,
      retrievalMode: retrievalMode,
      evidenceJson: evidence.isEmpty ? null : ChatMessage.encodeEvidence(evidence),
      citedAnchorsJson:
          anchors.isEmpty ? null : ChatMessage.encodeAnchors(anchors),
    );
    await store.appendMessage(reply);
    return reply;
  }
}
