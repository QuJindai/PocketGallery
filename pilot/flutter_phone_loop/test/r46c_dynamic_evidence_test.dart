import 'package:flutter_test/flutter_test.dart';

import 'package:pocketgallery_phone_pilot/experiments/dynamic_evidence_policy.dart';

void main() {
  test('dynamic evidence stays within reserve and favors diverse sources', () {
    const policy = DynamicEvidencePolicy(maxEvidence: 3);
    const candidates = <DynamicEvidenceCandidate>[
      DynamicEvidenceCandidate(
        candidateId: 'a0',
        chunkId: 'a0',
        documentId: 'doc-a',
        ordinal: 0,
        score: 1,
        tokenCount: 100,
      ),
      DynamicEvidenceCandidate(
        candidateId: 'a1',
        chunkId: 'a1',
        documentId: 'doc-a',
        ordinal: 1,
        score: 0.98,
        tokenCount: 100,
      ),
      DynamicEvidenceCandidate(
        candidateId: 'b0',
        chunkId: 'b0',
        documentId: 'doc-b',
        ordinal: 0,
        score: 0.96,
        tokenCount: 120,
      ),
      DynamicEvidenceCandidate(
        candidateId: 'c0',
        chunkId: 'c0',
        documentId: 'doc-c',
        ordinal: 0,
        score: 0.94,
        tokenCount: 140,
      ),
    ];

    final selected = policy.select(candidates, tokenReserve: 250);

    expect(selected.selected.map((item) => item.chunkId), ['a0', 'b0']);
    expect(selected.totalTokens, 220);
    expect(selected.totalTokens, lessThanOrEqualTo(250));
    expect(selected.dropReasons['a1'], 'near_neighbor_duplicate');
    expect(selected.dropReasons['c0'], 'token_budget');
    expect(selected.selected.length, inInclusiveRange(1, 3));
  });

  test('dynamic evidence applies the hard three-item ordinary Q&A cap', () {
    const policy = DynamicEvidencePolicy();
    final candidates = <DynamicEvidenceCandidate>[
      for (var index = 0; index < 5; index++)
        DynamicEvidenceCandidate(
          candidateId: 'c$index',
          chunkId: 'c$index',
          documentId: 'd$index',
          ordinal: 0,
          score: 1 - index / 100,
          tokenCount: 20,
        ),
    ];

    final selected = policy.select(candidates, tokenReserve: 500);

    expect(selected.selected, hasLength(3));
    expect(selected.dropReasons.values, everyElement('max_evidence'));
  });
}
