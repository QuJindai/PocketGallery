import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:pocketgallery_phone_pilot/core/models.dart';
import 'package:pocketgallery_phone_pilot/experiments/representation_builder.dart';
import 'package:pocketgallery_phone_pilot/experiments/retrieval_strategy.dart';
import 'package:pocketgallery_phone_pilot/lineage/import_lineage.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_ids.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_models.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_store.dart';
import 'package:pocketgallery_phone_pilot/okf/okf_experiment_engine.dart';
import 'package:pocketgallery_phone_pilot/okf/okf_parser.dart';
import 'package:pocketgallery_phone_pilot/okf/okf_signal_policy.dart';
import 'package:pocketgallery_phone_pilot/okf/okf_store.dart';
import 'package:pocketgallery_phone_pilot/retrieval/query_embedding_runtime.dart';
import 'package:pocketgallery_phone_pilot/services/lexical_fts_store.dart';

class _Generator implements EmbeddingGenerator {
  @override
  Future<List<double>> generateDocument(String text) async => const <double>[
    1,
    0,
  ];

  @override
  Future<List<double>> generateQuery(String text) async {
    throw StateError('OKF SHADOW must reuse the captured query embedding');
  }
}

Future<({LineageStore lineage, LexicalFtsStore lexical, OkfStore okf})>
_fixture() async {
  final lineageDb = sqlite3.openInMemory();
  final lexicalDb = sqlite3.openInMemory();
  final okfDb = sqlite3.openInMemory();
  addTearDown(lineageDb.close);
  addTearDown(lexicalDb.close);
  addTearDown(okfDb.close);

  final lineage = LineageStore(database: lineageDb);
  final lexical = LexicalFtsStore(database: lexicalDb);
  final okf = OkfStore(database: okfDb);
  await lineage.initialize();
  await lexical.initialize();
  await okf.initialize();

  const verified = PgChunk(
    id: 'c-verified',
    documentId: 'd-verified',
    sourceName: 'verified.md',
    locator: 'heading 1: Torque',
    ordinal: 0,
    text: 'Torque limit validation evidence for the motor controller.',
  );
  const stale = PgChunk(
    id: 'c-stale',
    documentId: 'd-stale',
    sourceName: 'stale.md',
    locator: 'heading 1: Torque',
    ordinal: 0,
    text: 'Torque limit validation evidence from an older policy.',
  );
  await lexical.replaceDocument(
    const ImportedDocument(
      documentId: 'd-verified',
      sourceName: 'verified.md',
      sha256: 'sha-verified',
      chunks: <PgChunk>[verified],
    ),
  );
  await lexical.replaceDocument(
    const ImportedDocument(
      documentId: 'd-stale',
      sourceName: 'stale.md',
      sha256: 'sha-stale',
      chunks: <PgChunk>[stale],
    ),
  );

  for (final chunk in const <PgChunk>[verified, stale]) {
    await lineage.upsertLineageSection(
      sectionId: 'sec-${chunk.id}',
      documentId: chunk.documentId,
      pageNo: null,
      heading: 'Torque',
      sectionType: 'heading',
      startOffset: 0,
      endOffset: chunk.text.length,
      charCount: chunk.text.length,
      parseStatus: ParseStatus.parsed.dbValue,
    );
    await lineage.upsertLineageChunk(
      chunkId: chunk.id,
      documentId: chunk.documentId,
      sectionId: 'sec-${chunk.id}',
      locator: chunk.locator,
      ordinal: 0,
      startOffset: 0,
      endOffset: chunk.text.length,
      charCount: chunk.text.length,
      tokenCount: 18,
      overlapFromPrevious: 0,
      chunkStrategy: 'test',
      boundaryReason: 'section_end',
      provenanceQuality: ProvenanceQuality.exact.name,
    );
  }

  await lineage.putTrace(
    LineageTrace(
      traceId: 'tr-okf',
      sessionId: 's1',
      turnId: 't1',
      queryText: 'torque limit validation',
      requestedMode: 'auto',
      finalMode: 'knowledge',
      scopeJson: '{"type":"all"}',
      activeStrategyId: RetrievalStrategies.activeControl.id,
      startedAt: DateTime.utc(2026, 9, 2),
      completedAt: DateTime.utc(2026, 9, 2, 0, 0, 1),
      status: TraceStatus.complete,
      failureStage: null,
      failureCode: null,
    ),
  );
  await lineage.putEmbedding(
    LineageEmbedding.test(
      embeddingId: LineageIds.queryEmbeddingId('tr-okf'),
      sourceKind: 'query',
      sourceId: 'tr-okf',
      chunkId: null,
      representation: EmbeddingRepresentation.query,
      vector: const <double>[1, 0],
      modelIdentity: 'test',
      taskMode: 'retrieval_query',
    ),
  );
  await lineage.putEmbedding(
    LineageEmbedding.test(
      embeddingId: LineageIds.bodyEmbeddingId(verified.id),
      sourceKind: 'chunk',
      sourceId: verified.id,
      documentId: verified.documentId,
      chunkId: verified.id,
      representation: EmbeddingRepresentation.body,
      vector: const <double>[0.985, 0.015],
      modelIdentity: 'test',
      taskMode: 'retrieval_document',
    ),
  );
  await lineage.putEmbedding(
    LineageEmbedding.test(
      embeddingId: LineageIds.bodyEmbeddingId(stale.id),
      sourceKind: 'chunk',
      sourceId: stale.id,
      documentId: stale.documentId,
      chunkId: stale.id,
      representation: EmbeddingRepresentation.body,
      vector: const <double>[0.999, 0.001],
      modelIdentity: 'test',
      taskMode: 'retrieval_document',
    ),
  );

  final activeCandidate = CandidateRecord(
    candidateId: LineageIds.candidateId(
      'tr-okf',
      RetrievalStrategies.activeControl.id,
      stale.id,
    ),
    traceId: 'tr-okf',
    strategyId: RetrievalStrategies.activeControl.id,
    lane: RetrievalLane.active,
    chunkId: stale.id,
    embeddingId: LineageIds.bodyEmbeddingId(stale.id),
    sourceChannels: 'fts5,embedding',
    ftsRank: 1,
    rawBm25: -1,
    vectorRank: 1,
    rawCosine: 0.999,
    fusionRank: 1,
    fusionScore: 0.12,
    rerankRank: null,
    rerankScore: null,
    finalRank: 1,
    selectedForEvidence: true,
    dropReason: null,
  );
  await lineage.putCandidate(activeCandidate);
  await lineage.putEvidence(
    EvidenceRecord(
      evidenceId: LineageIds.evidenceId(
        'tr-okf',
        RetrievalStrategies.activeControl.id,
        stale.id,
      ),
      traceId: 'tr-okf',
      strategyId: RetrievalStrategies.activeControl.id,
      lane: RetrievalLane.active,
      anchor: 'E1',
      candidateId: activeCandidate.candidateId,
      chunkId: stale.id,
      selectionRank: 1,
      score: 0.12,
      tokenCount: 18,
      selectionReason: 'active_control',
    ),
  );

  const parser = OkfParser();
  await okf.replaceDocument(
    verified.documentId,
    parser.parseMarkdown(
      '''---
type: Policy
verified: human:qa
stale_after: 2027-01-01
sources:
  - location: source/validated.md
---
# Torque
See [Calibration](calibration.md) and [Test](test.md).
''',
      documentId: verified.documentId,
      sourceName: verified.sourceName,
      now: DateTime.utc(2026, 9, 2),
    ),
  );
  await okf.replaceDocument(
    stale.documentId,
    parser.parseMarkdown(
      '''---
type: Policy
generated: process:legacy
stale_after: 2026-01-01
---
# Torque
Historical policy.
''',
      documentId: stale.documentId,
      sourceName: stale.sourceName,
      now: DateTime.utc(2026, 9, 2),
    ),
  );

  return (lineage: lineage, lexical: lexical, okf: okf);
}

void main() {
  test('OKF signal policy is bounded, explainable, and penalizes stale facts', () {
    const policy = OkfSignalPolicy();
    const parser = OkfParser();
    final verified = parser
        .parseMarkdown(
          '---\ntype: Policy\nverified: human:qa\nstale_after: 2027-01-01\n---\n# P',
          documentId: 'verified',
          sourceName: 'verified.md',
          now: DateTime.utc(2026, 9, 2),
        )
        .document;
    final stale = parser
        .parseMarkdown(
          '---\ntype: Policy\ngenerated: process:legacy\nstale_after: 2026-01-01\n---\n# P',
          documentId: 'stale',
          sourceName: 'stale.md',
          now: DateTime.utc(2026, 9, 2),
        )
        .document;

    final trusted = policy.score(
      baseScore: 0.10,
      document: verified,
      relativeLinkCount: 2,
    );
    final old = policy.score(
      baseScore: 0.11,
      document: stale,
      relativeLinkCount: 0,
    );

    expect(trusted.finalScore, greaterThan(old.finalScore));
    expect(trusted.trustAdjustment, greaterThan(0));
    expect(old.freshnessAdjustment, lessThan(0));
    expect(trusted.reason, contains('verified'));
    expect(trusted.reason, contains('fresh'));
    expect(trusted.reason, contains('links'));
    expect(trusted.totalAdjustment.abs(), lessThanOrEqualTo(0.08));
  });

  test(
    'OKF SHADOW reranks candidates without mutating ACTIVE evidence',
    () async {
      final data = await _fixture();
      final activeBefore = await data.lineage.candidatesForTrace(
        'tr-okf',
        strategyId: RetrievalStrategies.activeControl.id,
        lane: RetrievalLane.active,
      );
      final activeEvidenceBefore = await data.lineage.evidenceForTrace(
        'tr-okf',
        strategyId: RetrievalStrategies.activeControl.id,
        lane: RetrievalLane.active,
      );
      final engine = OkfAwareRetrievalExperimentEngine(
        store: data.lineage,
        lexicalStore: data.lexical,
        representationBuilder: RepresentationBuilder(
          store: data.lineage,
          lexicalStore: data.lexical,
          generator: _Generator(),
          modelIdentity: 'test',
        ),
        okfStore: data.okf,
        now: () => DateTime.utc(2026, 9, 2),
      );

      final run = await engine.run(
        traceId: 'tr-okf',
        strategyId: RetrievalStrategies.okfV02Structured.id,
      );
      final shadow = await data.lineage.candidatesForTrace(
        'tr-okf',
        strategyId: RetrievalStrategies.okfV02Structured.id,
        lane: RetrievalLane.shadow,
      );
      final signals = await data.okf.candidateSignals(
        traceId: 'tr-okf',
        strategyId: RetrievalStrategies.okfV02Structured.id,
      );
      final activeAfter = await data.lineage.candidatesForTrace(
        'tr-okf',
        strategyId: RetrievalStrategies.activeControl.id,
        lane: RetrievalLane.active,
      );
      final activeEvidenceAfter = await data.lineage.evidenceForTrace(
        'tr-okf',
        strategyId: RetrievalStrategies.activeControl.id,
        lane: RetrievalLane.active,
      );

      expect(run.status, ExperimentRunStatus.complete);
      expect(shadow.first.chunkId, 'c-verified');
      expect(signals, hasLength(2));
      expect(signals.first.documentId, 'd-verified');
      expect(activeAfter.single.fusionScore, activeBefore.single.fusionScore);
      expect(activeAfter.single.finalRank, activeBefore.single.finalRank);
      expect(
        activeEvidenceAfter.single.anchor,
        activeEvidenceBefore.single.anchor,
      );
      expect(
        activeEvidenceAfter.single.score,
        activeEvidenceBefore.single.score,
      );
    },
  );

  test('Gallery exposes a human-readable three-arm OKF Lab', () async {
    final engine = await File(
      'lib/services/knowledge_engine.dart',
    ).readAsString();
    final ui = await File(
      'lib/ui/microscope/retrieval_experiment_center_page.dart',
    ).readAsString();

    expect(engine, contains('OkfStore'));
    expect(engine, contains('OkfAwareRetrievalExperimentEngine'));
    expect(engine, contains('okfStore.replaceDocument'));
    expect(ui, contains('OKF Lab'));
    expect(ui, contains('BARE MODEL'));
    expect(ui, contains('MARKDOWN CONTROL'));
    expect(ui, contains('OKF v0.2'));
    expect(ui, contains('信任'));
    expect(ui, contains('新鲜度'));
  });
}
