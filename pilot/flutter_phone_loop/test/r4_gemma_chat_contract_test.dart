import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketgallery_phone_pilot/chat/chat_models.dart';
import 'package:pocketgallery_phone_pilot/chat/context_budgeter.dart';

void main() {
  test('budgeter keeps newest turns and discards oldest first', () {
    final messages = List.generate(20, (i) => ChatMessage.user(
      id: 'm$i', sessionId: 's', text: '第$i轮 ${'内容' * 250}',
    ));
    final selected = const ContextBudgeter().selectHistory(messages);
    expect(selected.last.id, 'm19');
    expect(selected.length, lessThan(messages.length));
    expect(selected.first.id, isNot('m0'));
  });

  test('budgeter reserves the current user turn before selecting history', () {
    final budgeter = const ContextBudgeter();
    final messages = List.generate(20, (i) => ChatMessage.user(
      id: 'm$i', sessionId: 's', text: '历史${'内容' * 220}',
    ));
    final selected = budgeter.selectHistory(
      messages,
      evidenceTokens: 1600,
      currentTurnTokens: 1800,
    );
    final historyTokens = selected
        .map((m) => budgeter.estimateTokens(m.text))
        .fold<int>(0, (a, b) => a + b);
    expect(
      historyTokens,
      lessThanOrEqualTo(budgeter.availableHistoryTokens(
        evidenceTokens: 1600,
        currentTurnTokens: 1800,
      )),
    );
  });

  test('Gemma chat service rebuilds and invalidates native chat every turn', () async {
    final source = await File('lib/services/gemma_chat_service.dart').readAsString();
    expect(source, contains('InferenceChat? _chat'));
    expect(source, contains('_createTurnChat'));
    expect(source, contains('await _closeNativeChat();'));
    expect(source, contains('finally'));
    expect(source, contains('generateChatResponse'));
    expect(source, isNot(contains('_activeSessionId')));
  });
}
