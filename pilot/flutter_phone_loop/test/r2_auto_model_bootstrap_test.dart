import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('R2 makes automatic model preparation the default UI path', () {
    final source = File('lib/ui/home_page.dart').readAsStringSync();

    expect(source, contains('自动准备模型'));
    expect(source, isNot(contains("_pathRow(\n            'Gemma 4 .litertlm'")));
    expect(source, isNot(contains("_pathRow(\n            'EmbeddingGemma .tflite'")));
    expect(source, isNot(contains("_pathRow(\n            'Tokenizer sentencepiece.model'")));
  });

  test('R2 model setup service exposes automatic bootstrap behavior', () {
    final source = File('lib/services/model_setup_service.dart').readAsStringSync();

    expect(source, contains('prepareAutomatically'));
    expect(source, contains('modelFromNetwork'));
    expect(source, contains('tokenizerFromNetwork'));
  });

  test('R2 prevents semantic search when embedder is not ready', () {
    final source = File('lib/services/knowledge_engine.dart').readAsStringSync();

    expect(source, contains('FlutterGemma.hasActiveEmbedder()'));
    expect(source, contains('const <RetrievalHit>[]'));
  });
}
