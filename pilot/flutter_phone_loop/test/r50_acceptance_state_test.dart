import 'package:flutter_test/flutter_test.dart';
import 'package:pocketgallery_phone_pilot/acceptance/handset_acceptance_models.dart';
import 'package:pocketgallery_phone_pilot/acceptance/pocketgallery_build_identity.dart';
import 'package:pocketgallery_phone_pilot/services/golden_test_state.dart';

void main() {
  test('a failed gate outranks blocked gates in the device verdict', () {
    final snapshot = _snapshot(
      gates: <HandsetGateSnapshot>[
        _gate('H1_TARGET_DEVICE', HandsetGateStatus.blocked),
        _gate('H7_RENDER_PERFORMANCE', HandsetGateStatus.failed),
      ],
    );

    expect(snapshot.verdict, AcceptanceVerdict.fail);
  });

  test('an incomplete run remains blocked when no gate has failed', () {
    final snapshot = _snapshot(
      phase: HandsetRunPhase.runningAutomated,
      gates: <HandsetGateSnapshot>[
        _gate('H1_TARGET_DEVICE', HandsetGateStatus.passed),
        _gate('H2_BUILD_IDENTITY', HandsetGateStatus.running),
      ],
    );

    expect(snapshot.verdict, AcceptanceVerdict.blocked);
  });

  test('nested Golden progress occupies only the fixed H4 weight', () {
    final snapshot = _snapshot(
      phase: HandsetRunPhase.runningAutomated,
      gates: <HandsetGateSnapshot>[
        _gate('H1_TARGET_DEVICE', HandsetGateStatus.passed),
        _gate('H2_BUILD_IDENTITY', HandsetGateStatus.passed),
        _gate('H3_UPGRADE_BASELINE', HandsetGateStatus.passed),
        _gate('H4_PHONE_FUNCTION_LOOP', HandsetGateStatus.running),
      ],
      nestedGolden: _goldenAtFiftyPercent(),
    );

    expect(snapshot.percent, 38);
  });

  test('schema version one round trips every evidence field', () {
    final source = _snapshot(
      baselineVersionCode: 2022,
      reportPath: '/private/PG_HANDSET_ACCEPTANCE_r50-test.json',
      mergeCandidate: true,
      gates: <HandsetGateSnapshot>[
        _gate(
          'H1_TARGET_DEVICE',
          HandsetGateStatus.passed,
          evidence: const <AcceptanceEvidence>[
            AcceptanceEvidence(
              code: 'TARGET_MODEL',
              method: EvidenceMethod.measured,
              source: 'Build.MODEL',
              actual: 'SM-S9280',
              threshold: r'^SM-S928[A-Z0-9]*$',
              unit: null,
              available: true,
              detail: 'target matched',
            ),
            AcceptanceEvidence(
              code: 'DISPLAY_RATE',
              method: EvidenceMethod.observed,
              source: 'Display.refreshRate',
              actual: 120.0,
              threshold: 60,
              unit: 'Hz',
              available: true,
              detail: 'measured on device',
            ),
          ],
        ),
      ],
    );

    expect(
      HandsetAcceptanceSnapshot.fromJson(source.toJson()).toJson(),
      source.toJson(),
    );
  });

  test('an unknown acceptance schema is rejected', () {
    final json = _snapshot(
      gates: <HandsetGateSnapshot>[
        _gate('H1_TARGET_DEVICE', HandsetGateStatus.passed),
      ],
    ).toJson();
    json['schemaVersion'] = 2;

    expect(
      () => HandsetAcceptanceSnapshot.fromJson(json),
      throwsFormatException,
    );
  });

  test('release source identity accepts only forty hexadecimal characters', () {
    final commit = List<String>.filled(40, 'a').join();

    expect(PocketGalleryBuildIdentity.isValidSourceCommit(commit), isTrue);
    expect(
      PocketGalleryBuildIdentity.isValidSourceCommit('${commit}0'),
      isFalse,
    );
    expect(PocketGalleryBuildIdentity.isValidSourceCommit('local'), isFalse);
  });
}

final DateTime _startedAt = DateTime.utc(2026, 9, 1);

HandsetGateSnapshot _gate(
  String name,
  HandsetGateStatus status, {
  List<AcceptanceEvidence> evidence = const <AcceptanceEvidence>[],
}) {
  return HandsetGateSnapshot(
    name: name,
    label: name,
    status: status,
    detail: '',
    evidence: evidence,
    startedAt: _startedAt,
    finishedAt: status == HandsetGateStatus.running ? null : _startedAt,
  );
}

HandsetAcceptanceSnapshot _snapshot({
  HandsetRunPhase phase = HandsetRunPhase.completed,
  required List<HandsetGateSnapshot> gates,
  GoldenTestSnapshot? nestedGolden,
  String? reportPath,
  int? baselineVersionCode,
  bool mergeCandidate = false,
}) {
  return HandsetAcceptanceSnapshot(
    runId: 'r50-test',
    phase: phase,
    startedAt: _startedAt,
    updatedAt: _startedAt.add(const Duration(seconds: 2)),
    gates: gates,
    nestedGolden: nestedGolden,
    reportPath: reportPath,
    baselineVersionCode: baselineVersionCode,
    mergeCandidate: mergeCandidate,
  );
}

GoldenTestSnapshot _goldenAtFiftyPercent() {
  return GoldenTestSnapshot(
    runId: 'golden-50',
    phase: GoldenRunPhase.running,
    startedAt: _startedAt,
    updatedAt: _startedAt,
    gates: List<GoldenGateSnapshot>.generate(
      9,
      (index) => GoldenGateSnapshot(
        name: 'F${index + 1}',
        label: 'F${index + 1}',
        timeout: const Duration(seconds: 30),
        status:
            index < 5 ? GoldenGateStatus.passed : GoldenGateStatus.pending,
        detail: '',
      ),
    ),
  );
}
