import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:pocketgallery_phone_pilot/experiments/retrieval_strategy.dart';
import 'package:pocketgallery_phone_pilot/lineage/import_lineage.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_ids.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_models.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_store.dart';
import 'package:pocketgallery_phone_pilot/ui/microscope/experiment_run_detail_page.dart';

CandidateRecord _candidate({
  required String strategyId,
  required RetrievalLane lane,
  required String chunkId,
  required int rank,
  required bool selected,
}) =>
    CandidateRecord(
      candidateId: LineageIds.candidateId('tr-detail', strategyId, chunkId),
      traceId: 'tr-detail',
      strategyId: strategyId,
      lane: lane,
      chunkId: chunkId,
      embeddingId: 'emb-$chunkId',
      sourceChannels: lane == RetrievalLane.active
          ? 'fts5,embedding'
          : 'embedding:heading,parent-child',
      ftsRank: lane == RetrievalLane.active ? rank : null,
      rawBm25: lane == RetrievalLane.active ? -rank.toDouble() : null,
      vectorRank: rank,
      rawCosine: 1 - rank / 10,
      fusionRank: rank,
      fusionScore: 1 - rank / 20,
      rerankRank: lane == RetrievalLane.shadow ? rank : null,
      rerankScore: lane == RetrievalLane.shadow ? 1 - rank / 30 : null,
      finalRank: rank,
      selectedForEvidence: selected,
      dropReason: selected ? null : 'not_selected',
    );

void main() {
  testWidgets('experiment detail compares lanes and drills into filtered rows',
      (tester) async {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    final store = LineageStore(database: db);
    await store.initialize();
    const active = 'active.r45-body-hybrid';
    final shadow = RetrievalStrategies.featureReranker.id;
    await store.putTrace(LineageTrace(
      traceId: 'tr-detail',
      sessionId: 's1',
      turnId: 't1',
      queryText: '比较 ACTIVE 和 SHADOW',
      requestedMode: 'auto',
      finalMode: 'knowledge',
      scopeJson: '{"type":"all"}',
      activeStrategyId: active,
      startedAt: DateTime.utc(2026, 8, 31),
      completedAt: DateTime.utc(2026, 8, 31, 0, 0, 1),
      status: TraceStatus.complete,
      failureStage: null,
      failureCode: null,
    ));
    for (final chunkId in <String>['c-active', 'c-shared', 'c-shadow']) {
      await store.upsertLineageChunk(
        chunkId: chunkId,
        documentId: 'd1',
        sectionId: null,
        locator: chunkId,
        ordinal: 0,
        startOffset: null,
        endOffset: null,
        charCount: 20,
        tokenCount: 10,
        overlapFromPrevious: 0,
        chunkStrategy: 'test',
        boundaryReason: null,
        provenanceQuality: ProvenanceQuality.exact.name,
      );
    }
    final activeOnly = _candidate(
      strategyId: active,
      lane: RetrievalLane.active,
      chunkId: 'c-active',
      rank: 1,
      selected: true,
    );
    final activeShared = _candidate(
      strategyId: active,
      lane: RetrievalLane.active,
      chunkId: 'c-shared',
      rank: 2,
      selected: false,
    );
    final shadowShared = _candidate(
      strategyId: shadow,
      lane: RetrievalLane.shadow,
      chunkId: 'c-shared',
      rank: 1,
      selected: false,
    );
    final shadowOnly = _candidate(
      strategyId: shadow,
      lane: RetrievalLane.shadow,
      chunkId: 'c-shadow',
      rank: 2,
      selected: true,
    );
    for (final candidate in <CandidateRecord>[
      activeOnly,
      activeShared,
      shadowShared,
      shadowOnly,
    ]) {
      await store.putCandidate(candidate);
    }
    await store.putEvidence(EvidenceRecord(
      evidenceId: LineageIds.evidenceId('tr-detail', active, 'c-active'),
      traceId: 'tr-detail',
      strategyId: active,
      lane: RetrievalLane.active,
      anchor: 'E1',
      candidateId: activeOnly.candidateId,
      chunkId: 'c-active',
      selectionRank: 1,
      score: 0.9,
      tokenCount: 10,
      selectionReason: 'active',
    ));
    await store.putEvidence(EvidenceRecord(
      evidenceId: LineageIds.evidenceId('tr-detail', shadow, 'c-shadow'),
      traceId: 'tr-detail',
      strategyId: shadow,
      lane: RetrievalLane.shadow,
      anchor: null,
      candidateId: shadowOnly.candidateId,
      chunkId: 'c-shadow',
      selectionRank: 1,
      score: 0.8,
      tokenCount: 10,
      selectionReason: 'shadow',
    ));
    await store.putRerankFeature(RerankFeatureRecord(
      featureId: LineageIds.rerankFeatureId('tr-detail', shadow, 'c-shadow'),
      traceId: 'tr-detail',
      strategyId: shadow,
      lane: RetrievalLane.shadow,
      candidateId: shadowOnly.candidateId,
      chunkId: 'c-shadow',
      normalizedLexicalAffinity: 0,
      cosine: 0.8,
      dualChannelAgreement: 0,
      queryWindowCoverage: 1,
      headingMatch: 1,
      exactTermMatch: 1,
      sourceDiversity: 1,
      rerankScore: 0.75,
      contributionJson: '{"cosine":0.24,"heading_match":0.1}',
    ));
    await store.putExperimentRun(ExperimentRunRecord(
      experimentRunId: 'run-detail',
      traceId: 'tr-detail',
      strategyId: shadow,
      lane: RetrievalLane.shadow,
      status: ExperimentRunStatus.failed,
      startedAt: DateTime.utc(2026, 8, 31),
      completedAt: DateTime.utc(2026, 8, 31, 0, 0, 2),
      completedItems: 2,
      totalItems: 3,
      metricJson: '{"candidateCount":2,"evidenceCount":1}',
      failureCode: 'SHADOW_EXECUTION_FAILED',
      failureDetail: 'failure after persisted candidates',
    ));

    await tester.pumpWidget(MaterialApp(
      home: ExperimentRunDetailPage(
        store: store,
        traceId: 'tr-detail',
        strategyId: shadow,
        experimentRunId: 'run-detail',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('SHADOW FAILED'), findsOneWidget);
    expect(find.textContaining('failure after persisted candidates'), findsOneWidget);
    expect(find.textContaining('added 1'), findsOneWidget);
    expect(find.textContaining('removed 1'), findsOneWidget);
    expect(find.textContaining('rank changed 1'), findsOneWidget);
    expect(find.textContaining('Evidence changed'), findsOneWidget);
    expect(find.textContaining('cosine'), findsOneWidget);
    expect(find.textContaining('heading_match'), findsOneWidget);

    final candidatesButton =
        find.byKey(const ValueKey<String>('experiment-candidates'));
    await tester.ensureVisible(candidatesButton);
    await tester.tap(candidatesButton);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('candidate-pool-page')), findsOneWidget);
    expect(find.text('c-shadow'), findsOneWidget);
    expect(find.text('c-active'), findsNothing);
  });
}
