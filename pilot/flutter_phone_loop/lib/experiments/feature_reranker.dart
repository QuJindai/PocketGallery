import 'dart:collection';

class RerankFeatureVector {
  const RerankFeatureVector({
    required this.normalizedLexicalAffinity,
    required this.cosine,
    required this.dualChannelAgreement,
    required this.queryWindowCoverage,
    required this.headingMatch,
    required this.exactTermMatch,
    required this.sourceDiversity,
  });

  final double normalizedLexicalAffinity;
  final double cosine;
  final double dualChannelAgreement;
  final double queryWindowCoverage;
  final double headingMatch;
  final double exactTermMatch;
  final double sourceDiversity;
}

class RerankFeatureScore {
  RerankFeatureScore({
    required this.score,
    required Map<String, double> contributions,
  }) : contributions = UnmodifiableMapView(contributions);

  final double score;
  final Map<String, double> contributions;
}

class FeatureRerankInput {
  const FeatureRerankInput({
    required this.candidateId,
    required this.chunkId,
    required this.documentId,
    required this.baseRank,
    required this.features,
  });

  final String candidateId;
  final String chunkId;
  final String documentId;
  final int baseRank;
  final RerankFeatureVector features;
}

class FeatureRerankResult {
  const FeatureRerankResult({
    required this.input,
    required this.rank,
    required this.scored,
  });

  final FeatureRerankInput input;
  final int rank;
  final RerankFeatureScore scored;
}

class FeatureReranker {
  const FeatureReranker();

  static const _weights = <String, double>{
    'normalized_lexical': 0.20,
    'cosine': 0.30,
    'dual_channel': 0.15,
    'query_coverage': 0.10,
    'heading_match': 0.10,
    'exact_term': 0.10,
    'source_diversity': 0.05,
  };

  RerankFeatureScore score(RerankFeatureVector features) {
    final values = <String, double>{
      'normalized_lexical': features.normalizedLexicalAffinity,
      'cosine': features.cosine,
      'dual_channel': features.dualChannelAgreement,
      'query_coverage': features.queryWindowCoverage,
      'heading_match': features.headingMatch,
      'exact_term': features.exactTermMatch,
      'source_diversity': features.sourceDiversity,
    };
    final contributions = <String, double>{};
    var total = 0.0;
    for (final entry in _weights.entries) {
      final value = (values[entry.key] ?? 0).clamp(0.0, 1.0).toDouble();
      final contribution = value * entry.value;
      contributions[entry.key] = contribution;
      total += contribution;
    }
    return RerankFeatureScore(score: total, contributions: contributions);
  }

  List<FeatureRerankResult> rerank(List<FeatureRerankInput> inputs) {
    final scored =
        <({FeatureRerankInput input, RerankFeatureScore score})>[
          for (final input in inputs)
            (input: input, score: score(input.features)),
        ]..sort((left, right) {
          final scoreOrder = right.score.score.compareTo(left.score.score);
          if (scoreOrder != 0) return scoreOrder;
          final rankOrder = left.input.baseRank.compareTo(right.input.baseRank);
          if (rankOrder != 0) return rankOrder;
          return left.input.chunkId.compareTo(right.input.chunkId);
        });
    return <FeatureRerankResult>[
      for (var index = 0; index < scored.length; index++)
        FeatureRerankResult(
          input: scored[index].input,
          rank: index + 1,
          scored: scored[index].score,
        ),
    ];
  }

  RerankFeatureVector extract({
    required String query,
    required String chunkText,
    required String? heading,
    required double lexicalAffinity,
    required double cosine,
    required bool dualChannel,
    required bool sourceIsNew,
  }) {
    final terms = _terms(query);
    final lowerChunk = chunkText.toLowerCase();
    final lowerHeading = (heading ?? '').toLowerCase();
    final matched = terms.where(lowerChunk.contains).length;
    final headingMatched = terms.where(lowerHeading.contains).length;
    final coverage = terms.isEmpty ? 0.0 : matched / terms.length;
    return RerankFeatureVector(
      normalizedLexicalAffinity: lexicalAffinity,
      cosine: cosine.clamp(0.0, 1.0).toDouble(),
      dualChannelAgreement: dualChannel ? 1 : 0,
      queryWindowCoverage: coverage,
      headingMatch: terms.isEmpty ? 0 : headingMatched / terms.length,
      exactTermMatch: terms.any(lowerChunk.contains) ? 1 : 0,
      sourceDiversity: sourceIsNew ? 1 : 0,
    );
  }

  List<String> _terms(String query) => query
      .toLowerCase()
      .split(RegExp(r'[\s，。；、,.;:：!?！？()\[\]{}]+'))
      .map((term) => term.trim())
      .where((term) => term.length >= 2)
      .toSet()
      .toList(growable: false);
}
