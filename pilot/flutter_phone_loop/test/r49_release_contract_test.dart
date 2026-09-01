import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('R4.9 maps build 21 to monotonic Android versionCode 2021', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    expect(pubspec, contains('version: 0.4.17+21'));

    final result = await Process.run(
      'bash',
      <String>['scripts/android_version_code.sh'],
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect((result.stdout as String).trim(), '2021');
  });

  test('R4.9 CI publishes an unsigned debug APK without weakening signer gate',
      () async {
    final tddWorkflow = await File(
      '../../.github/workflows/pocketgallery-r46-tdd.yml',
    ).readAsString();
    final signedWorkflow = await File(
      '../../.github/workflows/pocketgallery-phone-pilot-apk.yml',
    ).readAsString();

    expect(tddWorkflow, contains('scripts/android_version_code.sh'));
    expect(tddWorkflow, contains(r'--build-number="$ANDROID_VERSION_CODE"'));
    expect(tddWorkflow, contains('PocketGallery-R49-rotatable-3d-debug-apk'));
    expect(tddWorkflow, contains('actions/upload-artifact@v4'));
    expect(
      signedWorkflow,
      contains('SIGNING_IDENTITY_MISSING'),
      reason: 'canonical upgrade signing must continue to fail closed',
    );
    expect(
      signedWorkflow,
      contains(
        '81af4a5ef94c236774f0e193b2a4b248805b36c14cc36e2a56df8e451a712541',
      ),
    );
  });
}
