import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('R5 candidate remains monotonic over R4.9 versionCode 2021', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    expect(pubspec, contains('version: 0.5.0+23'));

    final result = await Process.run(
      'bash',
      <String>['scripts/android_version_code.sh'],
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(int.parse((result.stdout as String).trim()), greaterThan(2021));
  });

  test('R5 CI preserves R4.9 single ABI offset and fail-closed signing',
      () async {
    final tddWorkflow = await File(
      '../../.github/workflows/pocketgallery-r46-tdd.yml',
    ).readAsString();
    final signedWorkflow = await File(
      '../../.github/workflows/pocketgallery-phone-pilot-apk.yml',
    ).readAsString();

    expect(tddWorkflow, contains('scripts/android_version_code.sh'));
    expect(
      tddWorkflow,
      isNot(contains(r'--build-number="$ANDROID_VERSION_CODE"')),
      reason: 'arm64 split APKs add the 2000 ABI offset themselves',
    );
    expect(
      signedWorkflow,
      isNot(contains(r'--build-number="$ANDROID_VERSION_CODE"')),
      reason: 'the canonical path must use the same monotonic version mapping',
    );
    expect(
      tddWorkflow,
      contains('PocketGallery-R50-handset-acceptance-debug-apk'),
    );
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
