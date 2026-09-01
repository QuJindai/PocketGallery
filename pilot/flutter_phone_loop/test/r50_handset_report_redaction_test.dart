import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketgallery_phone_pilot/acceptance/handset_acceptance_models.dart';
import 'package:pocketgallery_phone_pilot/acceptance/handset_report_exporter.dart';
import 'package:pocketgallery_phone_pilot/acceptance/pocketgallery_build_identity.dart';
import 'package:pocketgallery_phone_pilot/acceptance/release_readiness_adjudicator.dart';
import 'package:pocketgallery_phone_pilot/services/golden_test_state.dart';

void main() {
  test('redacted report retains release truth but drops private text', () {
    final snapshot = _terminalSnapshot(
      h4Status: HandsetGateStatus.passed,
      mergeCandidate: true,
    );

    final encoded = utf8.decode(HandsetReportExporter.encodeRedacted(snapshot));
    final report = jsonDecode(encoded) as Map<String, dynamic>;

    expect(report['schema'], 'pocketgallery.r50.handset-acceptance.v1');
    expect(report['schemaVersion'], 1);
    expect(report['PHONE_FUNCTION_LOOP'], 'PASS');
    expect(report['DEVICE_ACCEPTANCE'], 'PASS');
    expect(report['MERGE_CANDIDATE'], isTrue);
    expect(encoded, contains('SAFE_LATENCY_MS'));
    expect(encoded, contains('12.4'));
    expect(encoded, isNot(contains('Bearer hf_secret_private')));
    expect(encoded, isNot(contains('private document body')));
    expect(encoded, isNot(contains('/private/report/path')));
    expect(encoded, isNot(contains('UNAPPROVED_TEXT_VALUE')));
  });

  test('release summary maps failed and blocked phone loops independently', () {
    final failed =
        jsonDecode(
              utf8.decode(
                HandsetReportExporter.encodeRedacted(
                  _terminalSnapshot(h4Status: HandsetGateStatus.failed),
                ),
              ),
            )
            as Map<String, dynamic>;
    final blocked =
        jsonDecode(
              utf8.decode(
                HandsetReportExporter.encodeRedacted(
                  _terminalSnapshot(h4Status: HandsetGateStatus.blocked),
                ),
              ),
            )
            as Map<String, dynamic>;

    expect(failed['PHONE_FUNCTION_LOOP'], 'FAIL');
    expect(failed['DEVICE_ACCEPTANCE'], 'FAIL');
    expect(blocked['PHONE_FUNCTION_LOOP'], 'BLOCKED');
    expect(blocked['DEVICE_ACCEPTANCE'], 'BLOCKED');
  });

  test('prohibited keys are rejected recursively at the export boundary', () {
    for (final value in <Map<String, Object?>>[
      <String, Object?>{'authorization': 'private'},
      <String, Object?>{
        'vectorF32': <double>[1, 2],
      },
      <String, Object?>{'documentText': 'private'},
      <String, Object?>{
        'safe': <String, Object?>{'body': 'private'},
      },
    ]) {
      expect(
        () => HandsetReportExporter.validateNoProhibitedKeys(value),
        throwsFormatException,
      );
    }

    expect(
      () => HandsetReportExporter.validateNoProhibitedKeys(<String, Object?>{
        'metric': <String, Object?>{'value': 12.4, 'unit': 'ms'},
      }),
      returnsNormally,
    );
  });

  test('merge-candidate encoding rejects an ineligible baseline', () {
    expect(
      () => HandsetReportExporter.encodeRedacted(
        _terminalSnapshot(
          h4Status: HandsetGateStatus.passed,
          mergeCandidate: true,
          baselineVersionCode: 2023,
        ),
      ),
      throwsFormatException,
    );
  });

  test(
    'nested cleanup and gate reasons are explicit without private detail',
    () {
      final startedAt = DateTime.utc(2026, 9, 1, 2);
      final snapshot = _terminalSnapshot(
        h4Status: HandsetGateStatus.passed,
        nestedGolden: GoldenTestSnapshot(
          runId: 'golden-redaction',
          phase: GoldenRunPhase.completed,
          startedAt: startedAt,
          updatedAt: startedAt.add(const Duration(seconds: 1)),
          cleanupError: 'Bearer hf_secret_private cleanup failed',
          gates: <GoldenGateSnapshot>[
            GoldenGateSnapshot(
              name: 'F6_GEMMA_CITATION',
              label: 'Gemma',
              timeout: const Duration(seconds: 1),
              status: GoldenGateStatus.blocked,
              detail: 'APP_BACKGROUND_INTERRUPTION',
              startedAt: startedAt,
              finishedAt: startedAt.add(const Duration(seconds: 1)),
            ),
          ],
        ),
      );

      final encoded = utf8.decode(
        HandsetReportExporter.encodeRedacted(snapshot),
      );
      final report = jsonDecode(encoded) as Map<String, dynamic>;
      final nested = report['nestedGolden'] as Map<String, dynamic>;
      final gates = nested['gates'] as List<dynamic>;

      expect(nested['cleanupError'], 'GOLDEN_CLEANUP_FAILED');
      expect(
        (gates.single as Map<String, dynamic>)['reasonCode'],
        'APP_BACKGROUND_INTERRUPTION',
      );
      expect(encoded, isNot(contains('hf_secret_private')));
    },
  );

  test('exported stable Golden reasons round-trip through adjudication', () {
    final startedAt = DateTime.utc(2026, 9, 1, 2);
    final nestedGolden = GoldenTestSnapshot(
      runId: 'golden-reason-round-trip',
      phase: GoldenRunPhase.completed,
      startedAt: startedAt,
      updatedAt: startedAt.add(const Duration(seconds: 1)),
      gates: <GoldenGateSnapshot>[
        for (var index = 0; index < _goldenGateNames.length; index += 1)
          GoldenGateSnapshot(
            name: _goldenGateNames[index],
            label: _goldenGateNames[index],
            timeout: const Duration(seconds: 1),
            status: index == 5
                ? GoldenGateStatus.blocked
                : GoldenGateStatus.passed,
            detail: index == 5 ? 'PROCESS_INTERRUPTED|USER_CANCELLED' : 'pass',
            startedAt: startedAt,
            finishedAt: startedAt.add(const Duration(seconds: 1)),
          ),
      ],
    );
    final report =
        jsonDecode(
              utf8.decode(
                HandsetReportExporter.encodeRedacted(
                  _terminalSnapshot(
                    h4Status: HandsetGateStatus.blocked,
                    nestedGolden: nestedGolden,
                  ),
                ),
              ),
            )
            as Map<String, dynamic>;

    final evidence = DeviceAcceptanceEvidence.fromJson(report);
    final nested = report['nestedGolden'] as Map<String, dynamic>;
    final gates = nested['gates'] as List<dynamic>;

    expect(evidence.nestedGoldenPassed, isFalse);
    expect(
      (gates[5] as Map<String, dynamic>)['reasonCode'],
      'PROCESS_INTERRUPTED|USER_CANCELLED',
    );
  });
}

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

HandsetAcceptanceSnapshot _terminalSnapshot({
  required HandsetGateStatus h4Status,
  bool mergeCandidate = false,
  int baselineVersionCode = 2022,
  GoldenTestSnapshot? nestedGolden,
}) {
  final startedAt = DateTime.utc(2026, 9, 1, 2);
  final gates = <HandsetGateSnapshot>[];
  for (final entry in handsetGateWeights.entries) {
    final status = entry.key == 'H4_PHONE_FUNCTION_LOOP'
        ? h4Status
        : HandsetGateStatus.passed;
    gates.add(
      HandsetGateSnapshot(
        name: entry.key,
        label: entry.key,
        status: status,
        detail: entry.key == 'H4_PHONE_FUNCTION_LOOP'
            ? 'Bearer hf_secret_private private document body'
            : '',
        evidence: _evidenceFor(entry.key),
        startedAt: startedAt,
        finishedAt: startedAt.add(const Duration(seconds: 1)),
      ),
    );
  }
  return HandsetAcceptanceSnapshot(
    runId: 'r50-redacted-report',
    phase: HandsetRunPhase.completed,
    startedAt: startedAt,
    updatedAt: startedAt.add(const Duration(seconds: 10)),
    gates: gates,
    reportPath: '/private/report/path',
    baselineVersionCode: baselineVersionCode,
    mergeCandidate: mergeCandidate,
    nestedGolden: nestedGolden,
  );
}

List<AcceptanceEvidence> _evidenceFor(String gateName) {
  if (gateName == 'H1_TARGET_DEVICE') {
    return <AcceptanceEvidence>[
      _evidence(
        code: 'TARGET_MANUFACTURER',
        source: 'Build.MANUFACTURER',
        actual: 'samsung',
        threshold: 'samsung',
      ),
      _evidence(
        code: 'TARGET_MODEL',
        source: 'Build.MODEL',
        actual: 'SM-S9280',
        threshold: r'^SM-S928[A-Z0-9]*$',
      ),
    ];
  }
  if (gateName == 'H2_BUILD_IDENTITY') {
    return <AcceptanceEvidence>[
      _evidence(
        code: 'PACKAGE_NAME',
        source: 'PackageManager',
        actual: PocketGalleryBuildIdentity.packageName,
        threshold: PocketGalleryBuildIdentity.packageName,
      ),
      _evidence(
        code: 'VERSION_CODE',
        source: 'PackageInfo.longVersionCode',
        actual: 2023,
        threshold: 2023,
      ),
      _evidence(
        code: 'SIGNER_SHA256',
        source: 'SigningInfo.apkContentsSigners',
        actual: PocketGalleryBuildIdentity.canonicalSignerSha256,
        threshold: PocketGalleryBuildIdentity.canonicalSignerSha256,
      ),
      _evidence(
        code: 'APK_SHA256',
        source: 'ApplicationInfo.sourceDir',
        actual:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        threshold: '64 hex characters',
      ),
      _evidence(
        code: 'SOURCE_COMMIT',
        source: 'POCKETGALLERY_SOURCE_COMMIT',
        actual: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        threshold: '40 hex characters',
      ),
    ];
  }
  if (gateName == 'H3_UPGRADE_BASELINE') {
    return <AcceptanceEvidence>[
      _evidence(
        code: 'BASELINE_VERSION_CODE',
        source: 'PG_HANDSET_BASELINE.json',
        actual: 2022,
        threshold: 2023,
      ),
    ];
  }
  if (gateName == 'H4_PHONE_FUNCTION_LOOP') {
    return <AcceptanceEvidence>[
      _evidence(
        code: 'SAFE_LATENCY_MS',
        source: 'FrameTiming',
        actual: 12.4,
        threshold: 16.7,
        unit: 'ms',
        detail: 'Bearer hf_secret_private private document body',
      ),
      _evidence(
        code: 'UNAPPROVED_TEXT',
        source: 'private document body',
        actual: 'UNAPPROVED_TEXT_VALUE',
        threshold: null,
      ),
    ];
  }
  return const <AcceptanceEvidence>[];
}

AcceptanceEvidence _evidence({
  required String code,
  required String source,
  required Object? actual,
  required Object? threshold,
  String? unit,
  String detail = 'safe detail',
}) {
  return AcceptanceEvidence(
    code: code,
    method: EvidenceMethod.measured,
    source: source,
    actual: actual,
    threshold: threshold,
    unit: unit,
    available: true,
    detail: detail,
  );
}
