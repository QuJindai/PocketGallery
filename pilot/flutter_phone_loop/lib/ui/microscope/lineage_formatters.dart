import '../../lineage/lineage_models.dart';

String formatGenerationSummary(
  GenerationStatsRecord? generation, {
  required int citationCount,
}) {
  if (generation == null) {
    return 'generation 未捕获 · TTFT 未捕获 · output tokens 未捕获 · '
        'decode 未捕获 · backend 未暴露 · citations $citationCount';
  }

  final ttft = generation.ttftMs == null
      ? 'TTFT 未捕获'
      : 'TTFT ${generation.ttftMs} ms';
  final output = generation.outputTokens == null
      ? 'output tokens 未捕获'
      : 'output ${generation.outputTokens} tokens';
  final decode = generation.decodeTokensPerSecond == null
      ? 'decode 未捕获'
      : 'decode ${generation.decodeTokensPerSecond!.toStringAsFixed(1)} tok/s';
  final backend = generation.backend == null
      ? 'backend 未暴露'
      : 'backend ${generation.backend}';
  return 'generation ${generation.generationMs} ms · $ttft · $output · '
      '$decode · $backend · citations $citationCount';
}

String formatDurationUs(int? microseconds) {
  if (microseconds == null) return '未捕获';
  if (microseconds < 1000) return '$microseconds µs';
  final milliseconds = microseconds / 1000;
  final digits = milliseconds == milliseconds.roundToDouble() ? 0 : 1;
  return '${milliseconds.toStringAsFixed(digits)} ms';
}

String formatNumber(double? value, {int digits = 4}) =>
    value == null ? '未捕获' : value.toStringAsFixed(digits);
