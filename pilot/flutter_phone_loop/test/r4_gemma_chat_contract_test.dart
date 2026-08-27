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

  test('Gemma chat service keeps one native chat for active session', () async {
    final source = await File('lib/services/gemma_chat_service.dart').readAsString();
    expect(source, contains('InferenceChat? _chat'));
    expect(source, contains('_activeSessionId'));
    expect(source, contains('addQueryChunk'));
    expect(source, contains('generateChatResponse'));
    expect(source, contains('isUser: false'));
  });
}
