import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('R4.0.3 materializes embedding runtime before RAG add and search', () async {
    final semantic = await File('lib/services/semantic_store.dart').readAsString();

    expect(semantic, contains('_ensureEmbeddingRuntime'));
    expect(semantic, contains('await FlutterGemma.getActiveEmbedder()'));

    final ensureCalls = RegExp(r'await _ensureEmbeddingRuntime\(\);')
        .allMatches(semantic)
        .length;
    expect(ensureCalls, greaterThanOrEqualTo(2));
  });

  test('R4.0.3 model READY self-check includes a real embedding runtime probe', () async {
    final setup = await File('lib/services/model_setup_service.dart').readAsString();

    expect(setup, contains('await FlutterGemma.getActiveEmbedder()'));
    expect(setup, contains('Embedding runtime'));
  });

  test('R4.0.3 remains an in-place R3 signed upgrade', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    final bootstrap = await File('scripts/bootstrap_android.sh').readAsString();

    expect(pubspec, contains('version: 0.4.3+10'));
    expect(bootstrap, contains('com.qujindai.pocketgallery_phone_pilot.r3'));
  });
}
