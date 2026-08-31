import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:pocketgallery_phone_pilot/core/models.dart';
import 'package:pocketgallery_phone_pilot/experiments/representation_builder.dart';
import 'package:pocketgallery_phone_pilot/experiments/retrieval_experiment_engine.dart';
import 'package:pocketgallery_phone_pilot/experiments/retrieval_strategy.dart';
import 'package:pocketgallery_phone_pilot/lineage/import_lineage.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_ids.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_models.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_store.dart';
import 'package:pocketgallery_phone_pilot/retrieval/query_embedding_runtime.dart';
import 'package:pocketgallery_phone_pilot/services/lexical_fts_store.dart';

class _ExperimentGenerator implements EmbeddingGenerator {
  _ExperimentGenerator({this.fail = false});

  final bool fail;
  int queryCalls = 0;

  @override
  Future<List<double>> generateDocument(String text) async {
    if (fail) throw StateError('shadow build failed');
    return const <double>[1, 0];
  }

  @override
  Future<List<double>> generateQuery(String text) async {
    queryCalls++;
    throw StateError('must reuse captured query vector');
  }
}

Future<({LineageStore store, LexicalFtsStore lexical})> _fixture(
  Database lineageDb,
  Database lexicalDb,
) async {
  final store = LineageStore(database: lineageDb);
  final lexical = LexicalFtsStore(database: lexicalDb);
  await store.initialize();
  await lexical.initialize();
  const chunk = PgChunk(
    id: 'c1',
    documentId: 'd1',
    sourceName: 'safety.md',
    locator: 'p1',
    ordinal: 0,
    text: '电池安全验证需要检查温度和绝缘。',
  );
  await lexical.replaceDocument(const ImportedDocument(
    documentId: 'd1',
    sourceName: 'safety.md',
    sha256: 'sha-d1',
    chunks: <PgChunk>[chunk],
  ));
  await store.upsertLineageSection(
    sectionId: 'sec1',
    documentId: 'd1',
    pageNo: null,
    heading: '电池安全',
    sectionType: 'heading',
    startOffset: 0,
    endOffset: chunk.text.length,
    charCount: chunk.text.length,
    parseStatus: ParseStatus.parsed.dbValue,
  );
  await store.upsertLineageChunk(
    chunkId: chunk.id,
    documentId: chunk.documentId,
    sectionId: 'sec1',
    locator: chunk.locator,
    ordinal: chunk.ordinal,
    startOffset: 0,
    endOffset: chunk.text.length,
    charCount: chunk.text.length,
    tokenCount: 24,
    overlapFromPrevious: 0,
    chunkStrategy: 'test',
    boundaryReason: 'section-boundary',
    provenanceQuality: ProvenanceQuality.exact.name,
  );
  await store.putTrace(LineageTrace(
    traceId: 'tr-shadow',
    sessionId: 's1',
    turnId: 't1',
    queryText: '电池安全',
    requestedMode: 'auto',
    finalMode: 'knowledge',
    scopeJson: '{"type":"all"}',
    activeStrategyId: 'active.r45-body-hybrid',
    startedAt: DateTime.utc(2026, 8, 31),
    completedAt: DateTime.utc(2026, 8, 31, 0, 0, 1),
    status: TraceStatus.complete,
    failureStage: null,
    failureCode: null,
  ));
  await store.putEmbedding(LineageEmbedding.test(
    embeddingId: LineageIds.queryEmbeddingId('tr-shadow'),
    sourceKind: 'query',
    sourceId: 'tr-shadow',
    chunkId: null,
    representation: EmbeddingRepresentation.query,
    vector: const <double>[1, 0],
    modelIdentity: 'test',
    taskMode: 'retrieval_query',
  ));
  await store.putEmbedding(LineageEmbedding.test(
    embeddingId: LineageIds.bodyEmbeddingId('c1'),
    sourceKind: 'chunk',
    sourceId: 'c1',
    documentId: 'd1',
    chunkId: 'c1',
    representation: EmbeddingRepresentation.body,
    vector: const <double>[0.8, 0.2],
    modelIdentity: 'test',
    taskMode: 'retrieval_document',
  ));
  final activeCandidate = CandidateRecord(
    candidateId: LineageIds.candidateId(
      'tr-shadow',
      'active.r45-body-hybrid',
      'c1',
    ),
    traceId: 'tr-shadow',
    strategyId: 'active.r45-body-hybrid',
    lane: RetrievalLane.active,
    chunkId: 'c1',
    embeddingId: LineageIds.bodyEmbeddingId('c1'),
    sourceChannels: 'fts5,embedding',
    ftsRank: 1,
    rawBm25: -1,
    vectorRank: 1,
    rawCosine: 0.8,
    fusionRank: 1,
    fusionScore: 0.9,
    rerankRank: null,
    rerankScore: null,
    finalRank: 1,
    selectedForEvidence: true,
    dropReason: null,
  );
  await store.putCandidate(activeCandidate);
  await store.putEvidence(EvidenceRecord(
    evidenceId: LineageIds.evidenceId(
      'tr-shadow',
      'active.r45-body-hybrid',
      'c1',
    ),
    traceId: 'tr-shadow',
    strategyId: 'active.r45-body-hybrid',
    lane: RetrievalLane.active,
    anchor: 'E1',
    candidateId: activeCandidate.candidateId,
    chunkId: 'c1',
    selectionRank: 1,
    score: 0.9,
    tokenCount: 24,
    selectionReason: 'active_control',
  ));
  return (store: store, lexical: lexical);
}

void main() {
  test('on-demand shadow run reuses query vector and cannot mutate ACTIVE',
      () async {
    final lineageDb = sqlite3.openInMemory();
    final lexicalDb = sqlite3.openInMemory();
    addTearDown(lineageDb.close);
    addTearDown(lexicalDb.close);
    final data = await _fixture(lineageDb, lexicalDb);
    final generator = _ExperimentGenerator();
    final engine = RetrievalExperimentEngine(
      store: data.store,
      lexicalStore: data.lexical,
      representationBuilder: RepresentationBuilder(
        store: data.store,
        lexicalStore: data.lexical,
        generator: generator,
        modelIdentity: 'test',
      ),
    );

    final run = await engine.run(
      traceId: 'tr-shadow',
      strategyId: RetrievalStrategies.headingBodyMultivector.id,
    );

    expect(run.status, ExperimentRunStatus.complete);
    expect(run.lane, RetrievalLane.shadow);
    expect(generator.queryCalls, 0);
    final activeCandidates = await data.store.candidatesForTrace(
      'tr-shadow',
      strategyId: 'active.r45-body-hybrid',
      lane: RetrievalLane.active,
    );
    final activeEvidence = await data.store.evidenceForTrace(
      'tr-shadow',
      strategyId: 'active.r45-body-hybrid',
      lane: RetrievalLane.active,
    );
    final shadowCandidates = await data.store.candidatesForTrace(
      'tr-shadow',
      strategyId: RetrievalStrategies.headingBodyMultivector.id,
      lane: RetrievalLane.shadow,
    );
    final shadowEvidence = await data.store.evidenceForTrace(
      'tr-shadow',
      strategyId: RetrievalStrategies.headingBodyMultivector.id,
      lane: RetrievalLane.shadow,
    );
    expect(activeCandidates, hasLength(1));
    expect(activeCandidates.single.fusionScore, 0.9);
    expect(activeEvidence, hasLength(1));
    expect(activeEvidence.single.anchor, 'E1');
    expect(shadowCandidates, isNotEmpty);
    expect(shadowEvidence, isNotEmpty);
    expect(shadowEvidence.every((item) => item.anchor == null), isTrue);
  });

  test('shadow failure remains inspectable and leaves trace complete', () async {
    final lineageDb = sqlite3.openInMemory();
    final lexicalDb = sqlite3.openInMemory();
    addTearDown(lineageDb.close);
    addTearDown(lexicalDb.close);
    final data = await _fixture(lineageDb, lexicalDb);
    final engine = RetrievalExperimentEngine(
      store: data.store,
      lexicalStore: data.lexical,
      representationBuilder: RepresentationBuilder(
        store: data.store,
        lexicalStore: data.lexical,
        generator: _ExperimentGenerator(fail: true),
        modelIdentity: 'test',
      ),
    );

    final run = await engine.run(
      traceId: 'tr-shadow',
      strategyId: RetrievalStrategies.headingBodyMultivector.id,
    );

    expect(run.status, ExperimentRunStatus.failed);
    expect(run.failureCode, isNotNull);
    expect(run.failureDetail, contains('shadow build failed'));
    expect((await data.store.traceById('tr-shadow'))!.status, TraceStatus.complete);
    expect(
      await data.store.evidenceForTrace(
        'tr-shadow',
        strategyId: 'active.r45-body-hybrid',
        lane: RetrievalLane.active,
      ),
      hasLength(1),
    );
  });

  test('shadow ignores same-dimension embeddings from a stale model',
      () async {
    final lineageDb = sqlite3.openInMemory();
    final lexicalDb = sqlite3.openInMemory();
    addTearDown(lineageDb.close);
    addTearDown(lexicalDb.close);
    final data = await _fixture(lineageDb, lexicalDb);
    const staleChunk = PgChunk(
      id: 'c-stale',
      documentId: 'd-stale',
      sourceName: 'stale.md',
      locator: 'p1',
      ordinal: 0,
      text: '与查询无关的历史模型内容。',
    );
    await data.lexical.replaceDocument(const ImportedDocument(
      documentId: 'd-stale',
      sourceName: 'stale.md',
      sha256: 'sha-stale',
      chunks: <PgChunk>[staleChunk],
    ));
    await data.store.putEmbedding(LineageEmbedding.test(
      embeddingId: LineageIds.bodyEmbeddingId(staleChunk.id),
      sourceKind: 'chunk',
      sourceId: staleChunk.id,
      documentId: staleChunk.documentId,
      chunkId: staleChunk.id,
      representation: EmbeddingRepresentation.body,
      vector: const <double>[1, 0],
      modelIdentity: 'stale-same-dimension',
      taskMode: 'retrieval_document',
    ));
    final engine = RetrievalExperimentEngine(
      store: data.store,
      lexicalStore: data.lexical,
      representationBuilder: RepresentationBuilder(
        store: data.store,
        lexicalStore: data.lexical,
        generator: _ExperimentGenerator(),
        modelIdentity: 'test',
      ),
    );

    final run = await engine.run(
      traceId: 'tr-shadow',
      strategyId: RetrievalStrategies.dynamicEvidence.id,
    );
    final candidates = await data.store.candidatesForTrace(
      'tr-shadow',
      strategyId: RetrievalStrategies.dynamicEvidence.id,
      lane: RetrievalLane.shadow,
    );

    expect(run.status, ExperimentRunStatus.complete);
    expect(candidates.map((item) => item.chunkId), isNot(contains('c-stale')));
  });
}
