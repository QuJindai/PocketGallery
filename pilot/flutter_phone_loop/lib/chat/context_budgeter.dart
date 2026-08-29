import 'chat_models.dart';

class ContextBudgeter {
  const ContextBudgeter();

  static const modelMaxTokens = 8192;
  static const systemReserve = 700;
  static const outputReserve = 700;
  static const evidenceReserveMax = 1900;
  static const safetyReserve = 600;

  int estimateTokens(String text) {
    final cjk = RegExp(r'[\u3400-\u9FFF]').allMatches(text).length;
    final nonCjk = text.length - cjk;
    return cjk + (nonCjk / 4).ceil() + 8;
  }

  int availableHistoryTokens({
    int evidenceTokens = 0,
    int currentTurnTokens = 0,
  }) {
    final evidenceReserve = evidenceTokens.clamp(0, evidenceReserveMax);
    final budget = modelMaxTokens -
        systemReserve -
        outputReserve -
        safetyReserve -
        evidenceReserve -
        currentTurnTokens;
    return budget < 0 ? 0 : budget;
  }

  List<ChatMessage> selectHistory(
    List<ChatMessage> messages, {
    int evidenceTokens = 0,
    int currentTurnTokens = 0,
  }) {
    final budget = availableHistoryTokens(
      evidenceTokens: evidenceTokens,
      currentTurnTokens: currentTurnTokens,
    );
    if (budget <= 0 || messages.isEmpty) return const [];

    var used = 0;
    final selected = <ChatMessage>[];
    for (var i = messages.length - 1; i >= 0; i--) {
      final cost = estimateTokens(messages[i].text);
      if (cost > budget || used + cost > budget) {
        continue;
      }
      selected.add(messages[i]);
      used += cost;
      if (used >= budget) break;
    }
    return selected.reversed.toList(growable: false);
  }

  String trimTextToTokenBudget(String text, int maxTokens) {
    if (text.isEmpty || maxTokens <= 0) return '';
    if (estimateTokens(text) <= maxTokens) return text;

    var low = 0;
    var high = text.length;
    var best = 0;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final candidate = text.substring(0, mid);
      if (estimateTokens(candidate) <= maxTokens) {
        best = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    if (best <= 0) return '';
    return '${text.substring(0, best).trimRight()}\n…[context budget truncated]';
  }
}
