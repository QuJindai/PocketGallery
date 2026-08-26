import 'package:flutter_test/flutter_test.dart';
import 'package:pocketgallery_phone_pilot/core/evidence.dart';
import 'package:pocketgallery_phone_pilot/core/hybrid_ranker.dart';
import 'package:pocketgallery_phone_pilot/core/models.dart';

PgChunk c(String id, String text) => PgChunk(
  id: id,
  documentId: id.split(':').first,
  sourceName: '$id.txt',
  locator: 'text',
  ordinal: 0,
  text: text,
);

void main() {
  test('dual-channel hit wins hybrid fusion', () {
    final a = c('a:0', '31 03 51 01 标定结果 DSA 等待');
    final b = c('b:0', '机器人润滑');
    final ranker = const HybridRanker();
    final out = ranker.fuse(
      query: '31 03 51 01 为什么 DSA 等待',
      lexical: [
        RetrievalHit(chunk: a, score: 0.9, channel: 'fts5', rank: 1),
        RetrievalHit(chunk: b, score: 0.3, channel: 'fts5', rank: 2),
      ],
      semantic: [
        RetrievalHit(chunk: a, score: 0.85, channel: 'embedding', rank: 1),
      ],
    );
    expect(out.first.chunk.id, a.id);
    expect(out.first.channels, containsAll(['fts5', 'embedding']));
  });

  test('evidence anchors and citation parsing stay deterministic', () {
    final a = c('a:0', '标定结果');
    final hits = [
      HybridHit(
        chunk: a,
        score: 1,
        channels: const {'fts5', 'embedding'},
        lexicalRank: 1,
        semanticRank: 1,
      ),
    ];
    final evidence = const EvidencePackBuilder().build(hits);
    expect(evidence.single.anchor, 'E1');
    final refs = CitationResolver().extract('依据资料 [E1]。', evidence);
    expect(refs, ['E1']);
  });
}
