import '../core/models.dart';
import 'okf_models.dart';
import 'okf_parser.dart';

enum OkfAfLane {
  bareModel,
  markdownControl,
  okfConcept,
  okfPassage,
  okfGraph,
  okfTrustFreshness,
}

extension OkfAfLaneInfo on OkfAfLane {
  String get code => switch (this) {
    OkfAfLane.bareModel => 'A',
    OkfAfLane.markdownControl => 'B',
    OkfAfLane.okfConcept => 'C',
    OkfAfLane.okfPassage => 'D',
    OkfAfLane.okfGraph => 'E',
    OkfAfLane.okfTrustFreshness => 'F',
  };

  String get label => switch (this) {
    OkfAfLane.bareModel => '裸模型',
    OkfAfLane.markdownControl => '普通 Markdown RAG',
    OkfAfLane.okfConcept => 'OKF Concept',
    OkfAfLane.okfPassage => 'OKF Passage',
    OkfAfLane.okfGraph => 'OKF + Graph',
    OkfAfLane.okfTrustFreshness => 'OKF + Trust/Freshness',
  };

  String get hypothesis => switch (this) {
    OkfAfLane.bareModel => '测本地模型自身，不提供任何外部知识。',
    OkfAfLane.markdownControl => '测“加知识库”本身的收益，不使用 OKF 结构。',
    OkfAfLane.okfConcept => '同样事实，按 OKF Concept 整体检索。',
    OkfAfLane.okfPassage => '在 Concept 内进一步按标题/段落渐进披露。',
    OkfAfLane.okfGraph => 'Passage 主召回后只做一跳受控关系补全。',
    OkfAfLane.okfTrustFreshness => 'Graph 之上过滤过期/废止知识并按可信度重排。',
  };
}

class OkfAfBenchmarkCase {
  const OkfAfBenchmarkCase({
    required this.id,
    required this.category,
    required this.question,
    required this.expectedAnswerFragments,
    required this.expectedSourceIds,
    required this.note,
  });

  final String id;
  final String category;
  final String question;
  final List<String> expectedAnswerFragments;
  final List<String> expectedSourceIds;
  final String note;

  bool answerMatches(String answer) {
    final normalized = _normalize(answer);
    return expectedAnswerFragments.every(
      (fragment) => normalized.contains(_normalize(fragment)),
    );
  }

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
}

const List<OkfAfBenchmarkCase> okfAfBenchmarkCases = <OkfAfBenchmarkCase>[
  OkfAfBenchmarkCase(
    id: 'single-fact-route',
    category: 'single_fact',
    question: 'X7是否经过B工序？',
    expectedAnswerFragments: <String>['不经过', 'B工序'],
    expectedSourceIds: <String>['mes://FR-Test/routes/X7/R7'],
    note: '单事实：专有车型路线，模型预训练不应知道。',
  ),
  OkfAfBenchmarkCase(
    id: 'multi-hop-bottleneck',
    category: 'multi_hop',
    question: 'X7在1线的瓶颈是什么？',
    expectedAnswerFragments: <String>['C工序'],
    expectedSourceIds: <String>[
      'mes://FR-Test/routes/X7/R7',
      'spec://FR-Test/SPEC-R19',
      'rule://FR-Test/BOTTLENECK-V1',
    ],
    note: '多跳：车型路线 + 当前工时 + 瓶颈规则。',
  ),
  OkfAfBenchmarkCase(
    id: 'version-conflict',
    category: 'version_conflict',
    question: '2026年9月5日，1线C工序应使用多少秒？',
    expectedAnswerFragments: <String>['76', '秒'],
    expectedSourceIds: <String>['spec://FR-Test/SPEC-R19'],
    note: '版本冲突：R18=83秒已废止，R19=76秒为当前版。',
  ),
  OkfAfBenchmarkCase(
    id: 'source-grounding',
    category: 'provenance',
    question: '1线C工序的76秒来自哪个规范？',
    expectedAnswerFragments: <String>['SPEC-R19'],
    expectedSourceIds: <String>['spec://FR-Test/SPEC-R19'],
    note: '来源：要求模型同时答对事实并回溯正确证据。',
  ),
];

class OkfAfEvidence {
  const OkfAfEvidence({
    required this.chunk,
    required this.conceptId,
    required this.score,
    required this.sourceIds,
    required this.trustLabel,
    required this.freshnessLabel,
    required this.graphExpanded,
  });

  final PgChunk chunk;
  final String conceptId;
  final double score;
  final Set<String> sourceIds;
  final String trustLabel;
  final String freshnessLabel;
  final bool graphExpanded;
}

class OkfAfCorpus {
  OkfAfCorpus._({required this._concepts, required this._ordinaryChunks});

  final Map<String, _AfConcept> _concepts;
  final List<_AfOrdinaryChunk> _ordinaryChunks;

  factory OkfAfCorpus.syntheticFrTest() {
    const parser = OkfParser();
    final documents = <String, String>{
      'lines/line1-r18': '''---
type: ProcessVersion
title: FR-Test 1线 R18（旧版）
status: deprecated
stale_after: 2026-09-01
sources:
  - location: spec://FR-Test/SPEC-R18
verified: human:legacy-owner
---
# 生效范围
SPEC-R18 是 FR-Test 1线的旧版本，自 2026-09-01 起由 R19 取代。

# 工位时间
A工序 = 71秒。
B工序 = 49秒。
C工序 = 83秒。

# 关联
当前版本见 [R19](line1-r19.md)。
''',
      'lines/line1-r19': '''---
type: ProcessVersion
title: FR-Test 1线 R19（当前版）
status: stable
stale_after: 2027-09-01
sources:
  - location: spec://FR-Test/SPEC-R19
verified: human:lab-expert
---
# 生效范围
SPEC-R19 自 2026-09-01 起取代 SPEC-R18，适用于 FR-Test 1线。

# 工位时间
A工序 = 71秒。
B工序 = 49秒。
C工序 = 76秒。

# 关联
车型路线见 [X7](../vehicles/x7.md)。瓶颈判断见 [规则](../rules/bottleneck.md)。
''',
      'vehicles/x7': '''---
type: Route
title: X7 检测路线
status: stable
stale_after: 2027-09-01
sources:
  - location: mes://FR-Test/routes/X7/R7
verified: human:route-owner
---
# 路线
X7 在 FR-Test 1线必须经过 A工序，然后经过 C工序。
X7 不经过 B工序。

# 关联
当前1线时间采用 [R19](../lines/line1-r19.md)。
瓶颈判断采用 [最大节拍规则](../rules/bottleneck.md)。
''',
      'rules/bottleneck': '''---
type: Playbook
title: FR-Test 瓶颈判断规则
status: stable
stale_after: 2027-09-01
sources:
  - location: rule://FR-Test/BOTTLENECK-V1
verified: human:industrial-engineer
---
# 定义
先按车型路线确定实际经过的工序。
只比较这些实际经过工序的测试时间。
测试时间最大的实际经过工序就是瓶颈。

# 关联
X7路线见 [X7](../vehicles/x7.md)，1线当前时间见 [R19](../lines/line1-r19.md)。
''',
    };

    final concepts = <String, _AfConcept>{};
    for (final entry in documents.entries) {
      final parsed = parser.parseMarkdown(
        entry.value,
        documentId: entry.key,
        sourceName: '${entry.key}.md',
        now: DateTime.utc(2026, 9, 5),
      );
      concepts[entry.key] = _AfConcept(
        id: entry.key,
        markdown: entry.value,
        body: entry.value.substring(parsed.bodyStartOffset).trim(),
        parsed: parsed,
      );
    }

    return OkfAfCorpus._(
      concepts: Map<String, _AfConcept>.unmodifiable(concepts),
      ordinaryChunks: const <_AfOrdinaryChunk>[
        _AfOrdinaryChunk(
          id: 'raw-r18',
          sourceName: 'line1-history.md',
          text:
              'FR-Test 1线旧记录 R18：A工序71秒，B工序49秒，C工序83秒；来源 SPEC-R18。'
              '该记录自2026-09-01起被R19替代。',
          sourceIds: <String>{'spec://FR-Test/SPEC-R18'},
        ),
        _AfOrdinaryChunk(
          id: 'raw-r19',
          sourceName: 'line1-history.md',
          text:
              'FR-Test 1线当前记录 R19：自2026-09-01起，A工序71秒，B工序49秒，C工序76秒；'
              '来源 SPEC-R19。',
          sourceIds: <String>{'spec://FR-Test/SPEC-R19'},
        ),
        _AfOrdinaryChunk(
          id: 'raw-x7',
          sourceName: 'routes.md',
          text: 'X7在FR-Test 1线的路线是A工序→C工序，不经过B工序；来源 MES X7 Route R7。',
          sourceIds: <String>{'mes://FR-Test/routes/X7/R7'},
        ),
        _AfOrdinaryChunk(
          id: 'raw-bottleneck',
          sourceName: 'rules.md',
          text:
              '瓶颈规则：先按车型路线确定实际经过工序，只比较这些工序，测试时间最大者为瓶颈；'
              '来源 BOTTLENECK-V1。',
          sourceIds: <String>{'rule://FR-Test/BOTTLENECK-V1'},
        ),
      ],
    );
  }
}

class OkfAfRetriever {
  OkfAfRetriever({required this.corpus, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final OkfAfCorpus corpus;
  final DateTime Function() _now;

  List<OkfAfEvidence> retrieve(
    String query, {
    required OkfAfLane lane,
    int limit = 5,
  }) {
    if (limit <= 0 || lane == OkfAfLane.bareModel) {
      return const <OkfAfEvidence>[];
    }
    return switch (lane) {
      OkfAfLane.bareModel => const <OkfAfEvidence>[],
      OkfAfLane.markdownControl => _ordinary(query, limit),
      OkfAfLane.okfConcept => _concepts(query, limit),
      OkfAfLane.okfPassage => _passages(query, limit, trustedOnly: false),
      OkfAfLane.okfGraph => _graph(query, limit, trustedOnly: false),
      OkfAfLane.okfTrustFreshness => _graph(query, limit, trustedOnly: true),
    };
  }

  List<OkfAfEvidence> _ordinary(String query, int limit) {
    final results = <OkfAfEvidence>[];
    for (final item in corpus._ordinaryChunks) {
      final score = _lexicalScore(query, item.text, item.sourceName);
      if (score <= 0) continue;
      results.add(
        OkfAfEvidence(
          chunk: PgChunk(
            id: 'ordinary:${item.id}',
            documentId: 'ordinary/${item.id}',
            sourceName: item.sourceName,
            locator: 'ordinary/${item.id}',
            ordinal: 0,
            text: item.text,
          ),
          conceptId: 'ordinary/${item.id}',
          score: score,
          sourceIds: item.sourceIds,
          trustLabel: 'none',
          freshnessLabel: 'none',
          graphExpanded: false,
        ),
      );
    }
    return _sort(results).take(limit).toList(growable: false);
  }

  List<OkfAfEvidence> _concepts(String query, int limit) {
    final results = <OkfAfEvidence>[];
    for (final concept in corpus._concepts.values) {
      final document = concept.parsed.document;
      final title = document.title ?? concept.id;
      final score = _lexicalScore(query, '$title\n${concept.body}', title);
      if (score <= 0) continue;
      results.add(
        OkfAfEvidence(
          chunk: PgChunk(
            id: 'concept:${concept.id}',
            documentId: concept.id,
            sourceName: document.sourceName,
            locator: 'okf://${concept.id}',
            ordinal: 0,
            text: _conceptPromptText(concept, includeTrust: false),
          ),
          conceptId: concept.id,
          score: score,
          sourceIds: _sourceIds(concept),
          trustLabel: document.trustTier.name,
          freshnessLabel: document.freshness.name,
          graphExpanded: false,
        ),
      );
    }
    return _sort(results).take(limit).toList(growable: false);
  }

  List<OkfAfEvidence> _passages(
    String query,
    int limit, {
    required bool trustedOnly,
  }) {
    final results = <OkfAfEvidence>[];
    for (final concept in corpus._concepts.values) {
      if (trustedOnly && !_eligible(concept)) continue;
      final document = concept.parsed.document;
      final title = document.title ?? concept.id;
      for (final passage in _splitPassages(concept)) {
        var score = _lexicalScore(
          query,
          '$title\n${passage.text}',
          '$title ${passage.heading}',
        );
        if (score <= 0) continue;
        if (trustedOnly) score *= _trustBoost(document.trustTier);
        results.add(
          OkfAfEvidence(
            chunk: PgChunk(
              id: 'passage:${concept.id}:${passage.ordinal}',
              documentId: concept.id,
              sourceName: document.sourceName,
              locator: 'okf://${concept.id}#${passage.heading}',
              ordinal: passage.ordinal,
              text: _passagePromptText(
                concept,
                passage,
                includeTrust: trustedOnly,
              ),
            ),
            conceptId: concept.id,
            score: score,
            sourceIds: _sourceIds(concept),
            trustLabel: document.trustTier.name,
            freshnessLabel: document.freshness.name,
            graphExpanded: false,
          ),
        );
      }
    }
    return _sort(results).take(limit).toList(growable: false);
  }

  List<OkfAfEvidence> _graph(
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

    final byConcept = <String, OkfAfEvidence>{};
    for (final item in base) {
      final current = byConcept[item.conceptId];
      if (current == null || item.score > current.score) {
        byConcept[item.conceptId] = item;
      }
    }

    final seeds = base.take(3).map((item) => item.conceptId).toSet();
    for (final seed in seeds) {
      for (final neighborId in _neighbors(seed)) {
        final concept = corpus._concepts[neighborId];
        if (concept == null || (trustedOnly && !_eligible(concept))) continue;
        final passages = _splitPassages(concept);
        if (passages.isEmpty) continue;
        var best = passages.first;
        var bestScore = _lexicalScore(
          query,
          best.text,
          '${concept.parsed.document.title ?? concept.id} ${best.heading}',
        );
        for (final passage in passages.skip(1)) {
          final score = _lexicalScore(
            query,
            passage.text,
            '${concept.parsed.document.title ?? concept.id} ${passage.heading}',
          );
          if (score > bestScore) {
            best = passage;
            bestScore = score;
          }
        }
        var score = bestScore + 0.8;
        if (trustedOnly) {
          score *= _trustBoost(concept.parsed.document.trustTier);
        }
        final candidate = OkfAfEvidence(
          chunk: PgChunk(
            id: 'graph:${concept.id}:${best.ordinal}',
            documentId: concept.id,
            sourceName: concept.parsed.document.sourceName,
            locator: 'okf://${concept.id}#${best.heading}',
            ordinal: best.ordinal,
            text: _passagePromptText(concept, best, includeTrust: trustedOnly),
          ),
          conceptId: concept.id,
          score: score,
          sourceIds: _sourceIds(concept),
          trustLabel: concept.parsed.document.trustTier.name,
          freshnessLabel: concept.parsed.document.freshness.name,
          graphExpanded: true,
        );
        final current = byConcept[concept.id];
        if (current == null || candidate.score > current.score) {
          byConcept[concept.id] = candidate;
        }
      }
    }

    return _sort(byConcept.values.toList()).take(limit).toList(growable: false);
  }

  bool _eligible(_AfConcept concept) {
    final document = concept.parsed.document;
    if (document.freshness == OkfFreshness.deprecated ||
        document.freshness == OkfFreshness.stale) {
      return false;
    }
    final staleAfter = document.staleAfter;
    if (staleAfter != null && !_now().toUtc().isBefore(staleAfter)) {
      return false;
    }
    return true;
  }

  Set<String> _neighbors(String conceptId) {
    final neighbors = <String>{};
    final concept = corpus._concepts[conceptId];
    if (concept == null) return neighbors;
    for (final link in concept.parsed.links) {
      final resolved = _resolveLink(conceptId, link.target);
      if (resolved != null) neighbors.add(resolved);
    }
    for (final other in corpus._concepts.values) {
      if (other.id == conceptId) continue;
      for (final link in other.parsed.links) {
        if (_resolveLink(other.id, link.target) == conceptId) {
          neighbors.add(other.id);
          break;
        }
      }
    }
    return neighbors;
  }

  String? _resolveLink(String fromId, String target) {
    var value = target.split('#').first.trim();
    if (value.isEmpty ||
        RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:').hasMatch(value) ||
        value.startsWith('/')) {
      return null;
    }
    final parts = fromId.split('/');
    final resolved = parts.length > 1
        ? <String>[...parts.take(parts.length - 1)]
        : <String>[];
    for (final raw in value.split('/')) {
      final part = raw.trim();
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (resolved.isNotEmpty) resolved.removeLast();
      } else {
        resolved.add(part);
      }
    }
    if (resolved.isEmpty) return null;
    var id = resolved.join('/');
    if (id.endsWith('.md')) id = id.substring(0, id.length - 3);
    return corpus._concepts.containsKey(id) ? id : null;
  }

  List<_AfPassage> _splitPassages(_AfConcept concept) {
    final passages = <_AfPassage>[];
    var heading = concept.parsed.document.title ?? concept.id;
    final buffer = <String>[];

    void flush() {
      final text = buffer.join('\n').trim();
      if (text.isEmpty) return;
      passages.add(
        _AfPassage(heading: heading, ordinal: passages.length, text: text),
      );
      buffer.clear();
    }

    for (final line in concept.body.split(RegExp(r'\r?\n'))) {
      final match = RegExp(r'^#{1,6}\s+(.+)$').firstMatch(line.trim());
      if (match != null) {
        flush();
        heading = match.group(1)!.trim();
      } else if (line.trim().isEmpty) {
        flush();
      } else {
        buffer.add(line);
      }
    }
    flush();
    return passages;
  }

  String _conceptPromptText(_AfConcept concept, {required bool includeTrust}) {
    final document = concept.parsed.document;
    return <String>[
      'TITLE: ${document.title ?? concept.id}',
      'TYPE: ${document.type}',
      'SOURCE: ${_sourceIds(concept).join(', ')}',
      if (includeTrust) 'TRUST: ${document.trustTier.name}',
      if (includeTrust) 'FRESHNESS: ${document.freshness.name}',
      if (includeTrust && document.status != null) 'STATUS: ${document.status}',
      concept.body,
    ].join('\n');
  }

  String _passagePromptText(
    _AfConcept concept,
    _AfPassage passage, {
    required bool includeTrust,
  }) {
    final document = concept.parsed.document;
    return <String>[
      'TITLE: ${document.title ?? concept.id}',
      'SECTION: ${passage.heading}',
      'SOURCE: ${_sourceIds(concept).join(', ')}',
      if (includeTrust) 'TRUST: ${document.trustTier.name}',
      if (includeTrust) 'FRESHNESS: ${document.freshness.name}',
      if (includeTrust && document.status != null) 'STATUS: ${document.status}',
      passage.text,
    ].join('\n');
  }

  Set<String> _sourceIds(_AfConcept concept) => concept.parsed.document.sources
      .map((source) => source.location)
      .where((value) => value.isNotEmpty)
      .toSet();

  double _trustBoost(OkfTrustTier tier) => switch (tier) {
    OkfTrustTier.verified => 1.18,
    OkfTrustTier.generated => 1.08,
    OkfTrustTier.provenance => 1.04,
    OkfTrustTier.typeOnly => 1.0,
  };

  List<OkfAfEvidence> _sort(List<OkfAfEvidence> values) {
    values.sort((left, right) {
      final score = right.score.compareTo(left.score);
      if (score != 0) return score;
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
      if (haystack.contains(term)) score += term.length >= 2 ? 1.4 : 0.4;
      if (titleText.contains(term)) score += term.length >= 2 ? 0.8 : 0.2;
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
      if (runes.length >= 2 && runes.length <= 10) {
        out.add(String.fromCharCodes(runes));
      }
      for (var index = 0; index + 1 < runes.length; index++) {
        out.add(String.fromCharCodes(runes.sublist(index, index + 2)));
      }
      for (var index = 0; index + 2 < runes.length; index++) {
        out.add(String.fromCharCodes(runes.sublist(index, index + 3)));
      }
    }
    out.removeAll(const <String>{'是否', '什么', '多少', '哪个', '应该', '使用'});
    return out;
  }
}

class _AfConcept {
  const _AfConcept({
    required this.id,
    required this.markdown,
    required this.body,
    required this.parsed,
  });

  final String id;
  final String markdown;
  final String body;
  final OkfParseResult parsed;
}

class _AfOrdinaryChunk {
  const _AfOrdinaryChunk({
    required this.id,
    required this.sourceName,
    required this.text,
    required this.sourceIds,
  });

  final String id;
  final String sourceName;
  final String text;
  final Set<String> sourceIds;
}

class _AfPassage {
  const _AfPassage({
    required this.heading,
    required this.ordinal,
    required this.text,
  });

  final String heading;
  final int ordinal;
  final String text;
}
