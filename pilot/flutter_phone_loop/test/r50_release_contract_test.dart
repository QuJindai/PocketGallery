import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String tddWorkflow;
  late String canonicalWorkflow;

  setUpAll(() async {
    tddWorkflow = await File(
      '../../.github/workflows/pocketgallery-r46-tdd.yml',
    ).readAsString();
    canonicalWorkflow = await File(
      '../../.github/workflows/pocketgallery-phone-pilot-apk.yml',
    ).readAsString();
  });

  test('R5.0 build 23 maps to candidate Android versionCode 2023', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    expect(pubspec, contains('version: 0.5.0+23'));

    final result = await Process.run(
      'bash',
      <String>['scripts/android_version_code.sh'],
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect((result.stdout as String).trim(), '2023');
  });

  test('both workflows compile the checked-out source commit into every APK',
      () {
    for (final workflow in <String>[tddWorkflow, canonicalWorkflow]) {
      expect(
        workflow,
        matches(
          RegExp(
            r'SOURCE_COMMIT="\$\(git rev-parse HEAD\)"',
          ),
        ),
      );
      expect(
        workflow,
        contains(
          r'--dart-define=POCKETGALLERY_SOURCE_COMMIT="$SOURCE_COMMIT"',
        ),
      );
    }
    expect(
      RegExp('POCKETGALLERY_SOURCE_COMMIT').allMatches(canonicalWorkflow).length,
      greaterThanOrEqualTo(2),
    );
  });

  test('TDD workflow publishes an explicit non-canonical R5 arm64 artifact',
      () {
    expect(tddWorkflow, contains('PocketGallery-R50-handset-acceptance-debug.apk'));
    expect(
      tddWorkflow,
      contains('PocketGallery-R50-handset-acceptance-debug.apk.sha256'),
    );
    expect(tddWorkflow, contains('APK_ABIS'));
    expect(tddWorkflow, contains('arm64-v8a'));
    expect(tddWorkflow, contains('EXPECTED_VERSION_CODE=2023'));
    expect(
      tddWorkflow,
      isNot(contains(r'--build-number="$ANDROID_VERSION_CODE"')),
    );
  });

  test('canonical workflow builds and verifies the same-source upgrade pair',
      () {
    expect(canonicalWorkflow, contains('--build-name=0.5.0'));
    expect(canonicalWorkflow, contains('--build-number=22'));
    expect(canonicalWorkflow, contains('--build-number=23'));
    expect(
      canonicalWorkflow,
      contains('PocketGallery-R50-baseline-v2022.apk'),
    );
    expect(
      canonicalWorkflow,
      contains('PocketGallery-R50-candidate-v2023.apk'),
    );
    expect(canonicalWorkflow, contains(r'verify_apk "$BASELINE_APK" 2022'));
    expect(canonicalWorkflow, contains(r'verify_apk "$CANDIDATE_APK" 2023'));
    expect(
      canonicalWorkflow,
      contains(r'test "$PKG" = "com.qujindai.pocketgallery_phone_pilot.r3"'),
    );
    expect(canonicalWorkflow, contains(r'test "$ABIS" = "arm64-v8a"'));
    expect(
      canonicalWorkflow,
      contains(r'test "$APK_CERT" = "$CANONICAL_SIGNER_SHA256"'),
    );
    for (final fileName in <String>[
      'PocketGallery-R50-baseline-v2022.apk.sha256',
      'PocketGallery-R50-candidate-v2023.apk.sha256',
    ]) {
      expect(canonicalWorkflow, contains(fileName));
    }
  });

  test('canonical evidence is emitted only after tests and pair verification',
      () {
    final analyze = canonicalWorkflow.indexOf('- name: Analyze');
    final tests = canonicalWorkflow.indexOf('- name: Unit tests');
    final builds = canonicalWorkflow.indexOf('- name: Build same-source R5.0');
    final verification = canonicalWorkflow.indexOf(
      '- name: Verify canonical R5.0 upgrade pair',
    );
    final evidence = canonicalWorkflow.indexOf(
      '- name: Emit automated release evidence',
    );
    expect(analyze, greaterThan(0));
    expect(tests, greaterThan(analyze));
    expect(builds, greaterThan(tests));
    expect(verification, greaterThan(builds));
    expect(evidence, greaterThan(verification));

    for (final contract in <String>[
      'pocketgallery.r50.automated-evidence.v1',
      r'"sourceCommit": "$SOURCE_COMMIT"',
      '"automatedGatesPassed": true',
      '"packageName": "com.qujindai.pocketgallery_phone_pilot.r3"',
      '"baselineVersionCode": 2022',
      '"versionCode": 2023',
      r'"signerSha256": "$CANONICAL_SIGNER_SHA256"',
      r'"apkSha256": "$CANDIDATE_SHA256"',
      r'"workflowIdentity": "$GITHUB_WORKFLOW/$GITHUB_RUN_ID/$GITHUB_RUN_ATTEMPT"',
      'PG_AUTOMATED_EVIDENCE.json',
    ]) {
      expect(canonicalWorkflow, contains(contract));
    }
  });

  test('canonical signing is isolated from pull requests and Actions cache',
      () {
    expect(canonicalWorkflow, isNot(contains('\n  pull_request:')));
    expect(canonicalWorkflow, isNot(contains('actions/cache')));
    expect(
      canonicalWorkflow,
      isNot(contains('pocketgallery-r3-signing-v1')),
    );
    expect(
      canonicalWorkflow,
      isNot(contains('feature/phone-pilot-')),
    );

    final secretNames = RegExp(r'secrets\.([A-Z0-9_]+)')
        .allMatches(canonicalWorkflow)
        .map((match) => match.group(1)!)
        .toSet();
    expect(secretNames, <String>{
      'POCKETGALLERY_SIGNING_KEYSTORE_B64',
      'POCKETGALLERY_SIGNING_STORE_PASSWORD',
      'POCKETGALLERY_SIGNING_KEY_PASSWORD',
      'POCKETGALLERY_SIGNING_KEY_ALIAS',
    });
    expect(
      canonicalWorkflow,
      contains(
        r'SECRET_KEYSTORE="$RUNNER_TEMP/pocketgallery-r3-signing/r3.keystore"',
      ),
    );
    expect(
      canonicalWorkflow,
      isNot(
        matches(
          RegExp(
            r'keytool\s+-(?:genkey|genkeypair)',
            caseSensitive: false,
          ),
        ),
      ),
    );
    expect(canonicalWorkflow, isNot(contains('SIGNING_KEY_ALIAS=new')));
    expect(canonicalWorkflow, contains('SIGNING_IDENTITY_MISSING'));
    expect(canonicalWorkflow, contains('exit 74'));
  });

  test('R5 documentation pins the physical S24U acceptance handoff', () async {
    final readme = await File('README.md').readAsString();
    final checklist = await File(
      '../../docs/phone-pilot/release-checklist.md',
    ).readAsString();
    final matrix = await File(
      '../../docs/phone-pilot/verification-matrix.md',
    ).readAsString();
    final runbook = await File(
      '../../docs/phone-pilot/r50-s24u-handset-acceptance-runbook.md',
    ).readAsString();

    expect(readme, contains('PocketGallery Phone Pilot R5.0'));
    expect(readme, contains('手机一键验收'));
    expect(checklist, contains('0.5.0+23'));
    expect(checklist, contains('versionCode `2022`'));
    expect(checklist, contains('versionCode `2023`'));
    expect(checklist, contains('PG_MERGE_READINESS.json'));
    expect(matrix, contains('H1–H10'));
    expect(matrix, contains('F1–F10'));
    expect(matrix, contains('PG_AUTOMATED_EVIDENCE.json'));
    expect(runbook, contains('SM-S928'));
    expect(runbook, contains('不得卸载'));
    expect(runbook, contains('PocketGallery-R50-baseline-v2022.apk'));
    expect(runbook, contains('PocketGallery-R50-candidate-v2023.apk'));
    expect(runbook, contains('导出脱敏报告'));
    expect(runbook, contains('adjudicate_handset_acceptance.dart'));
  });
}
