import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:pocketgallery_phone_pilot/experiments/feature_reranker.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_models.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_store.dart';

void main() {
  test('feature reranker exposes hand-computable contributions', () {
    const reranker = FeatureReranker();
    const features = RerankFeatureVector(
      normalizedLexicalAffinity: 0.8,
      cosine: 0.6,
      dualChannelAgreement: 1,
      queryWindowCoverage: 0.5,
      headingMatch: 1,
      exactTermMatch: 0.5,
      sourceDiversity: 1,
    );

    final scored = reranker.score(features);

    expect(scored.contributions['normalized_lexical'], closeTo(0.16, 1e-9));
    expect(scored.contributions['cosine'], closeTo(0.18, 1e-9));
    expect(scored.contributions['dual_channel'], closeTo(0.15, 1e-9));
    expect(scored.contributions['query_coverage'], closeTo(0.05, 1e-9));
    expect(scored.contributions['heading_match'], closeTo(0.10, 1e-9));
    expect(scored.contributions['exact_term'], closeTo(0.05, 1e-9));
    expect(scored.contributions['source_diversity'], closeTo(0.05, 1e-9));
    expect(scored.score, closeTo(0.74, 1e-9));
  });

  test('rerank features persist individually for microscope inspection',
      () async {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    final store = LineageStore(database: db);
    await store.initialize();
    await store.putTrace(LineageTrace(
      traceId: 'tr-rerank',
      sessionId: 's1',
      turnId: 't1',
      queryText: '验证贡献',
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
    const record = RerankFeatureRecord(
      featureId: 'rf-1',
      traceId: 'tr-rerank',
      strategyId: 'rerank.features-v1',
      lane: RetrievalLane.shadow,
      candidateId: 'candidate-1',
      chunkId: 'chunk-1',
      normalizedLexicalAffinity: 0.8,
      cosine: 0.6,
      dualChannelAgreement: 1,
      queryWindowCoverage: 0.5,
      headingMatch: 1,
      exactTermMatch: 0.5,
      sourceDiversity: 1,
      rerankScore: 0.74,
      contributionJson: '{"cosine":0.18,"normalized_lexical":0.16}',
    );

    await store.putRerankFeature(record);
    final rows = await store.rerankFeaturesForTrace(
      'tr-rerank',
      strategyId: 'rerank.features-v1',
      lane: RetrievalLane.shadow,
    );

    expect(rows, hasLength(1));
    expect(rows.single.chunkId, 'chunk-1');
    expect(rows.single.cosine, 0.6);
    expect(rows.single.rerankScore, 0.74);
    expect(rows.single.contributionJson, contains('normalized_lexical'));
  });
}
