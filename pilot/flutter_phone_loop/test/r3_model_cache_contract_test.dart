import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'installed Gemma and Embedding models bypass network download paths',
    () async {
      final source = await File(
        'lib/services/model_setup_service.dart',
      ).readAsString();

      final gemmaGuard = source.indexOf('if (!FlutterGemma.hasActiveModel())');
      final gemmaNetwork = source.indexOf('.fromNetwork(gemma4Url');
      final embedGuard = source.indexOf(
        'if (!FlutterGemma.hasActiveEmbedder())',
      );
      final embedNetwork = source.indexOf(
        '.modelFromNetwork(embeddingModelUrl',
      );

      expect(gemmaGuard, greaterThanOrEqualTo(0));
      expect(gemmaNetwork, greaterThan(gemmaGuard));
      expect(embedGuard, greaterThanOrEqualTo(0));
      expect(embedNetwork, greaterThan(embedGuard));
    },
  );

  test('model bootstrap does not use temporary cache storage', () async {
    final source = await File(
      'lib/services/model_setup_service.dart',
    ).readAsString();
    expect(source, isNot(contains('getTemporaryDirectory')));
    expect(source, isNot(contains('/cache/')));
  });

  test(
    'application identity and signing chain fail closed for upgrades',
    () async {
      final bootstrap = await File(
        'scripts/bootstrap_android.sh',
      ).readAsString();
      final workflow = await File(
        '../../.github/workflows/pocketgallery-phone-pilot-apk.yml',
      ).readAsString();

      expect(bootstrap, contains('com.qujindai.pocketgallery_phone_pilot.r3'));
      expect(bootstrap, contains('PocketGallery R3'));
      expect(workflow, isNot(contains('actions/cache')));
      expect(workflow, isNot(contains('~/.android/pocketgallery-r3-signing')));
      expect(workflow, contains('pocketgallery-canonical-signing'));
      expect(workflow, contains('CANONICAL_SIGNER_SHA256='));
      expect(workflow, contains('SIGNING_IDENTITY_MISSING'));
      expect(workflow, contains('SIGNING_IDENTITY_MISMATCH'));
      expect(workflow, isNot(contains('keytool -genkeypair')));
      expect(workflow, isNot(contains('openssl rand -hex')));
      expect(workflow, contains('POCKETGALLERY_SIGNING_KEYSTORE'));
      expect(workflow, contains('apksigner'));
      expect(workflow, contains('APK_SIGNER_SHA256'));
    },
  );
}
