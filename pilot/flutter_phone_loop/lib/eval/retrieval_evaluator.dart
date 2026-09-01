import 'retrieval_benchmark.dart';

class RetrievalMetrics {
  const RetrievalMetrics({
    required this.caseCount,
    required this.hitAt1,
    required this.hitAt3,
    required this.recallAt5,
    required this.mrr,
    required this.contextPrecision,
    this.citationAccuracy,
    this.routerAccuracy,
    this.citationGroundingRate,
  });

  final int caseCount;
  final double hitAt1;
  final double hitAt3;
  final double recallAt5;
  final double mrr;
  final double contextPrecision;
  final double? citationAccuracy;
  final double? routerAccuracy;
  final double? citationGroundingRate;
}

class RetrievalRankingComparison {
  const RetrievalRankingComparison({
    required this.pairedCaseCount,
    required this.rankingChangedCases,
    required this.top1ChangedCases,
  });

  final int pairedCaseCount;
  final int rankingChangedCases;
  final int top1ChangedCases;

  String get summary =>
      '对比 C · $rankingChangedCases/$pairedCaseCount cases 排名变化 · '
      '$top1ChangedCases top1 变化';
}

class RetrievalEvaluator {
  const RetrievalEvaluator();

  RetrievalRankingComparison compareRankings(
    List<BenchmarkCaseResult> current,
    List<BenchmarkCaseResult> alternate,
  ) {
    final alternateByCase = {
      for (final result in alternate) result.caseId: result,
    };
    var paired = 0;
    var rankingChanged = 0;
    var top1Changed = 0;

    for (final currentResult in current) {
      final alternateResult = alternateByCase[currentResult.caseId];
      if (alternateResult == null) continue;
      paired += 1;

      final currentRanking = [
        for (final hit in currentResult.hits) hit.chunkId,
      ];
      final alternateRanking = [
        for (final hit in alternateResult.hits) hit.chunkId,
      ];
      if (!_sameRanking(currentRanking, alternateRanking)) {
        rankingChanged += 1;
      }
      final currentTop1 = currentRanking.isEmpty ? null : currentRanking.first;
      final alternateTop1 = alternateRanking.isEmpty
          ? null
          : alternateRanking.first;
      if (currentTop1 != alternateTop1) top1Changed += 1;
    }

    return RetrievalRankingComparison(
      pairedCaseCount: paired,
      rankingChangedCases: rankingChanged,
      top1ChangedCases: top1Changed,
    );
  }

  RetrievalMetrics? aggregate(
    List<RetrievalBenchmarkCase> cases,
    List<BenchmarkCaseResult> results,
  ) {
    if (cases.isEmpty || results.isEmpty) return null;
    final caseById = {for (final c in cases) c.id: c};
    final valid = results.where((r) => caseById.containsKey(r.caseId)).toList();
    if (valid.isEmpty) return null;

    var hit1 = 0.0;
    var hit3 = 0.0;
    var recall5 = 0.0;
    var reciprocalRank = 0.0;
    var precision = 0.0;
    var routerCorrect = 0.0;
    var routerDenominator = 0;
    var citationGrounding = 0.0;
    var citationDenominator = 0;

    for (final result in valid) {
      final benchmark = caseById[result.caseId]!;
      final hits = result.hits;
      bool relevant(BenchmarkHit hit) => benchmark.isRelevant(hit);

      if (hits.isNotEmpty && relevant(hits.first)) hit1 += 1;
      if (hits.take(3).any(relevant)) hit3 += 1;

      final expectedCount =
          benchmark.expectedDocumentIds.length +
          benchmark.expectedChunkIds.length +
          benchmark.expectedSourceNames.length;
      if (expectedCount > 0) {
        final found = <String>{};
        for (final hit in hits.take(5)) {
          if (benchmark.expectedChunkIds.contains(hit.chunkId)) {
            found.add('c:${hit.chunkId}');
          }
          if (benchmark.expectedDocumentIds.contains(hit.documentId)) {
            found.add('d:${hit.documentId}');
          }
          if (benchmark.expectedSourceNames.contains(hit.sourceName)) {
            found.add('s:${hit.sourceName}');
          }
        }
        recall5 += (found.length / expectedCount).clamp(0.0, 1.0).toDouble();
      }

      final firstRelevant = hits.indexWhere(relevant);
      if (firstRelevant >= 0) reciprocalRank += 1 / (firstRelevant + 1);

      final top = hits.take(5).toList();
      if (top.isNotEmpty) {
        precision += top.where(relevant).length / top.length;
      }

      if (benchmark.expectedUseKnowledge != null &&
          result.routerUseKnowledge != null) {
        routerDenominator++;
        if (benchmark.expectedUseKnowledge == result.routerUseKnowledge) {
          routerCorrect += 1;
        }
      }
      final cited = result.citedChunkIds;
      if (benchmark.expectedChunkIds.isNotEmpty && cited != null) {
        citationDenominator++;
        if (cited.isNotEmpty) {
          citationGrounding +=
              cited.where(benchmark.expectedChunkIds.contains).length /
              cited.length;
        }
      }
    }

    final n = valid.length.toDouble();
    return RetrievalMetrics(
      caseCount: valid.length,
      hitAt1: hit1 / n,
      hitAt3: hit3 / n,
      recallAt5: recall5 / n,
      mrr: reciprocalRank / n,
      contextPrecision: precision / n,
      routerAccuracy: routerDenominator == 0
          ? null
          : routerCorrect / routerDenominator,
      citationGroundingRate: citationDenominator == 0
          ? null
          : citationGrounding / citationDenominator,
    );
  }

  bool _sameRanking(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
