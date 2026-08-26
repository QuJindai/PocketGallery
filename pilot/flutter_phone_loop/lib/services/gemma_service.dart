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

  Future<void> close() async {
    await _model?.close();
    _model = null;
  }
}
