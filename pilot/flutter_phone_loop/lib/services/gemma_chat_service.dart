import 'package:flutter_gemma/flutter_gemma.dart';

import '../chat/chat_models.dart';
import '../chat/context_budgeter.dart';
import '../core/evidence.dart';
import '../core/models.dart';

class GemmaChatService implements ChatModelGateway {
  GemmaChatService({ContextBudgeter budgeter = const ContextBudgeter()})
      : _budgeter = budgeter;

  final ContextBudgeter _budgeter;
  InferenceModel? _model;
  InferenceChat? _chat;
  String? _activeSessionId;

  Future<void> _ensureModel() async {
    if (_model != null) return;
    if (!FlutterGemma.hasActiveModel()) {
      throw StateError('Gemma 4 尚未就绪');
    }
    _model = await FlutterGemma.getActiveModel(
      maxTokens: 8192,
      preferredBackend: PreferredBackend.gpu,
    );
  }

  Future<void> _ensureChat(
    String sessionId,
    List<ChatMessage> priorMessages, {
    int evidenceTokens = 0,
  }) async {
    await _ensureModel();
    if (_chat != null && _activeSessionId == sessionId) return;

    await _closeNativeChat();
    _chat = await _model!.createChat(
      modelType: ModelType.gemma4,
      temperature: 0.35,
      topK: 32,
      topP: 0.9,
      maxOutputTokens: 700,
      systemInstruction:
          'You are PocketGallery, an on-device assistant. Continue the user conversation naturally. '
          'When a user turn contains [LOCAL_KNOWLEDGE], use that evidence for local factual claims and cite [E#]. '
          'When a turn contains [FORCED_KNOWLEDGE], answer local factual claims only from the supplied evidence. '
          'Never invent an [E#] that is not present in the supplied evidence. '
          'Prior evidence blocks belong to their original turns and must not be reused as evidence for a later turn unless re-supplied.',
    );
    _activeSessionId = sessionId;

    final selected = _budgeter.selectHistory(
      priorMessages,
      evidenceTokens: evidenceTokens,
    );
    for (final message in selected) {
      if (message.role == ChatRole.user) {
        await _chat!.addQueryChunk(Message.text(
          text: message.text,
          isUser: true,
        ));
      } else {
        await _chat!.addQueryChunk(Message.text(
          text: message.text,
          isUser: false,
        ));
      }
    }
  }

  @override
  Future<String> sendTurn({
    required String sessionId,
    required List<ChatMessage> priorMessages,
    required String userText,
    required List<EvidenceItem> evidence,
    required bool forceKnowledge,
  }) async {
    final context = evidence.isEmpty
        ? ''
        : const EvidencePackBuilder().toPromptContext(evidence);
    final evidenceTokens = _budgeter.estimateTokens(context);
    await _ensureChat(
      sessionId,
      priorMessages,
      evidenceTokens: evidenceTokens,
    );

    final payload = evidence.isEmpty
        ? userText
        : '${forceKnowledge ? '[FORCED_KNOWLEDGE]' : '[LOCAL_KNOWLEDGE]'}\n'
            '$context\n\nUSER MESSAGE:\n$userText';

    await _chat!.addQueryChunk(Message.text(text: payload, isUser: true));
    final response = await _chat!.generateChatResponse();
    if (response is TextResponse) return response.token.trim();
    return response.toString().trim();
  }

  @override
  Future<void> resetSession(String sessionId) async {
    if (_activeSessionId != sessionId) return;
    await _closeNativeChat();
    _activeSessionId = null;
  }

  Future<void> _closeNativeChat() async {
    final chat = _chat;
    _chat = null;
    if (chat != null) {
      await chat.session.close();
    }
  }

  @override
  Future<void> close() async {
    await _closeNativeChat();
    _activeSessionId = null;
    await _model?.close();
    _model = null;
  }
}
