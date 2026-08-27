class PgChunk {
  const PgChunk({
    required this.id,
    required this.documentId,
    required this.sourceName,
    required this.locator,
    required this.ordinal,
    required this.text,
  });

  final String id;
  final String documentId;
  final String sourceName;
  final String locator;
  final int ordinal;
  final String text;
}

class ImportedDocument {
  const ImportedDocument({
    required this.documentId,
    required this.sourceName,
    required this.sha256,
    required this.chunks,
  });

  final String documentId;
  final String sourceName;
  final String sha256;
  final List<PgChunk> chunks;
}

class KnowledgeDocument {
  const KnowledgeDocument({
    required this.documentId,
    required this.sourceName,
    required this.sha256,
    required this.chunkCount,
  });

  final String documentId;
  final String sourceName;
  final String sha256;
  final int chunkCount;

  bool get textAvailable => chunkCount > 0;
}

class RetrievalHit {
  const RetrievalHit({
    required this.chunk,
    required this.score,
    required this.channel,
    required this.rank,
  });

  final PgChunk chunk;
  final double score;
  final String channel;
  final int rank;
}

class HybridHit {
  const HybridHit({
    required this.chunk,
    required this.score,
    required this.channels,
    required this.lexicalRank,
    required this.semanticRank,
  });

  final PgChunk chunk;
  final double score;
  final Set<String> channels;
  final int? lexicalRank;
  final int? semanticRank;
}

class EvidenceItem {
  const EvidenceItem({
    required this.anchor,
    required this.chunk,
    required this.score,
  });

  final String anchor;
  final PgChunk chunk;
  final double score;
}

class KnowledgeAnswer {
  const KnowledgeAnswer({
    required this.answer,
    required this.evidence,
    required this.citedAnchors,
    required this.lexicalHits,
    required this.semanticHits,
    required this.hybridHits,
  });

  final String answer;
  final List<EvidenceItem> evidence;
  final List<String> citedAnchors;
  final List<RetrievalHit> lexicalHits;
  final List<RetrievalHit> semanticHits;
  final List<HybridHit> hybridHits;
}

class GateResult {
  const GateResult(this.name, this.passed, this.detail);
  final String name;
  final bool passed;
  final String detail;

  Map<String, Object> toJson() => {
        'name': name,
        'passed': passed,
        'detail': detail,
      };
}
