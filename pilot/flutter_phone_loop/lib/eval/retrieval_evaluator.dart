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
  });

  final int caseCount;
  final double hitAt1;
  final double hitAt3;
  final double recallAt5;
  final double mrr;
  final double contextPrecision;
  final double? citationAccuracy;
}

class RetrievalEvaluator {
  const RetrievalEvaluator();

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

    for (final result in valid) {
      final benchmark = caseById[result.caseId]!;
      final hits = result.hits;
      bool relevant(BenchmarkHit hit) => benchmark.isRelevant(hit);

      if (hits.isNotEmpty && relevant(hits.first)) hit1 += 1;
      if (hits.take(3).any(relevant)) hit3 += 1;

      final expectedCount = benchmark.expectedDocumentIds.length +
          benchmark.expectedSourceNames.length;
      if (expectedCount > 0) {
        final found = <String>{};
        for (final hit in hits.take(5)) {
          if (benchmark.expectedDocumentIds.contains(hit.documentId)) {
            found.add('d:${hit.documentId}');
          }
          if (benchmark.expectedSourceNames.contains(hit.sourceName)) {
            found.add('s:${hit.sourceName}');
          }
        }
        recall5 += (found.length / expectedCount).clamp(0, 1);
      }

      final firstRelevant = hits.indexWhere(relevant);
      if (firstRelevant >= 0) reciprocalRank += 1 / (firstRelevant + 1);

      final top = hits.take(5).toList();
      if (top.isNotEmpty) {
        precision += top.where(relevant).length / top.length;
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
    );
  }
}
