import '../core/models.dart';
import 'fts_inspector.dart';
import 'retrieval_trace.dart';

class RetrievalTraceDraft {
  const RetrievalTraceDraft({
    required this.startedAt,
    required this.timings,
    required this.lexicalHits,
    required this.semanticHits,
    required this.hybridHits,
  });

  final DateTime startedAt;
  final TraceStageTiming timings;
  final List<TraceHit> lexicalHits;
  final List<TraceHit> semanticHits;
  final List<TraceHit> hybridHits;
}

class RetrievalTraceRecorder {
  const RetrievalTraceRecorder._();

  static List<TraceHit> lexical(List<FtsInspectionHit> hits) => [
        for (final hit in hits.take(20))
          TraceHit(
            channel: hit.matchMode,
            chunkId: hit.chunk.id,
            documentId: hit.chunk.documentId,
            sourceName: hit.chunk.sourceName,
            locator: hit.chunk.locator,
            rank: hit.rank,
            rawScore: hit.rawBm25,
            normalizedScore: hit.affinity,
          ),
      ];

  static List<TraceHit> semantic(List<RetrievalHit> hits) => [
        for (final hit in hits.take(20))
          TraceHit(
            channel: 'embedding',
            chunkId: hit.chunk.id,
            documentId: hit.chunk.documentId,
            sourceName: hit.chunk.sourceName,
            locator: hit.chunk.locator,
            rank: hit.rank,
            rawScore: hit.score,
            normalizedScore: hit.score,
          ),
      ];

  static List<TraceHit> hybrid(List<HybridHit> hits) => [
        for (var i = 0; i < hits.length && i < 20; i++)
          TraceHit(
            channel: hits[i].channels.join('+'),
            chunkId: hits[i].chunk.id,
            documentId: hits[i].chunk.documentId,
            sourceName: hits[i].chunk.sourceName,
            locator: hits[i].chunk.locator,
            rank: i + 1,
            rawScore: hits[i].score,
            normalizedScore: hits[i].score,
            lexicalRank: hits[i].lexicalRank,
            semanticRank: hits[i].semanticRank,
            lexicalContribution: hits[i].lexicalContribution,
            semanticContribution: hits[i].semanticContribution,
            dualChannelBonus: hits[i].dualChannelContribution,
            exactTermBonus: hits[i].exactTermContribution,
          ),
      ];
}
