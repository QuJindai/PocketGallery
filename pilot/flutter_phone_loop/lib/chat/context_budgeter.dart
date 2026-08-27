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

  List<ChatMessage> selectHistory(
    List<ChatMessage> messages, {
    int evidenceTokens = 0,
  }) {
    final evidenceReserve = evidenceTokens.clamp(0, evidenceReserveMax);
    final budget = modelMaxTokens -
        systemReserve -
        outputReserve -
        safetyReserve -
        evidenceReserve;
    if (budget <= 0 || messages.isEmpty) return const [];

    var used = 0;
    final selected = <ChatMessage>[];
    for (var i = messages.length - 1; i >= 0; i--) {
      final cost = estimateTokens(messages[i].text);
      if (selected.isNotEmpty && used + cost > budget) break;
      if (cost > budget && selected.isEmpty) {
        selected.add(messages[i]);
        break;
      }
      selected.add(messages[i]);
      used += cost;
    }
    return selected.reversed.toList(growable: false);
  }
}
