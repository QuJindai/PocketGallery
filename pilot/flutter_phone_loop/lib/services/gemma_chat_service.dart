import 'package:flutter_gemma/flutter_gemma.dart';

import '../chat/chat_models.dart';
import '../chat/context_budgeter.dart';
import '../core/models.dart';
import '../lineage/generation_models.dart';
import '../lineage/streaming_generation_collector.dart';

class GemmaChatService implements ChatModelGateway {
  GemmaChatService({this.budgeter = const ContextBudgeter()});

  static const _systemInstruction =
      'You are PocketGallery, an on-device assistant. Continue the user conversation naturally. '
      'When a user turn contains [LOCAL_KNOWLEDGE], use that evidence for local factual claims and cite [E#]. '
      'When a turn contains [FORCED_KNOWLEDGE], answer local factual claims only from the supplied evidence. '
      'If supplied evidence cannot answer the question, say the local evidence is insufficient instead of giving a generic answer. '
      'Never invent an [E#] that is not present in the supplied evidence. '
      'Prior evidence blocks belong to their original turns and must not be reused as evidence for a later turn unless re-supplied.';

  final ContextBudgeter budgeter;
  InferenceModel? _model;
  InferenceChat? _chat;
  bool _closed = false;

  Future<void> _ensureModel() async {
    if (_closed) throw StateError('Gemma service is closed');
    if (_model != null) return;
    if (!FlutterGemma.hasActiveModel()) {
      throw StateError('Gemma 4 尚未就绪');
    }
    final acquired = await FlutterGemma.getActiveModel(
      maxTokens: ContextBudgeter.modelMaxTokens,
      preferredBackend: PreferredBackend.gpu,
    );
    if (_closed) {
      try {
        await acquired.close();
      } catch (_) {
        // Closing is best-effort after a concurrent service shutdown.
      }
      throw StateError('Gemma service is closed');
    }
    _model = acquired;
  }

  EvidenceContextSelection _boundedEvidenceContext(
    List<EvidenceItem> evidence,
  ) {
    return budgeter.composeEvidenceContextWithDecision(
      evidence,
      maxTokens: ContextBudgeter.evidenceReserveMax,
      maxItems: 8,
    );
  }

  Future<InferenceChat> _createTurnChat(
    List<ChatMessage> selectedHistory,
  ) async {
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
      systemInstruction: _systemInstruction,
    );
    _chat = chat;

    for (final message in selectedHistory) {
      await chat.addQueryChunk(Message.text(
        text: message.text,
        isUser: message.role == ChatRole.user,
      ));
    }
    return chat;
  }

  @override
  Future<ChatTurnResult> sendTurn({
    required String sessionId,
    required List<ChatMessage> priorMessages,
    required String userText,
    required List<EvidenceItem> evidence,
    required bool forceKnowledge,
  }) async {
    final evidenceSelection = _boundedEvidenceContext(evidence);
    final context = evidenceSelection.context;
    final marker = forceKnowledge ? '[FORCED_KNOWLEDGE]' : '[LOCAL_KNOWLEDGE]';
    final unboundedCurrentTurn = evidence.isEmpty
        ? userText
        : '$marker\n\nUSER MESSAGE:\n$userText';
    final evidenceTokens = budgeter.estimateTokens(context);
    final systemTokens = budgeter.estimateTokens(_systemInstruction);
    final currentTurnBudget = ContextBudgeter.modelMaxTokens -
        ContextBudgeter.outputReserve -
        ContextBudgeter.safetyReserve -
        systemTokens -
        evidenceTokens;
    final currentTurn = budgeter.trimTextToTokenBudget(
      unboundedCurrentTurn,
      currentTurnBudget,
    );
    final currentTurnTokens = budgeter.estimateTokens(currentTurn);
    final contextSelection = budgeter.selectHistoryWithDecision(
      priorMessages,
      evidenceTokens: evidenceTokens,
      currentTurnTokens: currentTurnTokens,
      systemTokens: systemTokens,
      evidenceItemCount: evidence.length,
      includedEvidenceItemCount: evidenceSelection.includedItemCount,
      trimDetails: <String>[
        ...evidenceSelection.trimDetails,
        if (currentTurn != unboundedCurrentTurn) 'query_truncated',
      ],
    );
    final chat = await _createTurnChat(contextSelection.history);

    final payload = evidence.isEmpty
        ? currentTurn
        : '$context\n\n$currentTurn';

    try {
      await chat.addQueryChunk(Message.text(text: payload, isUser: true));
      final generationWatch = Stopwatch()..start();
      final generation = StreamingGenerationCollector();
      await for (final response in chat.generateChatResponseAsync()) {
        if (response is TextResponse) {
          generation.addTextToken(
            response.token,
            elapsedMilliseconds: generationWatch.elapsedMilliseconds,
          );
        }
      }
      generationWatch.stop();
      final completed = generation.complete(
        totalElapsedMilliseconds: generationWatch.elapsedMilliseconds,
        nativeSessionRebuilt: true,
        sessionResetReason: 'fresh_turn_context_bound',
      );
      return ChatTurnResult(
        text: completed.text,
        budget: contextSelection.decision,
        generation: completed.telemetry,
        evidenceTokenCounts: evidenceSelection.tokenCountsByAnchor,
      );
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
    _closed = true;
    await _closeNativeChat();
    final model = _model;
    _model = null;
    await model?.close();
  }
}
