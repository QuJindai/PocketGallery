import 'package:flutter_test/flutter_test.dart';

import 'package:pocketgallery_phone_pilot/experiments/retrieval_strategy.dart';
import 'package:pocketgallery_phone_pilot/lineage/lineage_models.dart';

void main() {
  test('R4.6-C strategy registry freezes active control and shadow variants', () {
    expect(
      RetrievalStrategies.all.map((strategy) => strategy.id),
      containsAll(<String>[
        'active.r45-body-hybrid',
        'shadow.heading-body-multivector',
        'shadow.sentence-parent-child',
        'rerank.features-v1',
        'parent-child-v1',
        'evidence.dynamic-v1',
      ]),
    );

    final active = RetrievalStrategies.byId('active.r45-body-hybrid');
    expect(active.lane, RetrievalLane.active);
    expect(active.representations, {EmbeddingRepresentation.body});
    expect(active.onDemand, isFalse);
    expect(active.rerankPolicy, ExperimentRerankPolicy.none);

    final heading = RetrievalStrategies.byId(
      'shadow.heading-body-multivector',
    );
    expect(heading.lane, RetrievalLane.shadow);
    expect(
      heading.representations,
      {EmbeddingRepresentation.body, EmbeddingRepresentation.heading},
    );
    expect(heading.parentChildPolicy, ParentChildPolicy.headingToChunk);
    expect(heading.onDemand, isTrue);

    final sentence = RetrievalStrategies.byId(
      'shadow.sentence-parent-child',
    );
    expect(sentence.lane, RetrievalLane.shadow);
    expect(sentence.representations, {EmbeddingRepresentation.sentence});
    expect(sentence.parentChildPolicy, ParentChildPolicy.sentenceToChunk);
    expect(sentence.maxSentenceRepresentationsPerChunk, 4);

    expect(
      () => RetrievalStrategies.byId('missing.strategy'),
      throwsArgumentError,
    );
  });
}
