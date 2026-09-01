import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketgallery_phone_pilot/acceptance/pocketgallery_build_identity.dart';
import 'package:pocketgallery_phone_pilot/acceptance/release_readiness_adjudicator.dart';

void main() {
  group('R5.0 same-commit release readiness', () {
    test('matching automated, device, and sidecar evidence is MERGE_READY', () {
      final decision = _adjudicate();

      expect(decision.mergeReady, isTrue);
      expect(decision.reasons, isEmpty);
      expect(decision.toJson(), <String, Object?>{
        'schema': 'pocketgallery.r50.merge-readiness.v1',
        'mergeReady': true,
        'reasons': <String>[],
        'sourceCommit': _sourceCommit,
        'versionCode': 2023,
        'apkSha256': _apkSha256,
      });
    });

    test('each well-shaped evidence mismatch emits its one stable reason', () {
      final cases =
          <
            ({
              String reason,
              void Function(Map<String, dynamic>, Map<String, dynamic>) mutate,
              String sidecar,
            })
          >[
            (
              reason: 'SOURCE_COMMIT_MISMATCH',
              mutate: (device, automated) =>
                  automated['sourceCommit'] = _alternateCommit,
              sidecar: _apkSha256,
            ),
            (
              reason: 'PACKAGE_MISMATCH',
              mutate: (device, automated) =>
                  (device['identity'] as Map<String, dynamic>)['packageName'] =
                      'com.example.wrong',
              sidecar: _apkSha256,
            ),
            (
              reason: 'VERSION_CODE_MISMATCH',
              mutate: (device, automated) =>
                  (device['identity'] as Map<String, dynamic>)['versionCode'] =
                      2024,
              sidecar: _apkSha256,
            ),
            (
              reason: 'SIGNER_MISMATCH',
              mutate: (device, automated) =>
                  (device['identity'] as Map<String, dynamic>)['signerSha256'] =
                      _alternateDigest,
              sidecar: _apkSha256,
            ),
            (
              reason: 'DEVICE_APK_DIGEST_MISMATCH',
              mutate: (device, automated) =>
                  (device['identity'] as Map<String, dynamic>)['apkSha256'] =
                      _alternateDigest,
              sidecar: _apkSha256,
            ),
            (
              reason: 'SIDECAR_DIGEST_MISMATCH',
              mutate: (device, automated) {},
              sidecar: _alternateDigest,
            ),
            (
              reason: 'AUTOMATED_GATES_FAILED',
              mutate: (device, automated) =>
                  automated['automatedGatesPassed'] = false,
              sidecar: _apkSha256,
            ),
            (
              reason: 'DEVICE_GATE_STATUS_INVALID',
              mutate: (device, automated) =>
                  (device['gates'] as List<dynamic>)[4]['status'] = 'FAILED',
              sidecar: _apkSha256,
            ),
            (
              reason: 'PHONE_FUNCTION_LOOP_NOT_PASS',
              mutate: (device, automated) =>
                  device['PHONE_FUNCTION_LOOP'] = 'FAIL',
              sidecar: _apkSha256,
            ),
            (
              reason: 'NESTED_GOLDEN_NOT_PASS',
              mutate: (device, automated) {
                final nested = device['nestedGolden'] as Map<String, dynamic>;
                nested['passed'] = false;
                (nested['gates'] as List<dynamic>)[5]
                  ..['status'] = 'FAILED'
                  ..['reasonCode'] = 'GATE_FAILED';
              },
              sidecar: _apkSha256,
            ),
            (
              reason: 'DEVICE_ACCEPTANCE_NOT_PASS',
              mutate: (device, automated) =>
                  device['DEVICE_ACCEPTANCE'] = 'BLOCKED',
              sidecar: _apkSha256,
            ),
            (
              reason: 'MERGE_CANDIDATE_FALSE',
              mutate: (device, automated) => device['MERGE_CANDIDATE'] = false,
              sidecar: _apkSha256,
            ),
          ];

      for (final testCase in cases) {
        final device = _deviceJson();
        final automated = _automatedJson();
        testCase.mutate(device, automated);

        final decision = _adjudicate(
          device: device,
          automated: automated,
          sidecar: testCase.sidecar,
        );

        expect(decision.mergeReady, isFalse, reason: testCase.reason);
        expect(decision.reasons, <String>[
          testCase.reason,
        ], reason: testCase.reason);
      }
    });

    test('all mismatch reasons retain the release-contract order', () {
      final device = _deviceJson();
      final automated = _automatedJson();
      final identity = device['identity'] as Map<String, dynamic>;
      automated
        ..['sourceCommit'] = _alternateCommit
        ..['automatedGatesPassed'] = false;
      identity
        ..['packageName'] = 'com.example.wrong'
        ..['versionCode'] = 2024
        ..['signerSha256'] = _alternateDigest
        ..['apkSha256'] = _alternateDigest;
      (device['gates'] as List<dynamic>)[4]['status'] = 'FAILED';
      device
        ..['PHONE_FUNCTION_LOOP'] = 'FAIL'
        ..['DEVICE_ACCEPTANCE'] = 'BLOCKED'
        ..['MERGE_CANDIDATE'] = false;
      final nested = device['nestedGolden'] as Map<String, dynamic>;
      nested['passed'] = false;
      (nested['gates'] as List<dynamic>)[5]
        ..['status'] = 'FAILED'
        ..['reasonCode'] = 'GATE_FAILED';

      final decision = _adjudicate(
        device: device,
        automated: automated,
        sidecar: _sidecarAlternateDigest,
      );

      expect(decision.reasons, <String>[
        'SOURCE_COMMIT_MISMATCH',
        'PACKAGE_MISMATCH',
        'VERSION_CODE_MISMATCH',
        'SIGNER_MISMATCH',
        'DEVICE_APK_DIGEST_MISMATCH',
        'SIDECAR_DIGEST_MISMATCH',
        'AUTOMATED_GATES_FAILED',
        'DEVICE_GATE_STATUS_INVALID',
        'PHONE_FUNCTION_LOOP_NOT_PASS',
        'NESTED_GOLDEN_NOT_PASS',
        'DEVICE_ACCEPTANCE_NOT_PASS',
        'MERGE_CANDIDATE_FALSE',
      ]);
    });

    test(
      'digest hex is normalized but source commit comparison stays exact',
      () {
        final automated = _automatedJson()
          ..['signerSha256'] = PocketGalleryBuildIdentity.canonicalSignerSha256
              .toUpperCase()
          ..['apkSha256'] = _apkSha256.toUpperCase();
        expect(
          _adjudicate(
            automated: automated,
            sidecar: _apkSha256.toUpperCase(),
          ).mergeReady,
          isTrue,
        );

        automated['sourceCommit'] = _sourceCommit.toUpperCase();
        expect(
          _adjudicate(automated: automated).reasons,
          contains('SOURCE_COMMIT_MISMATCH'),
        );
      },
    );
  });

  group('R5.0 strict evidence parsing', () {
    test('rejects unknown schemas and missing or wrong-typed fields', () {
      final invalid = <Map<String, dynamic>>[
        _deviceJson()..['schema'] = 'unknown',
        _deviceJson()..remove('identity'),
        _deviceJson()..['MERGE_CANDIDATE'] = 'true',
      ];

      for (final value in invalid) {
        expect(
          () => DeviceAcceptanceEvidence.fromJson(value),
          throwsFormatException,
        );
      }

      final invalidAutomated = <Map<String, dynamic>>[
        _automatedJson()..['schema'] = 'unknown',
        _automatedJson()..remove('workflowIdentity'),
        _automatedJson()..['automatedGatesPassed'] = 'true',
      ];
      for (final value in invalidAutomated) {
        expect(
          () => AutomatedReleaseEvidence.fromJson(value),
          throwsFormatException,
        );
      }
    });

    test('rejects malformed commits and SHA-256 digests', () {
      final badCommit = _deviceJson();
      (badCommit['identity'] as Map<String, dynamic>)['sourceCommit'] =
          'not-a-commit';
      expect(
        () => DeviceAcceptanceEvidence.fromJson(badCommit),
        throwsFormatException,
      );

      final badDigest = _automatedJson()..['apkSha256'] = 'abcd';
      expect(
        () => AutomatedReleaseEvidence.fromJson(badDigest),
        throwsFormatException,
      );
      expect(
        () => ReleaseReadinessAdjudicator.adjudicate(
          DeviceAcceptanceEvidence.fromJson(_deviceJson()),
          AutomatedReleaseEvidence.fromJson(_automatedJson()),
          'malformed-sidecar',
        ),
        throwsFormatException,
      );
    });

    test('rejects missing duplicate and unknown H gate names', () {
      final cases = <Map<String, dynamic>>[
        _deviceJson()
          ..['gates'] = (_deviceJson()['gates'] as List<dynamic>)
              .take(9)
              .toList(),
        _mutateDeviceGateName(1, _handsetGateNames.first),
        _mutateDeviceGateName(0, 'H11_UNKNOWN'),
      ];

      for (final value in cases) {
        expect(
          () => DeviceAcceptanceEvidence.fromJson(value),
          throwsFormatException,
        );
      }
    });

    test('rejects missing duplicate and unknown nested F gate names', () {
      final missing = _deviceJson();
      final missingNested = missing['nestedGolden'] as Map<String, dynamic>;
      missingNested['gates'] = (missingNested['gates'] as List<dynamic>)
          .take(9)
          .toList();
      final duplicate = _mutateGoldenGateName(1, _goldenGateNames.first);
      final unknown = _mutateGoldenGateName(0, 'F11_UNKNOWN');

      for (final value in <Map<String, dynamic>>[missing, duplicate, unknown]) {
        expect(
          () => DeviceAcceptanceEvidence.fromJson(value),
          throwsFormatException,
        );
      }
    });

    test('rejects nested Golden evidence without explicit cleanup state', () {
      final device = _deviceJson();
      final nested = device['nestedGolden'] as Map<String, dynamic>;
      nested.remove('cleanupError');

      expect(
        () => DeviceAcceptanceEvidence.fromJson(device),
        throwsFormatException,
      );
    });

    test('rejects missing malformed or empty nested Golden reason codes', () {
      final missing = _deviceJson();
      final missingNested = missing['nestedGolden'] as Map<String, dynamic>;
      (missingNested['gates'] as List<dynamic>).first.remove('reasonCode');

      final malformed = _deviceJson();
      final malformedNested = malformed['nestedGolden'] as Map<String, dynamic>;
      (malformedNested['gates'] as List<dynamic>).first['reasonCode'] = 7;

      final emptyFailure = _deviceJson();
      final emptyFailureNested =
          emptyFailure['nestedGolden'] as Map<String, dynamic>;
      emptyFailureNested['passed'] = false;
      (emptyFailureNested['gates'] as List<dynamic>).first
        ..['status'] = 'FAILED'
        ..['reasonCode'] = null;

      for (final value in <Map<String, dynamic>>[
        missing,
        malformed,
        emptyFailure,
      ]) {
        expect(
          () => DeviceAcceptanceEvidence.fromJson(value),
          throwsFormatException,
        );
      }
    });

    test('rejects nested Golden reason codes inconsistent with status', () {
      final passedWithFailure = _deviceJson();
      final passedNested =
          passedWithFailure['nestedGolden'] as Map<String, dynamic>;
      (passedNested['gates'] as List<dynamic>).first['reasonCode'] =
          'GATE_FAILED';

      final timeoutWithFailure = _deviceJson();
      final timeoutNested =
          timeoutWithFailure['nestedGolden'] as Map<String, dynamic>;
      timeoutNested['passed'] = false;
      (timeoutNested['gates'] as List<dynamic>).first
        ..['status'] = 'TIMEDOUT'
        ..['reasonCode'] = 'GATE_FAILED';

      for (final value in <Map<String, dynamic>>[
        passedWithFailure,
        timeoutWithFailure,
      ]) {
        expect(
          () => DeviceAcceptanceEvidence.fromJson(value),
          throwsFormatException,
        );
      }
    });

    test('accepts status-consistent nested Golden reason codes', () {
      final device = _deviceJson();
      final nested = device['nestedGolden'] as Map<String, dynamic>;
      nested['passed'] = false;
      (nested['gates'] as List<dynamic>).first
        ..['status'] = 'TIMEDOUT'
        ..['reasonCode'] = 'GATE_TIMEOUT';

      expect(
        DeviceAcceptanceEvidence.fromJson(device).nestedGoldenPassed,
        isFalse,
      );
    });
  });

  group('R5.0 adjudicator CLI', () {
    test('--help prints usage and exits zero', () async {
      final result = await _runCli(<String>['--help']);

      expect(result.exitCode, 0);
      expect(result.stdout, contains('--device-report'));
      expect(result.stdout, contains('--automated-evidence'));
      expect(result.stdout, contains('--apk-sha256'));
      expect(result.stdout, contains('--output'));
    });

    test('writes ready output atomically and exits zero', () async {
      final fixture = await _CliFixture.create();
      addTearDown(fixture.dispose);

      final result = await _runCli(fixture.arguments);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, contains('MERGE_READY=true'));
      expect(fixture.output.existsSync(), isTrue);
      expect(File('${fixture.output.path}.tmp').existsSync(), isFalse);
      final decoded =
          jsonDecode(await fixture.output.readAsString())
              as Map<String, dynamic>;
      expect(decoded['mergeReady'], isTrue);
      expect(decoded['reasons'], isEmpty);
    });

    test('evidence mismatch writes a decision and exits two', () async {
      final fixture = await _CliFixture.create(
        automated: _automatedJson()..['automatedGatesPassed'] = false,
      );
      addTearDown(fixture.dispose);

      final result = await _runCli(fixture.arguments);

      expect(result.exitCode, 2);
      expect(result.stdout, contains('MERGE_READY=false'));
      final decoded =
          jsonDecode(await fixture.output.readAsString())
              as Map<String, dynamic>;
      expect(decoded['reasons'], <String>['AUTOMATED_GATES_FAILED']);
    });

    test('missing arguments exit sixty-four without creating output', () async {
      final result = await _runCli(const <String>[]);

      expect(result.exitCode, 64);
      expect(result.stderr, contains('Usage:'));
    });
  });
}

ReleaseReadinessDecision _adjudicate({
  Map<String, dynamic>? device,
  Map<String, dynamic>? automated,
  String sidecar = _apkSha256,
}) {
  return ReleaseReadinessAdjudicator.adjudicate(
    DeviceAcceptanceEvidence.fromJson(device ?? _deviceJson()),
    AutomatedReleaseEvidence.fromJson(automated ?? _automatedJson()),
    sidecar,
  );
}

Map<String, dynamic> _deviceJson() => <String, dynamic>{
  'schema': 'pocketgallery.r50.handset-acceptance.v1',
  'schemaVersion': 1,
  'runId': 'r50-release-test',
  'PHONE_FUNCTION_LOOP': 'PASS',
  'DEVICE_ACCEPTANCE': 'PASS',
  'MERGE_CANDIDATE': true,
  'baselineVersionCode': 2022,
  'identity': <String, dynamic>{
    'manufacturer': 'samsung',
    'model': 'SM-S9280',
    'packageName': PocketGalleryBuildIdentity.packageName,
    'versionCode': 2023,
    'signerSha256': PocketGalleryBuildIdentity.canonicalSignerSha256,
    'apkSha256': _apkSha256,
    'sourceCommit': _sourceCommit,
  },
  'gates': <Map<String, dynamic>>[
    for (final name in _handsetGateNames)
      <String, dynamic>{'name': name, 'status': 'PASSED'},
  ],
  'nestedGolden': <String, dynamic>{
    'schemaVersion': 2,
    'runId': 'golden-release-test',
    'phase': 'COMPLETED',
    'passed': true,
    'cleanupError': null,
    'gates': <Map<String, dynamic>>[
      for (final name in _goldenGateNames)
        <String, dynamic>{'name': name, 'status': 'PASSED', 'reasonCode': null},
    ],
  },
};

Map<String, dynamic> _automatedJson() => <String, dynamic>{
  'schema': 'pocketgallery.r50.automated-evidence.v1',
  'sourceCommit': _sourceCommit,
  'automatedGatesPassed': true,
  'packageName': PocketGalleryBuildIdentity.packageName,
  'baselineVersionCode': 2022,
  'versionCode': 2023,
  'signerSha256': PocketGalleryBuildIdentity.canonicalSignerSha256,
  'apkSha256': _apkSha256,
  'workflowIdentity': 'PocketGallery Phone Pilot APK/123/1',
};

Map<String, dynamic> _mutateDeviceGateName(int index, String name) {
  final value = _deviceJson();
  (value['gates'] as List<dynamic>)[index]['name'] = name;
  return value;
}

Map<String, dynamic> _mutateGoldenGateName(int index, String name) {
  final value = _deviceJson();
  final nested = value['nestedGolden'] as Map<String, dynamic>;
  (nested['gates'] as List<dynamic>)[index]['name'] = name;
  return value;
}

Future<ProcessResult> _runCli(List<String> arguments) {
  return Process.run('dart', <String>[
    'run',
    'tool/adjudicate_handset_acceptance.dart',
    ...arguments,
  ], workingDirectory: Directory.current.path);
}

final class _CliFixture {
  _CliFixture._({
    required this.directory,
    required this.device,
    required this.automated,
    required this.sidecar,
    required this.output,
  });

  final Directory directory;
  final File device;
  final File automated;
  final File sidecar;
  final File output;

  List<String> get arguments => <String>[
    '--device-report',
    device.path,
    '--automated-evidence',
    automated.path,
    '--apk-sha256',
    sidecar.path,
    '--output',
    output.path,
  ];

  static Future<_CliFixture> create({Map<String, dynamic>? automated}) async {
    final directory = await Directory.systemTemp.createTemp('pg-r50-adj-');
    final deviceFile = File('${directory.path}/device.json');
    final automatedFile = File('${directory.path}/automated.json');
    final sidecarFile = File('${directory.path}/candidate.apk.sha256');
    final outputFile = File('${directory.path}/readiness.json');
    await deviceFile.writeAsString(jsonEncode(_deviceJson()));
    await automatedFile.writeAsString(
      jsonEncode(automated ?? _automatedJson()),
    );
    await sidecarFile.writeAsString(
      '$_apkSha256  PocketGallery-R50-candidate-v2023.apk\n',
    );
    return _CliFixture._(
      directory: directory,
      device: deviceFile,
      automated: automatedFile,
      sidecar: sidecarFile,
      output: outputFile,
    );
  }

  Future<void> dispose() => directory.delete(recursive: true);
}

const String _sourceCommit = '0123456789abcdef0123456789abcdef01234567';
const String _alternateCommit = 'fedcba9876543210fedcba9876543210fedcba98';
const String _apkSha256 =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const String _alternateDigest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _sidecarAlternateDigest =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

const List<String> _handsetGateNames = <String>[
  'H1_TARGET_DEVICE',
  'H2_BUILD_IDENTITY',
  'H3_UPGRADE_BASELINE',
  'H4_PHONE_FUNCTION_LOOP',
  'H5_VECTOR_3D_TRUTH',
  'H6_VECTOR_INTERACTION',
  'H7_RENDER_PERFORMANCE',
  'H8_MEMORY_THERMAL',
  'H9_DATA_PRESERVATION',
  'H10_REPORT_INTEGRITY',
];

const List<String> _goldenGateNames = <String>[
  'F1_IMPORT_CHUNK',
  'F2_FTS5',
  'F3_EMBEDDING',
  'F4_HYBRID_RERANK',
  'F5_EVIDENCE',
  'F6_GEMMA_CITATION',
  'F7_CHAT_REALWORLD',
  'F8_RUNTIME_LINEAGE',
  'F9_QUERY_VECTOR_IDENTITY',
  'F10_CONTEXT_BUDGET',
];
