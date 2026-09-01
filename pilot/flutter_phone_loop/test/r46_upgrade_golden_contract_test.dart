import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:pocketgallery_phone_pilot/lineage/lineage_ids.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_models.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_store.dart';
import 'package:pocketgallery_phone_pilot/lineage/runtime_lineage_recorder.dart';
import 'package:pocketgallery_phone_pilot/services/golden_test_runner.dart';

import 'support/release_version.dart';

void main() {
  test('integrated R4.6/R4.7 release advances identity and CI guards',
      () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    final phoneWorkflow = await File(
      '../../.github/workflows/pocketgallery-phone-pilot-apk.yml',
    ).readAsString();
    final r46Workflow = await File(
      '../../.github/workflows/pocketgallery-r46-tdd.yml',
    ).readAsString();
    final setup =
        await File('lib/services/model_setup_service.dart').readAsString();
    final bootstrap = await File('scripts/bootstrap_android.sh').readAsString();

    final version = parseReleaseVersion(pubspec);
    expect(
      isReleaseVersionAtLeast(version, major: 0, minor: 4, patch: 17),
      isTrue,
    );
    expect(version.build, greaterThanOrEqualTo(18));
    expect(phoneWorkflow,
        contains('feature/phone-pilot-r46-runtime-lineage'));
    expect(phoneWorkflow, contains(r'test "$VERSION_CODE" -ge 2020'));
    expect(phoneWorkflow, contains(
      '81af4a5ef94c236774f0e193b2a4b248805b36c14cc36e2a56df8e451a712541',
    ));
    expect(phoneWorkflow,
        contains('android-arm64 --split-per-abi'));
    expect(
      r46Workflow,
      contains(RegExp(r'^\s*run:\s*flutter test\s*$', multiLine: true)),
      reason: 'the final R4.6 workflow must run the entire Flutter suite',
    );
    expect(bootstrap,
        contains('com.qujindai.pocketgallery_phone_pilot.r3'));
    expect(setup, contains('if (!FlutterGemma.hasActiveModel())'));
    expect(setup, contains('if (!FlutterGemma.hasActiveEmbedder())'));
  });

  test('Phone Golden F8-F10 verify persisted runtime facts', () async {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    final store = LineageStore(database: db);
    const traceId = 'golden-lineage-trace';
    const strategy = RuntimeLineageRecorder.activeStrategyId;
    await store.putTrace(LineageTrace(
      traceId: traceId,
      sessionId: 'golden-session',
      turnId: 'golden-turn',
      queryText: '真实查询向量是否被使用',
      requestedMode: 'knowledge',
      finalMode: 'knowledge:hybrid',
      scopeJson: '{"type":"all"}',
      activeStrategyId: strategy,
      startedAt: DateTime.utc(2026, 8, 29),
      completedAt: DateTime.utc(2026, 8, 29, 0, 0, 1),
      status: TraceStatus.complete,
      failureStage: null,
      failureCode: null,
    ));
    final queryId = LineageIds.queryEmbeddingId(traceId);
    final queryEmbedding = LineageEmbedding.test(
      embeddingId: queryId,
      sourceKind: 'query',
      sourceId: traceId,
      chunkId: null,
      representation: EmbeddingRepresentation.query,
      vector: const <double>[0.25, 0.75],
      modelIdentity: 'EmbeddingGemma-test',
      taskMode: 'retrieval_query',
    );
    await store.putEmbedding(queryEmbedding);

    const requiredKinds = <String>[
      'trace.started',
      'fts.search_completed',
      'embedding.query_completed',
      'vector.search_completed',
      'fusion.completed',
      'candidate.pool_built',
      'router.evaluated',
      'evidence.selected',
      'context.budgeted',
      'generation.completed',
      'citation.resolved',
      'trace.completed',
    ];
    for (var index = 0; index < requiredKinds.length; index++) {
      final kind = requiredKinds[index];
      final payload = switch (kind) {
        'embedding.query_completed' => <String, Object?>{
            'embeddingId': queryId,
            'modelIdentity': queryEmbedding.modelIdentity,
            'dimension': queryEmbedding.dimension,
            'vectorSha256': queryEmbedding.vectorSha256,
          },
        'vector.search_completed' => <String, Object?>{
            'queryEmbeddingId': queryId,
            'hitCount': 1,
          },
        _ => const <String, Object?>{},
      };
      await store.appendEvent(TraceEventRecord(
        eventId: 'golden-event-$index',
        traceId: traceId,
        seq: index + 1,
        stage: kind.split('.').first,
        kind: kind,
        truthKind:
            kind == 'fusion.completed' || kind == 'context.budgeted'
                ? TruthKind.derived
                : TruthKind.real,
        lane: RetrievalLane.active,
        strategyId: strategy,
        timestampUs: index + 1,
        durationUs: null,
        payloadJson: jsonEncode(payload),
      ));
    }
    await store.putPromptBudget(const PromptBudgetRecord(
      traceId: traceId,
      strategyId: strategy,
      lane: RetrievalLane.active,
      modelContextLimit: 8192,
      systemTokens: 100,
      historyTokens: 200,
      evidenceTokens: 300,
      queryTokens: 50,
      outputReserveTokens: 700,
      totalPrefillTokens: 650,
      remainingTokens: 6842,
      trimmedHistoryMessages: 0,
      trimmedEvidenceItems: 0,
      trimDetailJson: '[]',
    ));

    final gates = await const GoldenLineageVerifier().verify(store, traceId);
    expect(gates.map((gate) => gate.name), <String>[
      'F8_RUNTIME_LINEAGE',
      'F9_QUERY_VECTOR_IDENTITY',
      'F10_CONTEXT_BUDGET',
    ]);
    expect(gates.every((gate) => gate.passed), isTrue);

    final missing = await const GoldenLineageVerifier().verify(store, null);
    expect(missing.every((gate) => !gate.passed), isTrue);
    expect(missing.map((gate) => gate.name), gates.map((gate) => gate.name));
  });

  test('F8-F10 stay wired after F7 and F11 is not a placeholder pass',
      () async {
    final golden =
        await File('lib/services/golden_test_runner.dart').readAsString();
    final f7 = golden.indexOf("name: 'F7_CHAT_REALWORLD'");
    final f8 = golden.indexOf("name: 'F8_RUNTIME_LINEAGE'");
    final f9 = golden.indexOf("name: 'F9_QUERY_VECTOR_IDENTITY'");
    final f10 = golden.indexOf("name: 'F10_CONTEXT_BUDGET'");

    expect(f7, greaterThanOrEqualTo(0));
    expect(f8, greaterThan(f7));
    expect(f9, greaterThan(f8));
    expect(f10, greaterThan(f9));
    expect(golden, contains('lineageRecorder: engine.runtimeLineageRecorder'));
    expect(golden, contains('lineageTraceId = reply.traceId'));
    expect(golden, isNot(contains("GateResult('F11_CITATION_LINEAGE', true")));
  });
}
