import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('R4 main shell is chat first with three modes', () async {
    final main = await File('lib/main.dart').readAsString();
    final shell = await File('lib/ui/main_shell.dart').readAsString();
    final chat = await File('lib/ui/chat_page.dart').readAsString();
    expect(main, contains('MainShell'));
    expect(main, isNot(contains('home: HomePage')));
    expect(shell, contains("label: '聊天'"));
    expect(shell, contains("label: '知识库'"));
    expect(shell, contains("label: '模型 / 设置'"));
    expect(chat, contains('纯模型'));
    expect(chat, contains('自动'));
    expect(chat, contains('强制知识库'));
    expect(chat, contains('会话历史'));
    expect(chat, contains('新建会话'));
    expect(chat, isNot(contains('Run Phone Golden Test')));
  });
}
