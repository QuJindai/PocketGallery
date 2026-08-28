import 'package:flutter_test/flutter_test.dart';

import 'package:pocketgallery_phone_pilot/core/hybrid_ranker.dart';
import 'package:pocketgallery_phone_pilot/core/models.dart';

void main() {
  const chunk = PgChunk(
    id: 'c1',
    documentId: 'd1',
    sourceName: 'calibration.txt',
    locator: 'p.12',
    ordinal: 0,
    text: '31 03 51 01 获取标定结果时 DSA 可能持续等待最终结果。',
  );

  test('hybrid rank exposes the contributions that sum to final score', () {
    const ranker = HybridRanker(
      rrfK: 60,
      lexicalWeight: 1.0,
      semanticWeight: 1.15,
      dualChannelBonus: 0.035,
    );
    final result = ranker.fuse(
      query: '31 03 51 01 DSA 等待',
      lexical: const [
        RetrievalHit(chunk: chunk, score: 0.8, channel: 'fts5', rank: 1),
      ],
      semantic: const [
        RetrievalHit(chunk: chunk, score: 0.625, channel: 'embedding', rank: 1),
      ],
    ).single;

    expect(result.lexicalRank, 1);
    expect(result.semanticRank, 1);
    expect(result.lexicalContribution, greaterThan(0));
    expect(result.semanticContribution, greaterThan(0));
    expect(result.dualChannelContribution, closeTo(0.035, 1e-12));
    expect(result.exactTermContribution, greaterThan(0));
    expect(
      result.score,
      closeTo(
        result.lexicalContribution +
            result.semanticContribution +
            result.dualChannelContribution +
            result.exactTermContribution,
        1e-12,
      ),
    );
  });

  test('hybrid contribution refactor preserves deterministic ordering', () {
    const other = PgChunk(
      id: 'c2',
      documentId: 'd2',
      sourceName: 'other.txt',
      locator: 'p.1',
      ordinal: 0,
      text: '普通内容',
    );
    const ranker = HybridRanker();
    final result = ranker.fuse(
      query: '31 03 51 01',
      lexical: const [
        RetrievalHit(chunk: chunk, score: 0.9, channel: 'fts5', rank: 1),
        RetrievalHit(chunk: other, score: 0.4, channel: 'fts5', rank: 2),
      ],
      semantic: const [
        RetrievalHit(chunk: other, score: 0.8, channel: 'embedding', rank: 1),
        RetrievalHit(chunk: chunk, score: 0.7, channel: 'embedding', rank: 2),
      ],
    );
    expect(result.map((e) => e.chunk.id).toSet(), {'c1', 'c2'});
    expect(result.first.score, greaterThanOrEqualTo(result.last.score));
  });
}
