import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:pocketgallery_phone_pilot/chat/chat_models.dart';
import 'package:pocketgallery_phone_pilot/core/models.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_ids.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_models.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_store.dart';
import 'package:pocketgallery_phone_pilot/lineage/r45_vector_migration.dart';
import 'package:pocketgallery_phone_pilot/observability/vector_observation_store.dart';
import 'package:pocketgallery_phone_pilot/retrieval/active_vector_index.dart';
import 'package:pocketgallery_phone_pilot/services/lexical_fts_store.dart';

class RecordingActiveVectorIndex implements ActiveVectorIndex {
  final addCounts = <String, int>{};
  String? failOnceId;
  bool initialized = false;

  @override
  Future<void> initialize() async => initialized = true;

  @override
  Future<void> add(VectorIndexRecord record) async {
    addCounts.update(record.embeddingId, (v) => v + 1, ifAbsent: () => 1);
    if (failOnceId == record.embeddingId) {
      failOnceId = null;
      throw StateError('synthetic index interruption');
    }
  }

  @override
  Future<void> remove(String embeddingId) async {}

  @override
  Future<List<VectorSearchHit>> searchByEmbedding({
    required List<double> queryEmbedding,
    required int topK,
    required KnowledgeScope scope,
  }) async => const [];

  @override
  Future<VectorIndexProbe> probe() async => VectorIndexProbe(
        initialized: initialized,
        databasePath: 'memory://v46',
        backendId: 'recording-v46',
        searchVerified: false,
      );

  @override
  Future<void> close() async => initialized = false;
}

class MigrationFixture {
  MigrationFixture._({
    required this.lexicalDb,
    required this.observationDb,
    required this.lineageDb,
    required this.lexical,
    required this.observations,
    required this.lineage,
    required this.index,
    required this.generatedChunks,
    required this.migration,
  });

  final Database lexicalDb;
  final Database observationDb;
  final Database lineageDb;
  final LexicalFtsStore lexical;
  final VectorObservationStore observations;
  final LineageStore lineage;
  final RecordingActiveVectorIndex index;
  final List<String> generatedChunks;
  final R45VectorMigration migration;

  static Future<MigrationFixture> create({required List<PgChunk> chunks}) async {
    final lexicalDb = sqlite3.openInMemory();
    final observationDb = sqlite3.openInMemory();
    final lineageDb = sqlite3.openInMemory();
    final lexical = LexicalFtsStore(database: lexicalDb);
    final observations = VectorObservationStore(database: observationDb);
    final lineage = LineageStore(database: lineageDb);
    final index = RecordingActiveVectorIndex();
    await lexical.initialize();
    await observations.initialize();
    await lineage.initialize();
    await lexical.replaceDocument(ImportedDocument(
      documentId: 'doc-1',
      sourceName: 'legacy_notes.txt',
      sha256: 'legacy-sha',
      chunks: chunks,
    ));
    final generated = <String>[];
    final migration = R45VectorMigration(
      lexicalStore: lexical,
      observationStore: observations,
      lineageStore: lineage,
      activeVectorIndex: index,
      embeddingGenerator: (chunk) async {
        generated.add(chunk.id);
        return switch (chunk.id) {
          'c2' => const [0.2, 0.8],
          'c3' => const [0.3, 0.7],
          'c4' => const [0.4, 0.6],
          _ => const [0.55, 0.45],
        };
      },
    );
    return MigrationFixture._(
      lexicalDb: lexicalDb,
      observationDb: observationDb,
      lineageDb: lineageDb,
      lexical: lexical,
      observations: observations,
      lineage: lineage,
      index: index,
      generatedChunks: generated,
      migration: migration,
    );
  }

  void close() {
    lexicalDb.close();
    observationDb.close();
    lineageDb.close();
  }
}

PgChunk chunk(String id, int ordinal) => PgChunk(
      id: id,
      documentId: 'doc-1',
      sourceName: 'legacy_notes.txt',
      locator: 'text',
      ordinal: ordinal,
      text: 'legacy chunk $id',
    );

void main() {
  test('healthy R4.5 body vector is reused while missing stale and invalid vectors are generated', () async {
    final f = await MigrationFixture.create(
      chunks: [chunk('c1', 0), chunk('c2', 1), chunk('c3', 2), chunk('c4', 3)],
    );
    addTearDown(f.close);

    await f.observations.putChunkVector(
      chunkId: 'c1',
      documentId: 'doc-1',
      vector: const [0.5, 0.75],
      modelIdentity: 'EmbeddingGemma-test',
    );
    await f.observations.putChunkVector(
      chunkId: 'c3',
      documentId: 'doc-1',
      vector: const [0.3, 0.7],
      modelIdentity: 'old-model',
    );
    await f.observations.putChunkVector(
      chunkId: 'c4',
      documentId: 'doc-1',
      vector: const [0.0, 0.0],
      modelIdentity: 'EmbeddingGemma-test',
    );
    final before = await f.observations.getChunkVector('c1');

    final report = await f.migration.migrateActiveBodyVectors(
      activeModelIdentity: 'EmbeddingGemma-test',
      expectedDimension: 2,
    );

    expect(f.generatedChunks, unorderedEquals(['c2', 'c3', 'c4']));
    expect(f.generatedChunks, isNot(contains('c1')));
    expect(report.reusedFromR45, 1);
    expect(report.generated, 3);
    expect(report.failed, 0);

    final migrated = await f.lineage.embeddingById(LineageIds.bodyEmbeddingId('c1'));
    expect(migrated, isNotNull);
    expect(migrated!.vector, before!.vector,
        reason: 'healthy Float32 values must be copied rather than regenerated');
    expect(migrated.modelIdentity, 'EmbeddingGemma-test');
    expect(migrated.representation, EmbeddingRepresentation.body);

    for (final id in ['c1', 'c2', 'c3', 'c4']) {
      final embeddingId = LineageIds.bodyEmbeddingId(id);
      expect(embeddingId, isNot(id));
      expect(f.index.addCounts[embeddingId], 1);
      final entry = await f.lineage.vectorIndexEntryForEmbedding(
        embeddingId,
        R45VectorMigration.activeStrategyId,
        RetrievalLane.active,
      );
      expect(entry!.commitStatus, VectorCommitStatus.committed);
    }

    final job = await f.lineage.buildJobById(
      LineageIds.buildJobId('doc-1', R45VectorMigration.activeStrategyId),
    );
    expect(job!.status, BuildJobStatus.complete);
    expect(job.checkpointJson, contains('"state":"ready"'));
    expect(await f.observations.count(), 3,
        reason: 'migration must not clear or rewrite the R4.5 observation store');
    expect((await f.observations.getChunkVector('c1'))!.vector, before.vector);
  });

  test('rerun after vector-index interruption resumes persisted embedding without generating twice', () async {
    final f = await MigrationFixture.create(
      chunks: [chunk('c1', 0), chunk('c2', 1)],
    );
    addTearDown(f.close);
    final c2EmbeddingId = LineageIds.bodyEmbeddingId('c2');
    f.index.failOnceId = c2EmbeddingId;

    final first = await f.migration.migrateActiveBodyVectors(
      activeModelIdentity: 'EmbeddingGemma-test',
      expectedDimension: 2,
    );
    expect(first.generated, 2);
    expect(first.failed, 1);
    expect(f.generatedChunks, ['c1', 'c2']);
    expect(await f.lineage.embeddingById(c2EmbeddingId), isNotNull,
        reason: 'generated embedding must be checkpointed before index add');
    expect(
      (await f.lineage.vectorIndexEntryForEmbedding(
        c2EmbeddingId,
        R45VectorMigration.activeStrategyId,
        RetrievalLane.active,
      ))!
          .commitStatus,
      VectorCommitStatus.failed,
    );

    final second = await f.migration.migrateActiveBodyVectors(
      activeModelIdentity: 'EmbeddingGemma-test',
      expectedDimension: 2,
    );
    expect(second.generated, 0);
    expect(second.resumedPersisted, 1);
    expect(second.alreadyCommitted, 1);
    expect(second.failed, 0);
    expect(f.generatedChunks, ['c1', 'c2'],
        reason: 'rerun must reuse the persisted c2 embedding');
    expect(f.index.addCounts[LineageIds.bodyEmbeddingId('c1')], 1,
        reason: 'already committed c1 must not be re-added');
    expect(f.index.addCounts[c2EmbeddingId], 2,
        reason: 'only the failed index insertion is retried');
    expect(
      (await f.lineage.vectorIndexEntryForEmbedding(
        c2EmbeddingId,
        R45VectorMigration.activeStrategyId,
        RetrievalLane.active,
      ))!
          .commitStatus,
      VectorCommitStatus.committed,
    );
  });
}
