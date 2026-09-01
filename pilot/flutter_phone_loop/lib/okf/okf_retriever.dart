import '../core/models.dart';
import 'okf_models.dart';
import 'okf_parser.dart';

enum OkfLabLane {
  bareModel,
  ordinaryLexical,
  okfConcept,
  okfPassage,
  okfGraph,
  okfTrustFreshness,
}

extension OkfLabLaneInfo on OkfLabLane {
  String get code => switch (this) {
        OkfLabLane.bareModel => 'A',
        OkfLabLane.ordinaryLexical => 'B',
        OkfLabLane.okfConcept => 'C',
        OkfLabLane.okfPassage => 'D',
        OkfLabLane.okfGraph => 'E',
        OkfLabLane.okfTrustFreshness => 'F',
      };

  String get label => switch (this) {
        OkfLabLane.bareModel => '裸模型',
        OkfLabLane.ordinaryLexical => '普通词法 RAG',
        OkfLabLane.okfConcept => 'OKF Concept',
        OkfLabLane.okfPassage => 'OKF Passage',
        OkfLabLane.okfGraph => 'OKF + Graph',
        OkfLabLane.okfTrustFreshness => 'OKF + Trust/Freshness',
      };

  String get detail => switch (this) {
        OkfLabLane.bareModel => '不提供外部知识，观察本地模型自身能力。',
        OkfLabLane.ordinaryLexical => '同一事实内容，普通文本切片，不读取 OKF 元数据。',
        OkfLabLane.okfConcept => '按 OKF concept 检索完整知识对象。',
        OkfLabLane.okfPassage => 'concept 内按标题/段落做更细粒度检索。',
        OkfLabLane.okfGraph => 'Passage 主召回后，仅做一跳受控关系扩展。',
        OkfLabLane.okfTrustFreshness => 'Graph 之上过滤 deprecated/stale，并按验证等级重排。',
      };
}

class OkfLabRetrievalResult {
  const OkfLabRetrievalResult({
    required this.chunk,
    required this.conceptId,
    required this.score,
    required this.sourceIds,
    required this.trustTier,
    required this.status,
    required this.graphExpanded,
  });

  final PgChunk chunk;
  final String conceptId;
  final double score;
  final Set<String> sourceIds;
  final OkfTrustTier? trustTier;
  final OkfStatus? status;
  final bool graphExpanded;
}

class OkfLabRetriever {
  OkfLabRetriever({
    required this.bundle,
    required this.ordinaryChunks,
    DateTime Function()? clock,
    this._parser = const OkfParser(),
  }) : _clock = clock ?? DateTime.now;

  final OkfBundle bundle;
  final List<OkfOrdinaryChunk> ordinaryChunks;
  final DateTime Function() _clock;
  final OkfParser _parser;

  List<OkfLabRetrievalResult> retrieve(
    String query, {
    required OkfLabLane lane,
    int limit = 5,
  }) {
    if (limit <= 0) return const <OkfLabRetrievalResult>[];
    switch (lane) {
      case OkfLabLane.bareModel:
        return const <OkfLabRetrievalResult>[];
      case OkfLabLane.ordinaryLexical:
        return _ordinary(query, limit);
      case OkfLabLane.okfConcept:
        return _concepts(query, limit, trustedOnly: false);
      case OkfLabLane.okfPassage:
        return _passages(query, limit, trustedOnly: false);
      case OkfLabLane.okfGraph:
        return _graph(query, limit, trustedOnly: false);
      case OkfLabLane.okfTrustFreshness:
        return _graph(query, limit, trustedOnly: true);
    }
  }

  List<OkfLabRetrievalResult> _ordinary(String query, int limit) {
    final scored = <_ScoredOrdinary>[];
    for (final item in ordinaryChunks) {
      final score = _lexicalScore(query, item.text, item.sourceName);
      if (score <= 0) continue;
      scored.add(_ScoredOrdinary(item: item, score: score));
    }
    scored.sort((left, right) {
      final order = right.score.compareTo(left.score);
      if (order != 0) return order;
      return left.item.id.compareTo(right.item.id);
    });
    return <OkfLabRetrievalResult>[
      for (final item in scored.take(limit))
        OkfLabRetrievalResult(
          chunk: item.item.toChunk(),
          conceptId: item.item.documentId,
          score: item.score,
          sourceIds: const <String>{},
          trustTier: null,
          status: null,
          graphExpanded: false,
        ),
    ];
  }

  List<OkfLabRetrievalResult> _concepts(
    String query,
    int limit, {
    required bool trustedOnly,
  }) {
    final scored = <OkfLabRetrievalResult>[];
    for (final concept in bundle.concepts.values) {
      if (!_eligible(concept, trustedOnly: trustedOnly)) continue;
      final text = [
        concept.title,
        concept.description,
        concept.tags.join(' '),
        concept.body,
      ].join('\n');
      var score = _lexicalScore(query, text, '${concept.title} ${concept.description}');
      if (score <= 0) continue;
      if (trustedOnly) score *= _trustBoost(concept);
      scored.add(OkfLabRetrievalResult(
        chunk: PgChunk(
          id: 'okf-concept:${concept.id}',
          documentId: concept.id,
          sourceName: concept.title,
          locator: 'okf://${concept.id}',
          ordinal: 0,
          text: '${concept.title}\n${concept.description}\n${concept.body}'.trim(),
        ),
        conceptId: concept.id,
        score: score,
        sourceIds: concept.sourceIds,
        trustTier: concept.trustTier,
        status: concept.effectiveStatus,
        graphExpanded: false,
      ));
    }
    return _sorted(scored).take(limit).toList(growable: false);
  }

  List<OkfLabRetrievalResult> _passages(
    String query,
    int limit, {
    required bool trustedOnly,
  }) {
    final scored = <OkfLabRetrievalResult>[];
    for (final concept in bundle.concepts.values) {
      if (!_eligible(concept, trustedOnly: trustedOnly)) continue;
      for (final passage in _parser.passages(concept)) {
        var score = _lexicalScore(
          query,
          '${concept.title}\n${concept.description}\n${passage.text}',
          '${concept.title} ${passage.heading}',
        );
        if (score <= 0) continue;
        if (trustedOnly) score *= _trustBoost(concept);
        scored.add(OkfLabRetrievalResult(
          chunk: PgChunk(
            id: 'okf-passage:${concept.id}:${passage.ordinal}',
            documentId: concept.id,
            sourceName: concept.title,
            locator: 'okf://${concept.id}#${passage.heading}',
            ordinal: passage.ordinal,
            text: passage.text,
          ),
          conceptId: concept.id,
          score: score,
          sourceIds: concept.sourceIds,
          trustTier: concept.trustTier,
          status: concept.effectiveStatus,
          graphExpanded: false,
        ));
      }
    }
    return _sorted(scored).take(limit).toList(growable: false);
  }

  List<OkfLabRetrievalResult> _graph(
    String query,
    int limit, {
    required bool trustedOnly,
  }) {
    final base = _passages(
      query,
      limit < 4 ? 4 : limit,
      trustedOnly: trustedOnly,
    );
    if (base.isEmpty) return base;
    final byChunk = <String, OkfLabRetrievalResult>{
      for (final item in base) item.chunk.id: item,
    };
    final seedConcepts = base.take(3).map((item) => item.conceptId).toSet();
    for (final seed in seedConcepts) {
      for (final neighborId in bundle.neighbors(seed)) {
        final concept = bundle[neighborId];
        if (concept == null || !_eligible(concept, trustedOnly: trustedOnly)) {
          continue;
        }
        final passages = _parser.passages(concept);
        if (passages.isEmpty) continue;
        var best = passages.first;
        var bestScore = _lexicalScore(
          query,
          '${concept.title}\n${concept.description}\n${best.text}',
          '${concept.title} ${best.heading}',
        );
        for (final passage in passages.skip(1)) {
          final score = _lexicalScore(
            query,
            '${concept.title}\n${concept.description}\n${passage.text}',
            '${concept.title} ${passage.heading}',
          );
          if (score > bestScore) {
            best = passage;
            bestScore = score;
          }
        }
        var score = bestScore + 1.0;
        if (trustedOnly) score *= _trustBoost(concept);
        final item = OkfLabRetrievalResult(
          chunk: PgChunk(
            id: 'okf-graph:${concept.id}:${best.ordinal}',
            documentId: concept.id,
            sourceName: concept.title,
            locator: 'okf://${concept.id}#${best.heading}',
            ordinal: best.ordinal,
            text: best.text,
          ),
          conceptId: concept.id,
          score: score,
          sourceIds: concept.sourceIds,
          trustTier: concept.trustTier,
          status: concept.effectiveStatus,
          graphExpanded: true,
        );
        final current = byChunk[item.chunk.id];
        if (current == null || item.score > current.score) {
          byChunk[item.chunk.id] = item;
        }
      }
    }

    final byConcept = <String, OkfLabRetrievalResult>{};
    for (final item in byChunk.values) {
      final current = byConcept[item.conceptId];
      if (current == null ||
          item.score > current.score ||
          (item.score == current.score &&
              item.chunk.id.compareTo(current.chunk.id) < 0)) {
        byConcept[item.conceptId] = item;
      }
    }
    return _sorted(byConcept.values.toList())
        .take(limit)
        .toList(growable: false);
  }

  bool _eligible(OkfConcept concept, {required bool trustedOnly}) {
    if (!trustedOnly) return true;
    if (concept.effectiveStatus == OkfStatus.deprecated) return false;
    if (concept.isStaleAt(_clock().toUtc())) return false;
    return true;
  }

  double _trustBoost(OkfConcept concept) => switch (concept.trustTier) {
        OkfTrustTier.humanReviewed => 1.18,
        OkfTrustTier.machineConfirmed => 1.08,
        OkfTrustTier.unverified => 1.0,
      };

  List<OkfLabRetrievalResult> _sorted(
    List<OkfLabRetrievalResult> values,
  ) {
    values.sort((left, right) {
      final scoreOrder = right.score.compareTo(left.score);
      if (scoreOrder != 0) return scoreOrder;
      return left.chunk.id.compareTo(right.chunk.id);
    });
    return values;
  }

  double _lexicalScore(String query, String text, String title) {
    final terms = _terms(query);
    if (terms.isEmpty) return 0;
    final haystack = text.toLowerCase();
    final titleText = title.toLowerCase();
    var score = 0.0;
    for (final term in terms) {
      final normalized = term.toLowerCase();
      if (normalized.isEmpty) continue;
      final weight = normalized.runes.length >= 2 ? 1.5 : 0.55;
      if (haystack.contains(normalized)) score += weight;
      if (titleText.contains(normalized)) score += weight * 0.65;
    }
    final normalizedQuery = query.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (normalizedQuery.length >= 4 &&
        haystack.replaceAll(RegExp(r'\s+'), '').contains(normalizedQuery)) {
      score += 4.0;
    }
    return score;
  }

  Set<String> _terms(String query) {
    final out = <String>{};
    for (final match in RegExp(r'[A-Za-z0-9_.-]+').allMatches(query)) {
      final value = match.group(0)!.toLowerCase();
      if (value.length > 1 || RegExp(r'[0-9]').hasMatch(value)) out.add(value);
    }
    for (final match in RegExp(r'[\u4e00-\u9fff]+').allMatches(query)) {
      final runes = match.group(0)!.runes.toList();
      if (runes.length >= 2 && runes.length <= 8) {
        out.add(String.fromCharCodes(runes));
      }
      for (var index = 0; index + 1 < runes.length; index++) {
        out.add(String.fromCharCodes(runes.sublist(index, index + 2)));
      }
      for (var index = 0; index + 2 < runes.length; index++) {
        out.add(String.fromCharCodes(runes.sublist(index, index + 3)));
      }
    }
    const stop = <String>{
      '是否',
      '多少',
      '什么',
      '哪个',
      '来自',
      '使用',
      '应该',
      '工序',
      '2026',
    };
    out.removeAll(stop);
    return out;
  }
}

class _ScoredOrdinary {
  const _ScoredOrdinary({required this.item, required this.score});
  final OkfOrdinaryChunk item;
  final double score;
}
