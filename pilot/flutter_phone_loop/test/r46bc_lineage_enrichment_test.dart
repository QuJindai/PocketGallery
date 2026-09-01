import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:pocketgallery_phone_pilot/chat/context_budgeter.dart';
import 'package:pocketgallery_phone_pilot/core/models.dart';
import 'package:pocketgallery_phone_pilot/lineage/import_lineage.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_ids.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_models.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_store.dart';

Future<LineageStore> _storeWithTrace(Database db) async {
  final store = LineageStore(database: db);
  await store.initialize();
  await store.putTrace(
    LineageTrace(
      traceId: 'tr-enrichment',
      sessionId: 'session-1',
      turnId: 'turn-1',
      queryText: '端侧检索如何验证',
      requestedMode: 'auto',
      finalMode: 'knowledge',
      scopeJson: '{"type":"all"}',
      activeStrategyId: 'active.r45-body-hybrid',
      startedAt: DateTime.utc(2026, 8, 31, 7),
      completedAt: DateTime.utc(2026, 8, 31, 7, 0, 1),
      status: TraceStatus.complete,
      failureStage: null,
      failureCode: null,
    ),
  );
  return store;
}

CandidateRecord _candidate({
  required String strategyId,
  required RetrievalLane lane,
  required String chunkId,
}) => CandidateRecord(
  candidateId: LineageIds.candidateId('tr-enrichment', strategyId, chunkId),
  traceId: 'tr-enrichment',
  strategyId: strategyId,
  lane: lane,
  chunkId: chunkId,
  embeddingId: 'emb-$chunkId',
  sourceChannels: 'vector',
  ftsRank: null,
  rawBm25: null,
  vectorRank: 1,
  rawCosine: 0.8,
  fusionRank: 1,
  fusionScore: 0.04,
  rerankRank: null,
  rerankScore: null,
  finalRank: 1,
  selectedForEvidence: true,
  dropReason: null,
);

void main() {
  test(
    'lineage source records resolve directly by chunk and section id',
    () async {
      final db = sqlite3.openInMemory();
      addTearDown(db.close);
      final store = await _storeWithTrace(db);

      await store.upsertLineageDocument(
        documentId: 'doc-1',
        sourceName: 'test.pdf',
        sha256: 'sha-doc-1',
        fileType: 'pdf',
        sizeBytes: 1024,
        pageCount: 3,
        parseStatus: ParseStatus.parsed.dbValue,
        parseErrorCode: null,
        parseErrorDetail: null,
        extractedCharCount: 900,
        emptyPageCount: 0,
        provenanceQuality: ProvenanceQuality.exact.name,
        importedAt: DateTime.utc(2026, 8, 31),
      );
      await store.upsertLineageSection(
        sectionId: 'section-2',
        documentId: 'doc-1',
        pageNo: 2,
        heading: '检索测试',
        sectionType: 'heading',
        startOffset: 100,
        endOffset: 300,
        charCount: 200,
        parseStatus: ParseStatus.parsed.dbValue,
      );
      await store.upsertLineageChunk(
        chunkId: 'chunk-2',
        documentId: 'doc-1',
        sectionId: 'section-2',
        locator: 'p2',
        ordinal: 1,
        startOffset: 120,
        endOffset: 220,
        charCount: 100,
        tokenCount: 55,
        overlapFromPrevious: 20,
        chunkStrategy: 'fixed-char-v1',
        boundaryReason: 'section-boundary',
        provenanceQuality: ProvenanceQuality.exact.name,
      );

      final chunk = await store.lineageChunkById('chunk-2');
      final section = await store.lineageSectionById('section-2');

      expect(chunk!.sectionId, 'section-2');
      expect(section!.pageNo, 2);
      expect(section.heading, '检索测试');
    },
  );

  test(
    'candidate and evidence reads are isolated by strategy and lane',
    () async {
      final db = sqlite3.openInMemory();
      addTearDown(db.close);
      final store = await _storeWithTrace(db);
      const activeStrategy = 'active.r45-body-hybrid';
      const shadowStrategy = 'shadow.heading-body-multivector';
      final active = _candidate(
        strategyId: activeStrategy,
        lane: RetrievalLane.active,
        chunkId: 'chunk-active',
      );
      final shadow = _candidate(
        strategyId: shadowStrategy,
        lane: RetrievalLane.shadow,
        chunkId: 'chunk-shadow',
      );
      await store.putCandidate(active);
      await store.putCandidate(shadow);
      await store.putEvidence(
        EvidenceRecord(
          evidenceId: LineageIds.evidenceId(
            'tr-enrichment',
            activeStrategy,
            active.chunkId,
          ),
          traceId: 'tr-enrichment',
          strategyId: activeStrategy,
          lane: RetrievalLane.active,
          anchor: 'E1',
          candidateId: active.candidateId,
          chunkId: active.chunkId,
          selectionRank: 1,
          score: 0.04,
          tokenCount: 72,
          selectionReason: 'active evidence',
        ),
      );
      await store.putEvidence(
        EvidenceRecord(
          evidenceId: LineageIds.evidenceId(
            'tr-enrichment',
            shadowStrategy,
            shadow.chunkId,
          ),
          traceId: 'tr-enrichment',
          strategyId: shadowStrategy,
          lane: RetrievalLane.shadow,
          anchor: null,
          candidateId: shadow.candidateId,
          chunkId: shadow.chunkId,
          selectionRank: 1,
          score: 0.05,
          tokenCount: 68,
          selectionReason: 'shadow evidence',
        ),
      );

      final activeCandidates = await store.candidatesForTrace(
        'tr-enrichment',
        strategyId: activeStrategy,
        lane: RetrievalLane.active,
      );
      final shadowEvidence = await store.evidenceForTrace(
        'tr-enrichment',
        strategyId: shadowStrategy,
        lane: RetrievalLane.shadow,
      );

      expect(activeCandidates.map((item) => item.chunkId), ['chunk-active']);
      expect(shadowEvidence.map((item) => item.chunkId), ['chunk-shadow']);
    },
  );

  test(
    'experiment run progress and result survive a store round trip',
    () async {
      final db = sqlite3.openInMemory();
      addTearDown(db.close);
      final store = await _storeWithTrace(db);
      final started = DateTime.utc(2026, 8, 31, 7, 1);
      const run = ExperimentRunRecord(
        experimentRunId: 'run-1',
        traceId: 'tr-enrichment',
        strategyId: 'shadow.heading-body-multivector',
        lane: RetrievalLane.shadow,
        status: ExperimentRunStatus.running,
        startedAt: null,
        completedAt: null,
        completedItems: 2,
        totalItems: 5,
        metricJson: null,
        failureCode: null,
      );

      await store.putExperimentRun(run.copyWith(startedAt: started));
      final restored = await store.experimentRunById('run-1');

      expect(restored!.status, ExperimentRunStatus.running);
      expect(restored.completedItems, 2);
      expect(restored.totalItems, 5);
      expect(restored.startedAt, started);
    },
  );

  test('context selection exposes real token allocation for each evidence', () {
    const budgeter = ContextBudgeter();
    final selection = budgeter.composeEvidenceContextWithDecision(
      const <EvidenceItem>[
        EvidenceItem(
          anchor: 'E1',
          chunk: PgChunk(
            id: 'c1',
            documentId: 'd1',
            sourceName: 'a.md',
            locator: 's1',
            ordinal: 0,
            text: '第一条真实证据内容。',
          ),
          score: 0.9,
        ),
        EvidenceItem(
          anchor: 'E2',
          chunk: PgChunk(
            id: 'c2',
            documentId: 'd2',
            sourceName: 'b.md',
            locator: 's2',
            ordinal: 0,
            text: '第二条真实证据内容。',
          ),
          score: 0.8,
        ),
      ],
      maxTokens: 300,
      maxItems: 2,
    );

    expect(selection.tokenCountsByAnchor.keys, containsAll(['E1', 'E2']));
    expect(selection.tokenCountsByAnchor['E1'], greaterThan(0));
    expect(selection.tokenCountsByAnchor['E2'], greaterThan(0));
    expect(
      selection.tokenCountsByAnchor.values.reduce((a, b) => a + b),
      lessThanOrEqualTo(budgeter.estimateTokens(selection.context)),
    );
  });
}
