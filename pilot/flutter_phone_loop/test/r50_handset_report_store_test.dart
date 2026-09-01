import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pocketgallery_phone_pilot/acceptance/handset_acceptance_models.dart';
import 'package:pocketgallery_phone_pilot/acceptance/handset_acceptance_store.dart';
import 'package:pocketgallery_phone_pilot/acceptance/preservation_probe.dart';
import 'package:pocketgallery_phone_pilot/services/hf_oauth_device_service.dart';

void main() {
  test('checkpoint and private baseline survive interrupted atomic swaps', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pocketgallery-r50-report-store-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = HandsetAcceptanceStore(
      directoryProvider: () async => directory,
    );

    final generations = <HandsetAcceptanceSnapshot>[
      _checkpoint(
        phase: HandsetRunPhase.preparing,
        gateStatus: HandsetGateStatus.pending,
      ),
      _checkpoint(
        phase: HandsetRunPhase.runningAutomated,
        gateStatus: HandsetGateStatus.running,
      ),
      _checkpoint(
        phase: HandsetRunPhase.completed,
        gateStatus: HandsetGateStatus.passed,
      ),
    ];

    File? checkpointFile;
    for (final generation in generations) {
      checkpointFile = await store.saveCheckpoint(generation);
      final decoded = jsonDecode(await checkpointFile.readAsString()) as Map;
      expect(decoded['runId'], generation.runId);
      expect(decoded['phase'], generation.phase.name);
      expect((await store.readLast())!.phase, generation.phase);
      expect(File('${checkpointFile.path}.tmp').existsSync(), isFalse);
    }
    final lastCheckpointFile = checkpointFile!;
    expect(
      p.basename(lastCheckpointFile.path),
      'PG_HANDSET_ACCEPTANCE_LAST.json',
    );
    await lastCheckpointFile.copy('${lastCheckpointFile.path}.bak');
    await lastCheckpointFile.writeAsString('{corrupt-primary');
    expect((await store.readLast())!.phase, HandsetRunPhase.completed);

    final baseline = _baseline();
    final baselineFile = await store.saveBaseline(baseline);
    expect(p.basename(baselineFile.path), 'PG_HANDSET_BASELINE.json');
    expect((await store.readBaseline())!.toJson(), baseline.toJson());
    await baselineFile.copy('${baselineFile.path}.bak');
    await baselineFile.writeAsString('{corrupt-primary');
    expect((await store.readBaseline())!.toJson(), baseline.toJson());

    final reportBytes = Uint8List.fromList(
      utf8.encode(
        '{"schema":"pocketgallery.r50.handset-acceptance.v1",'
        '"schemaVersion":1}',
      ),
    );
    final reportFile = await store.saveFinalReport(
      reportBytes,
      'r50 unsafe/id',
    );
    expect(
      p.basename(reportFile.path),
      'PG_HANDSET_ACCEPTANCE_r50_unsafe_id.json',
    );
    expect(await reportFile.readAsBytes(), reportBytes);
    expect(File('${reportFile.path}.tmp').existsSync(), isFalse);
  });
}

HandsetAcceptanceSnapshot _checkpoint({
  required HandsetRunPhase phase,
  required HandsetGateStatus gateStatus,
}) {
  final startedAt = DateTime.utc(2026, 9, 1);
  return HandsetAcceptanceSnapshot(
    runId: 'r50-atomic',
    phase: phase,
    startedAt: startedAt,
    updatedAt: startedAt.add(const Duration(seconds: 1)),
    gates: <HandsetGateSnapshot>[
      HandsetGateSnapshot(
        name: 'H1_TARGET_DEVICE',
        label: 'Target device',
        status: gateStatus,
        detail: '',
        evidence: const <AcceptanceEvidence>[],
        startedAt: gateStatus == HandsetGateStatus.pending ? null : startedAt,
        finishedAt: gateStatus.isTerminal
            ? startedAt.add(const Duration(seconds: 1))
            : null,
      ),
    ],
  );
}

PreservationSnapshot _baseline() {
  return PreservationSnapshot(
    versionCode: 2022,
    packageName: 'com.qujindai.pocketgallery_phone_pilot.r3',
    signerSha256:
        '81af4a5ef94c236774f0e193b2a4b248805b36c14cc36e2a56df8e451a712541',
    hasActiveModel: true,
    hasActiveEmbedder: true,
    oauthAccessPresent: true,
    oauthRefreshPresent: true,
    oauthExpiry: HfTokenExpiryState.valid,
    knowledgeStates: const <String, String>{},
    chatStates: const <String, String>{},
    chatMessageCounts: const <String, int>{},
    vectorStates: const <String, String>{},
    lineageStates: const <String, String>{},
  );
}
