import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:pocketgallery_phone_pilot/chat/chat_models.dart';
import 'package:pocketgallery_phone_pilot/chat/chat_session_store.dart';

void main() {
  test('session mode scope and messages persist', () async {
    final db = sqlite3.openInMemory();
    final store = ChatSessionStore(database: db);
    await store.initialize();
    final session = await store.createSession(title: 'DSA');
    await store.updateSession(
      session.id,
      mode: ChatMode.knowledge,
      scope: KnowledgeScope.documents({'doc-a'}),
    );
    await store.appendMessage(
      ChatMessage.user(id: 'm1', sessionId: session.id, text: '31 03 51 01'),
    );
    await store.appendMessage(
      ChatMessage.assistant(
        id: 'm2',
        sessionId: session.id,
        text: '车辆仍在处理中 [E1]',
        evidenceJson: '[{"anchor":"E1","chunkId":"c1"}]',
        citedAnchorsJson: '["E1"]',
        retrievalMode: 'knowledge',
      ),
    );
    final loaded = await store.getSession(session.id);
    final messages = await store.messages(session.id);
    expect(loaded!.mode, ChatMode.knowledge);
    expect(loaded.scope.documentIds, {'doc-a'});
    expect(messages.map((m) => m.text).toList(), [
      '31 03 51 01',
      '车辆仍在处理中 [E1]',
    ]);
    db.close();
  });

  test('chat schema is additive and isolated from R3 knowledge DBs', () async {
    final source = await File('lib/chat/chat_session_store.dart')
        .readAsString();
    expect(source, contains('pocketgallery_chat.db'));
    expect(source, isNot(contains('DROP TABLE')));
    expect(source, isNot(contains('pocketgallery_fts5.db')));
    expect(source, isNot(contains('pocketgallery_vectors.db')));
  });
}
