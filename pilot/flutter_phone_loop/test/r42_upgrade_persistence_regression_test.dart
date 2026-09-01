import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const canonicalSigner =
      '81af4a5ef94c236774f0e193b2a4b248805b36c14cc36e2a56df8e451a712541';

  test(
    'distributable APK signing identity is pinned and cache miss fails closed',
    () async {
      final workflow = await File(
        '../../.github/workflows/pocketgallery-phone-pilot-apk.yml',
      ).readAsString();

      expect(workflow, contains('CANONICAL_SIGNER_SHA256=$canonicalSigner'));
      expect(workflow, contains('SIGNING_IDENTITY_MISSING'));
      expect(workflow, isNot(contains('keytool -genkeypair')));
      expect(workflow, isNot(contains('openssl rand -hex')));
    },
  );

  test('next pilot build is a monotonic in-place update over R4.1', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    final bootstrap = await File('scripts/bootstrap_android.sh').readAsString();

    final match = RegExp(
      r'^version:\s*[^+]+\+(\d+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull);
    expect(int.parse(match!.group(1)!), greaterThanOrEqualTo(12));
    expect(bootstrap, contains('com.qujindai.pocketgallery_phone_pilot.r3'));
  });

  test(
    'canceled model downloads recover automatically without OAuth reset',
    () async {
      final setup = await File(
        'lib/services/model_setup_service.dart',
      ).readAsString();

      expect(setup, contains('DownloadException'));
      expect(setup, contains('CanceledError'));
      expect(setup, contains('_retryCanceledDownload'));
      expect(setup, contains('UnauthorizedError'));
      expect(setup, contains('ForbiddenError'));
    },
  );

  test('frozen R3 and R4 regression gates remain present', () {
    const required = <String>[
      'r2_auto_model_bootstrap_test.dart',
      'r3_model_cache_contract_test.dart',
      'r3_oauth_device_flow_test.dart',
      'r31_phone_recovery_test.dart',
      'r32_oauth_resume_test.dart',
      'r33_device_code_ux_test.dart',
      'r401_phone_realworld_recovery_test.dart',
      'r402_chat_attachment_test.dart',
      'r403_embedding_runtime_recovery_test.dart',
      'r41_upgrade_contract_test.dart',
    ];

    for (final name in required) {
      expect(File('test/$name').existsSync(), isTrue, reason: 'missing $name');
    }
  });
}
