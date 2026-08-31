import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:pocketgallery_phone_pilot/core/models.dart';
import 'package:pocketgallery_phone_pilot/experiments/representation_builder.dart';
import 'package:pocketgallery_phone_pilot/experiments/retrieval_strategy.dart';
import 'package:pocketgallery_phone_pilot/lineage/import_lineage.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_ids.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_models.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_store.dart';
import 'package:pocketgallery_phone_pilot/retrieval/query_embedding_runtime.dart';
import 'package:pocketgallery_phone_pilot/services/lexical_fts_store.dart';

class _CheckpointGenerator implements EmbeddingGenerator {
  _CheckpointGenerator({this.failOnCall});

  final int? failOnCall;
  int calls = 0;

  @override
  Future<List<double>> generateDocument(String text) async {
    calls++;
    if (calls == failOnCall) throw StateError('fixture interruption');
    return <double>[1, calls / 10];
  }

  @override
  Future<List<double>> generateQuery(String text) =>
      throw StateError('query generation is forbidden');
}

void main() {
  test('sentence representation build checkpoints and resumes missing only',
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
      id: 'c-resume',
      documentId: 'd-resume',
      sourceName: 'resume.md',
      locator: 'p1',
      ordinal: 0,
      text: '第一段内容足够长可以生成向量。第二段内容足够长可以生成向量。第三段内容足够长可以生成向量。',
    );
    await lexical.replaceDocument(const ImportedDocument(
      documentId: 'd-resume',
      sourceName: 'resume.md',
      sha256: 'sha-resume',
      chunks: <PgChunk>[chunk],
    ));
    await store.upsertLineageChunk(
      chunkId: chunk.id,
      documentId: chunk.documentId,
      sectionId: null,
      locator: chunk.locator,
      ordinal: chunk.ordinal,
      startOffset: 0,
      endOffset: chunk.text.length,
      charCount: chunk.text.length,
      tokenCount: 60,
      overlapFromPrevious: 0,
      chunkStrategy: 'test',
      boundaryReason: 'test',
      provenanceQuality: ProvenanceQuality.exact.name,
    );
    final failing = _CheckpointGenerator(failOnCall: 2);
    final first = RepresentationBuilder(
      store: store,
      lexicalStore: lexical,
      generator: failing,
      modelIdentity: 'test',
    );

    await expectLater(
      first.build(
        strategy: RetrievalStrategies.sentenceParentChild,
        chunks: const <PgChunk>[chunk],
      ),
      throwsA(isA<StateError>()),
    );
    final jobId = LineageIds.buildJobId(
      chunk.documentId,
      RetrievalStrategies.sentenceParentChild.id,
    );
    final interrupted = await store.buildJobById(jobId);
    expect(interrupted!.status, BuildJobStatus.failed);
    expect(interrupted.completedItems, 1);
    expect(interrupted.totalItems, 3);
    expect(interrupted.failureDetail, contains('fixture interruption'));

    final resumedGenerator = _CheckpointGenerator();
    final resumed = RepresentationBuilder(
      store: store,
      lexicalStore: lexical,
      generator: resumedGenerator,
      modelIdentity: 'test',
    );
    final result = await resumed.build(
      strategy: RetrievalStrategies.sentenceParentChild,
      chunks: const <PgChunk>[chunk],
    );

    expect(resumedGenerator.calls, 2);
    expect(result.generatedItems, 2);
    expect(result.reusedItems, 1);
    final completed = await store.buildJobById(jobId);
    expect(completed!.status, BuildJobStatus.complete);
    expect(completed.completedItems, 3);
    expect(completed.totalItems, 3);
    expect(
      await store.embeddingsForRepresentation(EmbeddingRepresentation.sentence),
      hasLength(3),
    );

    final upgradedGenerator = _CheckpointGenerator();
    final upgradedBuilder = RepresentationBuilder(
      store: store,
      lexicalStore: lexical,
      generator: upgradedGenerator,
      modelIdentity: 'test-next-model',
    );
    await expectLater(
      upgradedBuilder.build(
        strategy: RetrievalStrategies.sentenceParentChild,
        chunks: const <PgChunk>[chunk],
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('model identity mismatch'),
        ),
      ),
    );
    final rejected = await store.buildJobById(jobId);
    expect(upgradedGenerator.calls, 0);
    expect(rejected!.status, BuildJobStatus.failed);
    expect(rejected.failureCode, 'REPRESENTATION_MODEL_MISMATCH');
    expect(
      (await store.embeddingsForRepresentation(
        EmbeddingRepresentation.sentence,
      ))
          .every((embedding) => embedding.modelIdentity == 'test'),
      isTrue,
    );
  });
}
