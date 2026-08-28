import '../core/models.dart';

class FtsInspectionHit {
  const FtsInspectionHit({
    required this.chunk,
    required this.rank,
    required this.rawBm25,
    required this.affinity,
    required this.snippet,
    required this.matchedTerms,
    required this.matchMode,
  });

  final PgChunk chunk;
  final int rank;

  /// REAL SQLite bm25() value. Null when the exact short-CJK fallback is used
  /// because trigram FTS5 does not index two-character terms.
  final double? rawBm25;

  /// DERIVED presentation affinity in [0, 1].
  final double affinity;
  final String snippet;
  final List<String> matchedTerms;
  final String matchMode;
}

class FtsInspectionResult {
  const FtsInspectionResult({
    required this.query,
    required this.normalizedQuery,
    required this.hits,
    required this.diagnostics,
  });

  final String query;
  final String normalizedQuery;
  final List<FtsInspectionHit> hits;
  final String diagnostics;
}
