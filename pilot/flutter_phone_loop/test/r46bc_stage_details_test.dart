import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:pocketgallery_phone_pilot/lineage/import_lineage.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_ids.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_models.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_store.dart';
import 'package:pocketgallery_phone_pilot/lineage/trace_snapshot.dart';
import 'package:pocketgallery_phone_pilot/services/knowledge_engine.dart';
import 'package:pocketgallery_phone_pilot/ui/microscope/candidate_pool_page.dart';
import 'package:pocketgallery_phone_pilot/ui/microscope/embedding_microscope_page.dart';
import 'package:pocketgallery_phone_pilot/ui/microscope/evidence_context_page.dart';
import 'package:pocketgallery_phone_pilot/ui/microscope/generation_citation_page.dart';
import 'package:pocketgallery_phone_pilot/ui/microscope/rank_trajectory_page.dart';
import 'package:pocketgallery_phone_pilot/ui/microscope/router_decision_page.dart';

Future<({TraceSnapshot snapshot, KnowledgeEngine engine})> _fixture(
  Database db,
) async {
  final store = LineageStore(database: db);
  await store.initialize();
  const traceId = 'tr-details';
  const strategy = 'active.r45-body-hybrid';
  await store.putTrace(LineageTrace(
    traceId: traceId,
    sessionId: 's1',
    turnId: 't1',
    queryText: '为什么选择这个证据',
    requestedMode: 'auto',
    finalMode: 'knowledge',
    scopeJson: '{"type":"all"}',
    activeStrategyId: strategy,
    startedAt: DateTime.utc(2026, 8, 31),
    completedAt: DateTime.utc(2026, 8, 31, 0, 0, 2),
    status: TraceStatus.complete,
    failureStage: null,
    failureCode: null,
  ));
  await store.upsertLineageDocument(
    documentId: 'd1',
    sourceName: 'doc.pdf',
    sha256: 'sha-d1',
    fileType: 'pdf',
    sizeBytes: 1000,
    pageCount: 3,
    parseStatus: ParseStatus.parsed.dbValue,
    parseErrorCode: null,
    parseErrorDetail: null,
    extractedCharCount: 600,
    emptyPageCount: 0,
    provenanceQuality: ProvenanceQuality.exact.name,
    importedAt: DateTime.utc(2026, 8, 30),
  );
  await store.upsertLineageSection(
    sectionId: 'sec-2',
    documentId: 'd1',
    pageNo: 2,
    heading: '验证',
    sectionType: 'heading',
    startOffset: 100,
    endOffset: 300,
    charCount: 200,
    parseStatus: ParseStatus.parsed.dbValue,
  );
  await store.upsertLineageChunk(
    chunkId: 'c1',
    documentId: 'd1',
    sectionId: 'sec-2',
    locator: 'p2',
    ordinal: 0,
    startOffset: 120,
    endOffset: 220,
    charCount: 100,
    tokenCount: 55,
    overlapFromPrevious: 0,
    chunkStrategy: 'fixed-char-v1',
    boundaryReason: 'section-boundary',
    provenanceQuality: ProvenanceQuality.exact.name,
  );
  await store.putEmbedding(LineageEmbedding.test(
    embeddingId: LineageIds.queryEmbeddingId(traceId),
    sourceKind: 'query',
    sourceId: traceId,
    chunkId: null,
    representation: EmbeddingRepresentation.query,
    vector: const <double>[1, 0],
    modelIdentity: 'EmbeddingGemma-test',
    taskMode: 'retrieval_query',
  ));
  await store.putEmbedding(LineageEmbedding.test(
    embeddingId: 'emb-c1',
    sourceKind: 'chunk',
    sourceId: 'c1',
    documentId: 'd1',
    chunkId: 'c1',
    representation: EmbeddingRepresentation.body,
    vector: const <double>[0.9, 0.1],
    modelIdentity: 'EmbeddingGemma-test',
    taskMode: 'retrieval_document',
  ));
  final selectedCandidate = CandidateRecord(
    candidateId: LineageIds.candidateId(traceId, strategy, 'c1'),
    traceId: traceId,
    strategyId: strategy,
    lane: RetrievalLane.active,
    chunkId: 'c1',
    embeddingId: 'emb-c1',
    sourceChannels: 'fts5+vector',
    ftsRank: 2,
    rawBm25: -3.2,
    vectorRank: 1,
    rawCosine: 0.81,
    fusionRank: 1,
    fusionScore: 0.04,
    rerankRank: null,
    rerankScore: null,
    finalRank: 1,
    selectedForEvidence: true,
    dropReason: null,
  );
  await store.putCandidate(selectedCandidate);
  await store.putCandidate(CandidateRecord(
    candidateId: LineageIds.candidateId(traceId, strategy, 'c2'),
    traceId: traceId,
    strategyId: strategy,
    lane: RetrievalLane.active,
    chunkId: 'c2',
    embeddingId: null,
    sourceChannels: 'fts5',
    ftsRank: 8,
    rawBm25: -1.2,
    vectorRank: null,
    rawCosine: null,
    fusionRank: 6,
    fusionScore: 0.01,
    rerankRank: null,
    rerankScore: null,
    finalRank: 6,
    selectedForEvidence: false,
    dropReason: 'max_evidence',
  ));
  await store.putRouterDecision(const RouterDecisionRecord(
    decisionId: 'route-1',
    traceId: traceId,
    strategyId: strategy,
    lane: RetrievalLane.active,
    ftsHitCount: 2,
    top1Cosine: 0.81,
    top2Cosine: 0.62,
    top1Top2Gap: 0.19,
    dualChannel: true,
    lexicalGatePass: true,
    semanticStrengthGatePass: true,
    semanticGapGatePass: true,
    finalUseKnowledge: true,
    ruleProfile: 'r45-auto',
    decisionReason: 'lexical_hit',
  ));
  final evidenceId = LineageIds.evidenceId(traceId, strategy, 'c1');
  await store.putEvidence(EvidenceRecord(
    evidenceId: evidenceId,
    traceId: traceId,
    strategyId: strategy,
    lane: RetrievalLane.active,
    anchor: 'E1',
    candidateId: selectedCandidate.candidateId,
    chunkId: 'c1',
    selectionRank: 1,
    score: 0.04,
    tokenCount: 91,
    selectionReason: 'context_token_allocation',
  ));
  await store.putPromptBudget(const PromptBudgetRecord(
    traceId: traceId,
    strategyId: strategy,
    lane: RetrievalLane.active,
    modelContextLimit: 8192,
    systemTokens: 320,
    historyTokens: 1000,
    evidenceTokens: 91,
    queryTokens: 40,
    outputReserveTokens: 700,
    totalPrefillTokens: 1451,
    remainingTokens: 6041,
    trimmedHistoryMessages: 1,
    trimmedEvidenceItems: 1,
    trimDetailJson: '["history_messages:1","evidence_budget:1"]',
  ));
  await store.putGenerationStats(const GenerationStatsRecord(
    traceId: traceId,
    strategyId: strategy,
    lane: RetrievalLane.active,
    ttftMs: null,
    generationMs: 1200,
    outputTokens: null,
    decodeTokensPerSecond: null,
    backend: null,
    nativeSessionRebuilt: true,
    sessionResetReason: 'fresh_turn_context_bound',
  ));
  await store.putCitation(CitationRecord(
    citationId: 'citation-1',
    traceId: traceId,
    anchor: 'E1',
    evidenceId: evidenceId,
    chunkId: 'c1',
    documentId: 'd1',
    sectionId: 'sec-2',
    pageNo: 2,
    citationStatus: 'resolved',
  ));
  return (
    snapshot: await TraceSnapshot.load(store, traceId),
    engine: KnowledgeEngine(lineageStore: store),
  );
}

void main() {
  testWidgets('decision pages expose captured ranks router budget and citation',
      (tester) async {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    final data = await _fixture(db);

    Future<void> pump(Widget page) async {
      await tester.pumpWidget(MaterialApp(home: page));
      await tester.pumpAndSettle();
    }

    await pump(CandidatePoolPage(snapshot: data.snapshot));
    expect(find.textContaining('dual-channel 1'), findsOneWidget);
    expect(find.textContaining('dropped 1'), findsOneWidget);
    expect(find.textContaining('max_evidence'), findsOneWidget);

    await pump(RankTrajectoryPage(snapshot: data.snapshot));
    expect(find.textContaining('FTS #2'), findsOneWidget);
    expect(find.textContaining('Fusion #1'), findsOneWidget);
    expect(find.textContaining('Evidence E1'), findsOneWidget);
    expect(find.textContaining('重排未运行'), findsOneWidget);

    await pump(RouterDecisionPage(snapshot: data.snapshot));
    expect(find.text('Auto → Knowledge'), findsOneWidget);
    expect(find.textContaining('lexical_hit'), findsOneWidget);
    expect(find.text('PASS'), findsWidgets);

    await pump(EvidenceContextPage(snapshot: data.snapshot));
    expect(find.textContaining('E1'), findsWidgets);
    expect(find.textContaining('91 tokens'), findsWidgets);
    expect(find.textContaining('Output Reserve'), findsOneWidget);
    expect(find.textContaining('700'), findsWidgets);
    expect(find.textContaining('trimmed evidence 1'), findsOneWidget);

    await pump(GenerationCitationPage(snapshot: data.snapshot));
    expect(find.textContaining('generation 1200 ms'), findsOneWidget);
    expect(find.textContaining('TTFT 未捕获'), findsOneWidget);
    expect(find.textContaining('Citation → Evidence → Chunk'), findsOneWidget);
    expect(find.textContaining('第 2 页'), findsOneWidget);
    expect(find.textContaining('doc.pdf'), findsOneWidget);

    await pump(EmbeddingMicroscopePage(
      engine: data.engine,
      snapshot: data.snapshot,
    ));
    expect(find.textContaining('Chunk → Embedding'), findsWidgets);
    expect(find.textContaining('emb-c1'), findsOneWidget);
  });
}
