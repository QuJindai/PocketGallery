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

class _HeadingGenerator implements EmbeddingGenerator {
  final List<String> documents = <String>[];

  @override
  Future<List<double>> generateDocument(String text) async {
    documents.add(text);
    return text.contains('电池安全') ? <double>[1, 0] : <double>[0, 1];
  }

  @override
  Future<List<double>> generateQuery(String text) =>
      throw StateError('experiment must reuse captured query vector');
}

void main() {
  test('heading and sentence hits preserve their parent chunk identity',
      () async {
    final lineageDb = sqlite3.openInMemory();
    final lexicalDb = sqlite3.openInMemory();
    addTearDown(lineageDb.close);
    addTearDown(lexicalDb.close);
    final store = LineageStore(database: lineageDb);
    final lexical = LexicalFtsStore(database: lexicalDb);
    await store.initialize();
    await lexical.initialize();
    const chunk = PgChunk(
      id: 'c1',
      documentId: 'd1',
      sourceName: 'battery.md',
      locator: 'p1',
      ordinal: 0,
      text: '第一条说明足够长用于切句。第二条说明足够长用于切句。第三条说明足够长用于切句。'
          '第四条说明足够长用于切句。第五条说明足够长用于切句。第六条说明足够长用于切句。',
    );
    await lexical.replaceDocument(const ImportedDocument(
      documentId: 'd1',
      sourceName: 'battery.md',
      sha256: 'sha-d1',
      chunks: <PgChunk>[chunk],
    ));
    await store.upsertLineageDocument(
      documentId: 'd1',
      sourceName: 'battery.md',
      sha256: 'sha-d1',
      fileType: 'markdown',
      sizeBytes: 300,
      pageCount: null,
      parseStatus: ParseStatus.parsed.dbValue,
      parseErrorCode: null,
      parseErrorDetail: null,
      extractedCharCount: chunk.text.length,
      emptyPageCount: 0,
      provenanceQuality: ProvenanceQuality.exact.name,
      importedAt: DateTime.utc(2026, 8, 31),
    );
    await store.upsertLineageSection(
      sectionId: 'sec1',
      documentId: 'd1',
      pageNo: null,
      heading: '电池安全验证',
      sectionType: 'heading',
      startOffset: 0,
      endOffset: chunk.text.length,
      charCount: chunk.text.length,
      parseStatus: ParseStatus.parsed.dbValue,
    );
    await store.upsertLineageChunk(
      chunkId: 'c1',
      documentId: 'd1',
      sectionId: 'sec1',
      locator: 'p1',
      ordinal: 0,
      startOffset: 0,
      endOffset: chunk.text.length,
      charCount: chunk.text.length,
      tokenCount: 80,
      overlapFromPrevious: 0,
      chunkStrategy: 'test',
      boundaryReason: 'section-boundary',
      provenanceQuality: ProvenanceQuality.exact.name,
    );
    await store.putTrace(LineageTrace(
      traceId: 'tr-parent',
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
      embeddingId: LineageIds.queryEmbeddingId('tr-parent'),
      sourceKind: 'query',
      sourceId: 'tr-parent',
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
      vector: const <double>[0, 1],
      modelIdentity: 'test',
      taskMode: 'retrieval_document',
    ));
    final generator = _HeadingGenerator();
    final builder = RepresentationBuilder(
      store: store,
      lexicalStore: lexical,
      generator: generator,
      modelIdentity: 'test',
    );

    await builder.build(
      strategy: RetrievalStrategies.headingBodyMultivector,
      chunks: const <PgChunk>[chunk],
    );
    await builder.build(
      strategy: RetrievalStrategies.sentenceParentChild,
      chunks: const <PgChunk>[chunk],
    );

    final headings = await store.embeddingsForRepresentation(
      EmbeddingRepresentation.heading,
    );
    final sentences = await store.embeddingsForRepresentation(
      EmbeddingRepresentation.sentence,
    );
    expect(headings, hasLength(1));
    expect(headings.single.sourceId, 'sec1');
    expect(headings.single.chunkId, 'c1');
    expect(sentences, hasLength(4));
    expect(sentences.every((embedding) => embedding.chunkId == 'c1'), isTrue);
    expect(
      sentences.map((embedding) => '${embedding.spanStart}:${embedding.spanEnd}').toSet(),
      hasLength(4),
    );

    final engine = RetrievalExperimentEngine(
      store: store,
      lexicalStore: lexical,
      representationBuilder: builder,
    );
    final run = await engine.run(
      traceId: 'tr-parent',
      strategyId: RetrievalStrategies.headingBodyMultivector.id,
    );
    final candidates = await store.candidatesForTrace(
      'tr-parent',
      strategyId: RetrievalStrategies.headingBodyMultivector.id,
      lane: RetrievalLane.shadow,
    );

    expect(run.status, ExperimentRunStatus.complete);
    expect(candidates, isNotEmpty);
    expect(candidates.first.chunkId, 'c1');
    final trigger = await store.embeddingById(candidates.first.embeddingId!);
    expect(trigger!.representation, EmbeddingRepresentation.heading);
    expect(candidates.first.sourceChannels, contains('parent-child'));
  });
}
