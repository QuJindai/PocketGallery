class TraceStageTiming {
  const TraceStageTiming({
    this.lexicalMs = 0,
    this.semanticMs = 0,
    this.fusionMs = 0,
    this.evidenceMs = 0,
    this.generationMs = 0,
  });

  final int lexicalMs;
  final int semanticMs;
  final int fusionMs;
  final int evidenceMs;
  final int generationMs;

  TraceStageTiming copyWith({
    int? lexicalMs,
    int? semanticMs,
    int? fusionMs,
    int? evidenceMs,
    int? generationMs,
  }) =>
      TraceStageTiming(
        lexicalMs: lexicalMs ?? this.lexicalMs,
        semanticMs: semanticMs ?? this.semanticMs,
        fusionMs: fusionMs ?? this.fusionMs,
        evidenceMs: evidenceMs ?? this.evidenceMs,
        generationMs: generationMs ?? this.generationMs,
      );

  Map<String, Object> toJson() => {
        'lexicalMs': lexicalMs,
        'semanticMs': semanticMs,
        'fusionMs': fusionMs,
        'evidenceMs': evidenceMs,
        'generationMs': generationMs,
      };

  factory TraceStageTiming.fromJson(Map<String, dynamic> json) =>
      TraceStageTiming(
        lexicalMs: (json['lexicalMs'] as num?)?.toInt() ?? 0,
        semanticMs: (json['semanticMs'] as num?)?.toInt() ?? 0,
        fusionMs: (json['fusionMs'] as num?)?.toInt() ?? 0,
        evidenceMs: (json['evidenceMs'] as num?)?.toInt() ?? 0,
        generationMs: (json['generationMs'] as num?)?.toInt() ?? 0,
      );
}

class TraceHit {
  const TraceHit({
    required this.channel,
    required this.chunkId,
    required this.documentId,
    required this.sourceName,
    required this.locator,
    required this.rank,
    required this.rawScore,
    required this.normalizedScore,
    this.lexicalRank,
    this.semanticRank,
    this.lexicalContribution,
    this.semanticContribution,
    this.dualChannelBonus,
    this.exactTermBonus,
  });

  final String channel;
  final String chunkId;
  final String documentId;
  final String sourceName;
  final String locator;
  final int rank;

  /// REAL score returned by the corresponding index/runtime whenever the
  /// channel exposes one. Null for explicitly-labelled fallback channels.
  final double? rawScore;

  /// DERIVED score when normalization is necessary for presentation.
  final double normalizedScore;
  final int? lexicalRank;
  final int? semanticRank;
  final double? lexicalContribution;
  final double? semanticContribution;
  final double? dualChannelBonus;
  final double? exactTermBonus;

  Map<String, Object?> toJson() => {
        'channel': channel,
        'chunkId': chunkId,
        'documentId': documentId,
        'sourceName': sourceName,
        'locator': locator,
        'rank': rank,
        'rawScore': rawScore,
        'normalizedScore': normalizedScore,
        'lexicalRank': lexicalRank,
        'semanticRank': semanticRank,
        'lexicalContribution': lexicalContribution,
        'semanticContribution': semanticContribution,
        'dualChannelBonus': dualChannelBonus,
        'exactTermBonus': exactTermBonus,
      };

  factory TraceHit.fromJson(Map<String, dynamic> json) => TraceHit(
        channel: json['channel'] as String,
        chunkId: json['chunkId'] as String,
        documentId: json['documentId'] as String,
        sourceName: json['sourceName'] as String,
        locator: json['locator'] as String,
        rank: (json['rank'] as num).toInt(),
        rawScore: (json['rawScore'] as num?)?.toDouble(),
        normalizedScore: (json['normalizedScore'] as num).toDouble(),
        lexicalRank: (json['lexicalRank'] as num?)?.toInt(),
        semanticRank: (json['semanticRank'] as num?)?.toInt(),
        lexicalContribution:
            (json['lexicalContribution'] as num?)?.toDouble(),
        semanticContribution:
            (json['semanticContribution'] as num?)?.toDouble(),
        dualChannelBonus: (json['dualChannelBonus'] as num?)?.toDouble(),
        exactTermBonus: (json['exactTermBonus'] as num?)?.toDouble(),
      );
}

class RetrievalTrace {
  const RetrievalTrace({
    required this.traceId,
    required this.sessionId,
    required this.query,
    required this.mode,
    required this.startedAt,
    required this.completedAt,
    required this.scopeDocumentIds,
    required this.timings,
    required this.lexicalHits,
    required this.semanticHits,
    required this.hybridHits,
    required this.evidenceAnchors,
    required this.citations,
    this.queryVectorFingerprint,
  });

  final String traceId;
  final String sessionId;
  final String query;
  final String mode;
  final DateTime startedAt;
  final DateTime completedAt;
  final Set<String> scopeDocumentIds;
  final TraceStageTiming timings;
  final List<TraceHit> lexicalHits;
  final List<TraceHit> semanticHits;
  final List<TraceHit> hybridHits;
  final List<String> evidenceAnchors;
  final List<String> citations;
  final String? queryVectorFingerprint;

  RetrievalTrace bounded({int maxHits = 20}) => RetrievalTrace(
        traceId: traceId,
        sessionId: sessionId,
        query: query,
        mode: mode,
        startedAt: startedAt,
        completedAt: completedAt,
        scopeDocumentIds: scopeDocumentIds,
        timings: timings,
        lexicalHits: lexicalHits.take(maxHits).toList(growable: false),
        semanticHits: semanticHits.take(maxHits).toList(growable: false),
        hybridHits: hybridHits.take(maxHits).toList(growable: false),
        evidenceAnchors: evidenceAnchors,
        citations: citations,
        queryVectorFingerprint: queryVectorFingerprint,
      );

  Map<String, Object?> toJson() => {
        'traceId': traceId,
        'sessionId': sessionId,
        'query': query,
        'mode': mode,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'completedAt': completedAt.toUtc().toIso8601String(),
        'scopeDocumentIds': (scopeDocumentIds.toList()..sort()),
        'timings': timings.toJson(),
        'lexicalHits': lexicalHits.map((e) => e.toJson()).toList(),
        'semanticHits': semanticHits.map((e) => e.toJson()).toList(),
        'hybridHits': hybridHits.map((e) => e.toJson()).toList(),
        'evidenceAnchors': evidenceAnchors,
        'citations': citations,
        'queryVectorFingerprint': queryVectorFingerprint,
      };

  factory RetrievalTrace.fromJson(Map<String, dynamic> json) => RetrievalTrace(
        traceId: json['traceId'] as String,
        sessionId: json['sessionId'] as String,
        query: json['query'] as String,
        mode: json['mode'] as String,
        startedAt: DateTime.parse(json['startedAt'] as String),
        completedAt: DateTime.parse(json['completedAt'] as String),
        scopeDocumentIds: (json['scopeDocumentIds'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toSet(),
        timings: TraceStageTiming.fromJson(
          (json['timings'] as Map<dynamic, dynamic>).cast<String, dynamic>(),
        ),
        lexicalHits: _hits(json['lexicalHits']),
        semanticHits: _hits(json['semanticHits']),
        hybridHits: _hits(json['hybridHits']),
        evidenceAnchors: (json['evidenceAnchors'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        citations: (json['citations'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        queryVectorFingerprint: json['queryVectorFingerprint'] as String?,
      );

  static List<TraceHit> _hits(Object? raw) =>
      (raw as List<dynamic>? ?? const [])
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => TraceHit.fromJson(e.cast<String, dynamic>()))
          .toList();
}
