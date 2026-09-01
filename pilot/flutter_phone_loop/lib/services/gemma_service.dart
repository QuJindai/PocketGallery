import 'package:flutter_gemma/flutter_gemma.dart';

import '../core/evidence.dart';
import '../core/models.dart';

class GemmaService {
  InferenceModel? _model;

  Future<void> ensureLoaded() async {
    _model ??= await FlutterGemma.getActiveModel(
      maxTokens: 8192,
      preferredBackend: PreferredBackend.gpu,
    );
  }

  Future<String> answer({
    required String question,
    required List<EvidenceItem> evidence,
  }) async {
    await ensureLoaded();
    final context = const EvidencePackBuilder().toPromptContext(evidence);
    final chat = await _model!.createChat(
      modelType: ModelType.gemma4,
      temperature: 0.15,
      topK: 20,
      topP: 0.9,
      maxOutputTokens: 420,
      systemInstruction:
          'You are PocketGallery, a local evidence-grounded engineering assistant. '
          'Use only the supplied evidence. Every factual claim must cite [E#]. '
          'If the evidence is insufficient, say so. Do not invent sources.',
    );
    await chat.addQueryChunk(Message.text(
      text: 'EVIDENCE:\n$context\nQUESTION:\n$question',
      isUser: true,
    ));
    final response = await chat.generateChatResponse();
    if (response is TextResponse) return response.token.trim();
    return response.toString().trim();
  }

  Future<String> experimentalAnswer({
    required String question,
    required List<EvidenceItem> evidence,
    required bool groundedOnly,
  }) async {
    await ensureLoaded();
    final context = const EvidencePackBuilder().toPromptContext(evidence);
    final systemInstruction = groundedOnly
        ? 'You are PocketGallery OKF Mobile Lab. This is a controlled local-model experiment. '
            'Use only the supplied EVIDENCE. Cite every factual claim with [E#]. '
            'When evidence conflicts, prefer evidence that explicitly states it is current. '
            'If evidence is insufficient, say so and do not guess.'
        : 'You are PocketGallery OKF Mobile Lab running the BARE local-model control lane. '
            'No external knowledge is supplied. Answer only from the model itself. '
            'The benchmark contains fictional identifiers that may not exist in training data. '
            'If you do not know a fact, say that it is unknown instead of inventing it.';
    final userText = groundedOnly
        ? 'EVIDENCE:\n$context\nQUESTION:\n$question'
        : 'QUESTION:\n$question';

    final chat = await _model!.createChat(
      modelType: ModelType.gemma4,
      temperature: 0.05,
      topK: 20,
      topP: 0.85,
      maxOutputTokens: 260,
      systemInstruction: systemInstruction,
    );
    await chat.addQueryChunk(Message.text(text: userText, isUser: true));
    final response = await chat.generateChatResponse();
    if (response is TextResponse) return response.token.trim();
    return response.toString().trim();
  }

  Future<void> close() async {
    await _model?.close();
    _model = null;
  }
}
