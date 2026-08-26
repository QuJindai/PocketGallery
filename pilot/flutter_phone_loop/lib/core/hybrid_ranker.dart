import 'models.dart';

class HybridRanker {
  const HybridRanker({
    this.rrfK = 60,
    this.lexicalWeight = 1.0,
    this.semanticWeight = 1.15,
    this.dualChannelBonus = 0.035,
  });

  final int rrfK;
  final double lexicalWeight;
  final double semanticWeight;
  final double dualChannelBonus;

  List<HybridHit> fuse({
    required String query,
    required List<RetrievalHit> lexical,
    required List<RetrievalHit> semantic,
    int limit = 8,
  }) {
    final byId = <String, _Accumulator>{};

    for (var i = 0; i < lexical.length; i++) {
      final hit = lexical[i];
      final a = byId.putIfAbsent(hit.chunk.id, () => _Accumulator(hit.chunk));
      a.lexicalRank = i + 1;
      a.channels.add('fts5');
      a.score += lexicalWeight / (rrfK + i + 1);
      a.score += 0.018 * hit.score.clamp(0.0, 1.0).toDouble();
    }
    for (var i = 0; i < semantic.length; i++) {
      final hit = semantic[i];
      final a = byId.putIfAbsent(hit.chunk.id, () => _Accumulator(hit.chunk));
      a.semanticRank = i + 1;
      a.channels.add('embedding');
      a.score += semanticWeight / (rrfK + i + 1);
      a.score += 0.026 * hit.score.clamp(0.0, 1.0).toDouble();
    }

    // Cheap deterministic rerank: exact engineering identifiers and query terms
    // get a small boost. This never replaces embeddings; it only reranks the
    // already-fused candidates.
    final terms = _terms(query);
    for (final a in byId.values) {
      if (a.channels.length > 1) a.score += dualChannelBonus;
      final lower = a.chunk.text.toLowerCase();
      var matched = 0;
      for (final term in terms) {
        if (lower.contains(term)) matched++;
      }
      if (terms.isNotEmpty) {
        a.score += 0.025 * (matched / terms.length);
      }
    }

    final list = byId.values.toList()
      ..sort((a, b) {
        final scoreCmp = b.score.compareTo(a.score);
        if (scoreCmp != 0) return scoreCmp;
        return a.chunk.id.compareTo(b.chunk.id);
      });

    return list.take(limit).map((a) => HybridHit(
      chunk: a.chunk,
      score: a.score,
      channels: Set.unmodifiable(a.channels),
      lexicalRank: a.lexicalRank,
      semanticRank: a.semanticRank,
    )).toList();
  }

  List<String> _terms(String query) {
    final normalized = query.toLowerCase();
    final raw = normalized
        .split(RegExp(r'[\s，。；、,.;:：!?！？()\[\]{}]+'))
        .where((e) => e.trim().length >= 2)
        .toSet()
        .toList();
    final identifiers = RegExp(r'[a-z0-9][a-z0-9_.:/+-]{2,}', caseSensitive: false)
        .allMatches(normalized)
        .map((m) => m.group(0)!)
        .toSet();
    return {...raw, ...identifiers}.take(16).toList();
  }
}

class _Accumulator {
  _Accumulator(this.chunk);
  final PgChunk chunk;
  double score = 0;
  final Set<String> channels = {};
  int? lexicalRank;
  int? semanticRank;
}
