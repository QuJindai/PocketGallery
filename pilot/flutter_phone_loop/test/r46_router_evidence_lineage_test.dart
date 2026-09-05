import 'package:flutter_test/flutter_test.dart';

import 'package:pocketgallery_phone_pilot/core/models.dart';
import 'package:pocketgallery_phone_pilot/retrieval/evidence_policy.dart';
import 'package:pocketgallery_phone_pilot/retrieval/router_policy.dart';

const chunk1 = PgChunk(
  id: 'c1',
  documentId: 'd1',
  sourceName: 'doc.md',
  locator: 's1',
  ordinal: 0,
  text: 'one',
);

RetrievalHit semantic(double score, int rank, [PgChunk chunk = chunk1]) =>
    RetrievalHit(
      chunk: chunk,
      score: score,
      channel: 'embedding',
      rank: rank,
    );

HybridHit hybrid(
  PgChunk chunk,
  double score, {
  Set<String> channels = const <String>{'embedding'},
}) =>
    HybridHit(
      chunk: chunk,
      score: score,
      channels: channels,
      lexicalRank: channels.contains('fts5') ? 1 : null,
      semanticRank: channels.contains('embedding') ? 1 : null,
    );

void main() {
  group('router policy preserves the shipped R4.7 thresholds', () {
    const policy = RouterPolicy();
    const chunk2 = PgChunk(
      id: 'c2',
      documentId: 'd1',
      sourceName: 'doc.md',
      locator: 's2',
      ordinal: 1,
      text: 'two',
    );

    test('rejects weak semantic noise in auto mode', () {
      final decision = policy.evaluate(
        lexicalHits: const <RetrievalHit>[],
        semanticHits: <RetrievalHit>[
          semantic(0.53, 1),
          semantic(0.52, 2, chunk2),
        ],
        hybridHits: <HybridHit>[hybrid(chunk1, 0.03)],
        evidenceAvailable: true,
        requestedMode: 'auto',
      );
      expect(decision.useKnowledge, isFalse);
      expect(decision.reason, 'insufficient_semantic');
    });

    test('accepts strong, gapped, lexical and dual-channel evidence', () {
      final strong = policy.evaluate(
        lexicalHits: const <RetrievalHit>[],
        semanticHits: <RetrievalHit>[
          semantic(0.63, 1),
          semantic(0.62, 2, chunk2),
        ],
        hybridHits: <HybridHit>[hybrid(chunk1, 0.03)],
        evidenceAvailable: true,
        requestedMode: 'auto',
      );
      final gapped = policy.evaluate(
        lexicalHits: const <RetrievalHit>[],
        semanticHits: <RetrievalHit>[
          semantic(0.60, 1),
          semantic(0.54, 2, chunk2),
        ],
        hybridHits: <HybridHit>[hybrid(chunk1, 0.03)],
        evidenceAvailable: true,
        requestedMode: 'auto',
      );
      final lexical = policy.evaluate(
        lexicalHits: <RetrievalHit>[
          const RetrievalHit(
            chunk: chunk1,
            score: 0.8,
            channel: 'fts5',
            rank: 1,
          ),
        ],
        semanticHits: const <RetrievalHit>[],
        hybridHits: <HybridHit>[
          hybrid(chunk1, 0.03, channels: const <String>{'fts5'}),
        ],
        evidenceAvailable: true,
        requestedMode: 'auto',
      );
      final dual = policy.evaluate(
        lexicalHits: const <RetrievalHit>[],
        semanticHits: <RetrievalHit>[semantic(0.40, 1)],
        hybridHits: <HybridHit>[
          hybrid(
            chunk1,
            0.03,
            channels: const <String>{'embedding', 'fts5'},
          ),
        ],
        evidenceAvailable: true,
        requestedMode: 'auto',
      );

      expect(strong.reason, 'semantic_strong');
      expect(gapped.reason, 'semantic_gap');
      expect(lexical.reason, 'lexical_hit');
      expect(dual.reason, 'dual_channel');
      expect(<bool>[
        strong.useKnowledge,
        gapped.useKnowledge,
        lexical.useKnowledge,
        dual.useKnowledge,
      ], everyElement(isTrue));
    });

    test('knowledge mode uses its existing lower floor and gap', () {
      final decision = policy.evaluate(
        lexicalHits: const <RetrievalHit>[],
        semanticHits: <RetrievalHit>[
          semantic(0.51, 1),
          semantic(0.48, 2, chunk2),
        ],
        hybridHits: <HybridHit>[hybrid(chunk1, 0.03)],
        evidenceAvailable: true,
        requestedMode: 'knowledge',
      );
      expect(decision.useKnowledge, isTrue);
      expect(decision.reason, 'semantic_gap');
    });
  });

  group('evidence policy keeps latest five-item behavior and explains drops', () {
    const policy = EvidencePolicy();

    test('caps ordinary evidence at five', () {
      final hits = <HybridHit>[
        for (var i = 0; i < 6; i++)
          hybrid(
            PgChunk(
              id: 'c$i',
              documentId: 'd1',
              sourceName: 'doc.md',
              locator: 's$i',
              ordinal: i,
              text: 'evidence $i',
            ),
            1 - (i * 0.02),
          ),
      ];
      final selection = policy.select(hits);
      expect(selection.evidence, hasLength(5));
      expect(selection.dropReasonFor('c5'), 'max_evidence');
    });

    test('records relative-score and token-budget drops', () {
      const longChunk = PgChunk(
        id: 'long',
        documentId: 'd1',
        sourceName: 'doc.md',
        locator: 'long',
        ordinal: 2,
        text: '1234567890',
      );
      const weakChunk = PgChunk(
        id: 'weak',
        documentId: 'd1',
        sourceName: 'doc.md',
        locator: 'weak',
        ordinal: 3,
        text: 'weak',
      );
      final relative = policy.select(<HybridHit>[
        hybrid(chunk1, 1),
        hybrid(weakChunk, 0.70),
      ]);
      final budgeted = policy.select(
        <HybridHit>[hybrid(longChunk, 1)],
        maxTotalChars: 5,
      );

      expect(relative.dropReasonFor('weak'), 'relative_score_cutoff');
      expect(budgeted.evidence, isEmpty);
      expect(budgeted.dropReasonFor('long'), 'token_budget');
    });
  });
}
