import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('installed Gemma and Embedding models bypass network download paths', () async {
    final source = await File('lib/services/model_setup_service.dart').readAsString();

    final gemmaGuard = source.indexOf('if (!FlutterGemma.hasActiveModel())');
    final gemmaNetwork = source.indexOf('.fromNetwork(gemma4Url');
    final embedGuard = source.indexOf('if (!FlutterGemma.hasActiveEmbedder())');
    final embedNetwork = source.indexOf('.modelFromNetwork(embeddingModelUrl');

    expect(gemmaGuard, greaterThanOrEqualTo(0));
    expect(gemmaNetwork, greaterThan(gemmaGuard));
    expect(embedGuard, greaterThanOrEqualTo(0));
    expect(embedNetwork, greaterThan(embedGuard));
  });

  test('model bootstrap does not use temporary cache storage', () async {
    final source = await File('lib/services/model_setup_service.dart').readAsString();
    expect(source, isNot(contains('getTemporaryDirectory')));
    expect(source, isNot(contains('/cache/')));
  });

  test('R2 application identity remains fixed for app-data reuse', () async {
    final bootstrap = await File('scripts/bootstrap_android.sh').readAsString();
    expect(
      bootstrap,
      contains('com.qujindai.pocketgallery_phone_pilot.r2'),
    );
    expect(bootstrap, contains('PocketGallery R2'));
  });
}
