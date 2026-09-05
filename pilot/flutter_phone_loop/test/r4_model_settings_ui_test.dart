import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Golden Test is advanced only in R4', () async {
    final settings = await File('lib/ui/model_settings_page.dart').readAsString();
    final chat = await File('lib/ui/chat_page.dart').readAsString();
    expect(settings, contains('高级 / 诊断'));
    expect(settings, contains('Run Phone Golden Test'));
    expect(settings, contains('Gemma 4'));
    expect(settings, contains('EmbeddingGemma'));
    expect(chat, isNot(contains('Run Phone Golden Test')));
  });
}
