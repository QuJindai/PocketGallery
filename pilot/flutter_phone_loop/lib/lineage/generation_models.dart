class ContextBudgetDecision {
  const ContextBudgetDecision({
    required this.modelContextLimit,
    required this.systemTokens,
    required this.historyTokens,
    required this.evidenceTokens,
    required this.queryTokens,
    required this.outputReserveTokens,
    required this.totalPrefillTokens,
    required this.remainingTokens,
    required this.trimmedHistoryMessages,
    required this.trimmedEvidenceItems,
    required this.trimDetails,
  });

  final int modelContextLimit;
  final int systemTokens;
  final int historyTokens;
  final int evidenceTokens;
  final int queryTokens;
  final int outputReserveTokens;
  final int totalPrefillTokens;
  final int remainingTokens;
  final int trimmedHistoryMessages;
  final int trimmedEvidenceItems;
  final List<String> trimDetails;
}

class GenerationTelemetry {
  const GenerationTelemetry({
    required this.generationMs,
    this.ttftMs,
    this.outputTokens,
    this.decodeTokensPerSecond,
    this.backend,
    this.nativeSessionRebuilt = false,
    this.sessionResetReason,
  });

  final int generationMs;
  final int? ttftMs;
  final int? outputTokens;
  final double? decodeTokensPerSecond;
  final String? backend;
  final bool nativeSessionRebuilt;
  final String? sessionResetReason;
}

class ChatTurnResult {
  const ChatTurnResult({
    required this.text,
    required this.budget,
    required this.generation,
  });

  final String text;
  final ContextBudgetDecision budget;
  final GenerationTelemetry generation;
}
