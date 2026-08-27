import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('R4.0.1 is an in-place R3 upgrade and never redownloads active models', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    final bootstrap = await File('scripts/bootstrap_android.sh').readAsString();
    final setup = await File('lib/services/model_setup_service.dart').readAsString();
    final main = await File('lib/main.dart').readAsString();
    expect(pubspec, contains('version: 0.4.1+8'));
    expect(bootstrap, contains('com.qujindai.pocketgallery_phone_pilot.r3'));
    expect(setup, contains('if (!FlutterGemma.hasActiveModel())'));
    expect(setup, contains('if (!FlutterGemma.hasActiveEmbedder())'));
    expect(main, contains('MainShell'));
  });

  test('R4 chat data migration is additive', () async {
    final store = await File('lib/chat/chat_session_store.dart').readAsString();
    final fts = await File('lib/services/lexical_fts_store.dart').readAsString();
    expect('$store\n$fts', isNot(contains('DROP TABLE')));
    expect(fts, contains('INSERT OR IGNORE INTO pg_documents'));
  });
}
