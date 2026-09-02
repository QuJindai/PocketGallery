import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketgallery_phone_pilot/core/models.dart';
import 'package:pocketgallery_phone_pilot/services/knowledge_retriever.dart';

void main() {
  const chunk = PgChunk(
    id: 'c1',
    documentId: 'd1',
    sourceName: 'doc.txt',
    locator: 'text',
    ordinal: 0,
    text: 'calibration result processing response',
  );

  test('auto retrieval accepts dual channel evidence', () {
    final bundle = RetrievalBundle(
      lexicalHits: const [],
      semanticHits: const [],
      hybridHits: const [
        HybridHit(
          chunk: chunk,
          score: 0.02,
          channels: {'fts5', 'embedding'},
          lexicalRank: 1,
          semanticRank: 1,
        ),
      ],
      evidence: const [EvidenceItem(anchor: 'E1', chunk: chunk, score: 0.02)],
      lexicalOnly: false,
    );
    expect(bundle.relevantForAuto, isTrue);
  });

  test('auto retrieval rejects weak single channel noise', () {
    final bundle = RetrievalBundle(
      lexicalHits: const [],
      semanticHits: const [],
      hybridHits: const [
        HybridHit(
          chunk: chunk,
          score: 0.018,
          channels: {'fts5'},
          lexicalRank: 1,
          semanticRank: null,
        ),
      ],
      evidence: const [EvidenceItem(anchor: 'E1', chunk: chunk, score: 0.018)],
      lexicalOnly: true,
    );
    expect(bundle.relevantForAuto, isFalse);
  });

  test('semantic scope oversamples before document filtering', () async {
    final source = await File('lib/services/semantic_store.dart')
        .readAsString();
    expect(source, contains('candidateK'));
    expect(source, contains('scope.documentIds'));
    expect(
      source.indexOf('searchSimilar'),
      lessThan(source.lastIndexOf('scope.documentIds')),
    );
  });
}
