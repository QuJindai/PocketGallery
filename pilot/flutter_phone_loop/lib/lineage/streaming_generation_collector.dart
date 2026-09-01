import 'generation_models.dart';

class StreamingGenerationResult {
  const StreamingGenerationResult({
    required this.text,
    required this.telemetry,
  });

  final String text;
  final GenerationTelemetry telemetry;
}

class StreamingGenerationCollector {
  final StringBuffer _text = StringBuffer();
  int? _firstTokenAtMs;
  int? _lastTokenAtMs;
  int _outputTokens = 0;

  void addTextToken(String token, {required int elapsedMilliseconds}) {
    _firstTokenAtMs ??= elapsedMilliseconds;
    _lastTokenAtMs = elapsedMilliseconds;
    _outputTokens += 1;
    _text.write(token);
  }

  StreamingGenerationResult complete({
    required int totalElapsedMilliseconds,
    bool nativeSessionRebuilt = false,
    String? sessionResetReason,
  }) {
    final firstTokenAtMs = _firstTokenAtMs;
    final lastTokenAtMs = _lastTokenAtMs;
    final decodedAfterFirst = _outputTokens - 1;
    final decodeMilliseconds = firstTokenAtMs == null || lastTokenAtMs == null
        ? 0
        : lastTokenAtMs - firstTokenAtMs;
    final decodeTokensPerSecond =
        decodedAfterFirst > 0 && decodeMilliseconds > 0
        ? decodedAfterFirst * 1000 / decodeMilliseconds
        : null;

    return StreamingGenerationResult(
      text: _text.toString().trim(),
      telemetry: GenerationTelemetry(
        generationMs: totalElapsedMilliseconds,
        ttftMs: firstTokenAtMs,
        outputTokens: _outputTokens,
        decodeTokensPerSecond: decodeTokensPerSecond,
        // flutter_gemma accepts a preferred backend but does not expose the
        // backend that actually executed this generation. Keep it unknown.
        backend: null,
        nativeSessionRebuilt: nativeSessionRebuilt,
        sessionResetReason: sessionResetReason,
      ),
    );
  }
}
