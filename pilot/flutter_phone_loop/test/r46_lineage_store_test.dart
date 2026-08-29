import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_ids.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_models.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_store.dart';

void main() {
  test('chunk and embedding identities are distinct and one chunk can own many embeddings', () async {
    final db = sqlite3.openInMemory();
    final store = LineageStore(database: db);
    await store.initialize();

    const chunkId = 'doc:7';
    final bodyId = LineageIds.embeddingId(
      sourceKind: 'chunk',
      sourceId: chunkId,
      representation: EmbeddingRepresentation.body,
    );
    final headingId = LineageIds.embeddingId(
      sourceKind: 'chunk',
      sourceId: chunkId,
      representation: EmbeddingRepresentation.heading,
    );
    expect(bodyId, isNot(chunkId));
    expect(headingId, isNot(chunkId));
    expect(bodyId, isNot(headingId));

    await store.putEmbedding(LineageEmbedding.test(
      embeddingId: bodyId,
      sourceKind: 'chunk',
      sourceId: chunkId,
      chunkId: chunkId,
      representation: EmbeddingRepresentation.body,
      vector: const [1.0, 0.0],
      modelIdentity: 'EmbeddingGemma-test',
      taskMode: 'retrieval_document',
    ));
    await store.putEmbedding(LineageEmbedding.test(
      embeddingId: headingId,
      sourceKind: 'chunk',
      sourceId: chunkId,
      chunkId: chunkId,
      representation: EmbeddingRepresentation.heading,
      vector: const [0.0, 1.0],
      modelIdentity: 'EmbeddingGemma-test',
      taskMode: 'retrieval_document',
    ));
    expect(await store.embeddingsForChunk(chunkId), hasLength(2));
    db.close();
  });

  test('query embedding is first class without a chunk identity', () async {
    final db = sqlite3.openInMemory();
    final store = LineageStore(database: db);
    await store.initialize();
    final id = LineageIds.queryEmbeddingId('trace-1');
    await store.putEmbedding(LineageEmbedding.test(
      embeddingId: id,
      sourceKind: 'query',
      sourceId: 'trace-1',
      chunkId: null,
      representation: EmbeddingRepresentation.query,
      vector: const [0.2, 0.8],
      modelIdentity: 'EmbeddingGemma-test',
      taskMode: 'retrieval_query',
    ));
    final row = await store.embeddingById(id);
    expect(row!.chunkId, isNull);
    expect(row.representation, EmbeddingRepresentation.query);
    db.close();
  });

  test('lineage schema contains resumable build state and strategy scoped decisions', () async {
    final db = sqlite3.openInMemory();
    final store = LineageStore(database: db);
    await store.initialize();
    final tables = db
        .select("SELECT name FROM sqlite_master WHERE type='table'")
        .map((r) => r['name'] as String)
        .toSet();
    expect(tables, containsAll(<String>{
      'pg_lineage_documents',
      'pg_lineage_sections',
      'pg_lineage_chunks',
      'pg_embeddings',
      'pg_vector_index_entries',
      'pg_traces',
      'pg_trace_events',
      'pg_candidates',
      'pg_router_decisions',
      'pg_evidence',
      'pg_prompt_budgets',
      'pg_generation_stats',
      'pg_citations',
      'pg_experiment_runs',
      'pg_build_jobs',
    }));
    final routerSql = db
        .select("SELECT sql FROM sqlite_master WHERE name='pg_router_decisions'")
        .single['sql'] as String;
    expect(routerSql, contains('strategy_id'));
    expect(routerSql, contains('lane'));
    db.close();
  });
}
