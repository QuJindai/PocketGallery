import 'package:flutter_gemma/flutter_gemma.dart';

import '../core/evidence.dart';
import '../core/models.dart';
import '../lineage/streaming_generation_collector.dart';

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
    try {
      await chat.addQueryChunk(
        Message.text(
          text: 'EVIDENCE:\n$context\nQUESTION:\n$question',
          isUser: true,
        ),
      );
      final response = await chat.generateChatResponse();
      if (response is TextResponse) return response.token.trim();
      return response.toString().trim();
    } finally {
      try {
        await chat.session.close();
      } catch (_) {
        // A failed native generation can already have closed the session.
      }
    }
  }

  Future<StreamingGenerationResult> benchmarkAnswer({
    required String question,
    required List<EvidenceItem> evidence,
    required bool groundedOnly,
  }) async {
    await ensureLoaded();
    final context = const EvidencePackBuilder().toPromptContext(evidence);
    final instruction = groundedOnly
        ? 'You are PocketGallery OKF A-F Lab running a controlled on-device experiment. '
              'Use only the supplied EVIDENCE for factual claims. Cite every factual claim with [E#]. '
              'When evidence conflicts, use explicit current/version/lifecycle evidence and never silently merge values. '
              'If the evidence is insufficient, say so instead of guessing.'
        : 'You are PocketGallery OKF A-F Lab running the BARE MODEL control lane. '
              'No external knowledge is supplied. The identifiers and factory facts may be fictional. '
              'If you do not know the answer from the model itself, explicitly say it is unknown and do not invent facts.';
    final payload = groundedOnly
        ? 'EVIDENCE:\n$context\n\nQUESTION:\n$question'
        : 'QUESTION:\n$question';
    final chat = await _model!.createChat(
      modelType: ModelType.gemma4,
      temperature: 0.05,
      topK: 20,
      topP: 0.85,
      maxOutputTokens: 260,
      systemInstruction: instruction,
    );
    try {
      await chat.addQueryChunk(Message.text(text: payload, isUser: true));
      final watch = Stopwatch()..start();
      final collector = StreamingGenerationCollector();
      await for (final response in chat.generateChatResponseAsync()) {
        if (response is TextResponse) {
          collector.addTextToken(
            response.token,
            elapsedMilliseconds: watch.elapsedMilliseconds,
          );
        }
      }
      watch.stop();
      return collector.complete(
        totalElapsedMilliseconds: watch.elapsedMilliseconds,
        nativeSessionRebuilt: true,
        sessionResetReason: 'okf_af_fresh_lane_session',
      );
    } finally {
      try {
        await chat.session.close();
      } catch (_) {
        // Every lane uses a fresh native chat; close is best effort on failure.
      }
    }
  }

  Future<void> close() async {
    await _model?.close();
    _model = null;
  }
}
