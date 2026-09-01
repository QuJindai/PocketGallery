import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/release_version.dart';

void main() {
  const applicationId = 'com.qujindai.pocketgallery_phone_pilot.r3';
  const signerSha256 =
      '81af4a5ef94c236774f0e193b2a4b248805b36c14cc36e2a56df8e451a712541';

  test('R4.6 B/C release preserves upgrade identity at build 20 or later',
      () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    final workflow = await File(
      '../../.github/workflows/pocketgallery-phone-pilot-apk.yml',
    ).readAsString();
    final bootstrap = await File('scripts/bootstrap_android.sh').readAsString();

    final version = parseReleaseVersion(pubspec);
    expect(
      isReleaseVersionAtLeast(version, major: 0, minor: 4, patch: 17),
      isTrue,
    );
    expect(version.build, greaterThanOrEqualTo(20));
    expect(bootstrap, contains(applicationId));
    expect(workflow, contains(signerSha256));
    expect(workflow, contains('android-arm64 --split-per-abi'));
    expect(workflow, contains(r'test "$PKG" = "' + applicationId + r'"'));
    expect(workflow, contains(r'test "$VERSION_CODE" -ge 2020'));
  });
}
