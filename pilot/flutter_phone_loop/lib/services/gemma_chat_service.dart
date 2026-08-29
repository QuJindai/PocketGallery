import 'package:flutter_gemma/flutter_gemma.dart';

import '../chat/chat_models.dart';
import '../chat/context_budgeter.dart';
import '../core/models.dart';

class GemmaChatService implements ChatModelGateway {
  GemmaChatService({this.budgeter = const ContextBudgeter()});

  final ContextBudgeter budgeter;
  InferenceModel? _model;
  InferenceChat? _chat;

  Future<void> _ensureModel() async {
    if (_model != null) return;
    if (!FlutterGemma.hasActiveModel()) {
      throw StateError('Gemma 4 尚未就绪');
    }
    _model = await FlutterGemma.getActiveModel(
      maxTokens: ContextBudgeter.modelMaxTokens,
      preferredBackend: PreferredBackend.gpu,
    );
  }

  String _boundedEvidenceContext(List<EvidenceItem> evidence) {
    return budgeter.composeEvidenceContext(
      evidence,
      maxTokens: ContextBudgeter.evidenceReserveMax,
      maxItems: 8,
    );
  }

  Future<InferenceChat> _createTurnChat(
    List<ChatMessage> priorMessages, {
    required int evidenceTokens,
    required int currentTurnTokens,
  }) async {
    await _ensureModel();

    // Native LiteRT chat state is bounded. Reusing one session forever makes
    // the state grow beyond the model's remaining prefill capacity and also
    // leaves a closed session cached after a runtime failure. Rebuild a fresh
    // native chat from the bounded persisted history for every user turn while
    // keeping the heavyweight model itself resident.
    await _closeNativeChat();
    final chat = await _model!.createChat(
      modelType: ModelType.gemma4,
      temperature: 0.35,
      topK: 32,
      topP: 0.9,
      maxOutputTokens: 700,
      systemInstruction:
          'You are PocketGallery, an on-device assistant. Continue the user conversation naturally. '
          'When a user turn contains [LOCAL_KNOWLEDGE], use that evidence for local factual claims and cite [E#]. '
          'When a turn contains [FORCED_KNOWLEDGE], answer local factual claims only from the supplied evidence. '
          'If supplied evidence cannot answer the question, say the local evidence is insufficient instead of giving a generic answer. '
          'Never invent an [E#] that is not present in the supplied evidence. '
          'Prior evidence blocks belong to their original turns and must not be reused as evidence for a later turn unless re-supplied.',
    );
    _chat = chat;

    final selected = budgeter.selectHistory(
      priorMessages,
      evidenceTokens: evidenceTokens,
      currentTurnTokens: currentTurnTokens,
    );
    for (final message in selected) {
      await chat.addQueryChunk(Message.text(
        text: message.text,
        isUser: message.role == ChatRole.user,
      ));
    }
    return chat;
  }

  @override
  Future<String> sendTurn({
    required String sessionId,
    required List<ChatMessage> priorMessages,
    required String userText,
    required List<EvidenceItem> evidence,
    required bool forceKnowledge,
  }) async {
    final context = _boundedEvidenceContext(evidence);
    final marker = forceKnowledge ? '[FORCED_KNOWLEDGE]' : '[LOCAL_KNOWLEDGE]';
    final currentTurn = evidence.isEmpty
        ? userText
        : '$marker\n\nUSER MESSAGE:\n$userText';
    final evidenceTokens = budgeter.estimateTokens(context);
    final currentTurnTokens = budgeter.estimateTokens(currentTurn);

    final chat = await _createTurnChat(
      priorMessages,
      evidenceTokens: evidenceTokens,
      currentTurnTokens: currentTurnTokens,
    );

    final payload = evidence.isEmpty
        ? userText
        : '$marker\n$context\n\nUSER MESSAGE:\n$userText';

    try {
      await chat.addQueryChunk(Message.text(text: payload, isUser: true));
      final response = await chat.generateChatResponse();
      if (response is TextResponse) return response.token.trim();
      return response.toString().trim();
    } finally {
      // A failed prefill/generation may already have closed the native session.
      // Always invalidate our reference so the next turn can never reuse a
      // poisoned/closed chat object.
      await _closeNativeChat();
    }
  }

  @override
  Future<void> resetSession(String sessionId) => _closeNativeChat();

  Future<void> _closeNativeChat() async {
    final chat = _chat;
    _chat = null;
    if (chat == null) return;
    try {
      await chat.session.close();
    } catch (_) {
      // The plugin may close the native session itself after an inference
      // failure. Closing twice must not turn a recoverable state into another
      // user-visible "Session is closed" error.
    }
  }

  @override
  Future<void> close() async {
    await _closeNativeChat();
    await _model?.close();
    _model = null;
  }
}
