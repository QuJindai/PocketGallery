import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'lineage_models.dart';

abstract final class LineageIds {
  static String _id(String prefix, String canonical) {
    final digest = sha256.convert(utf8.encode('r46|$canonical')).toString();
    return '$prefix-${digest.substring(0, 24)}';
  }

  static String embeddingId({
    required String sourceKind,
    required String sourceId,
    required EmbeddingRepresentation representation,
    int? spanStart,
    int? spanEnd,
  }) =>
      _id(
        'emb',
        '$sourceKind|$sourceId|${representation.name}|${spanStart ?? -1}|${spanEnd ?? -1}',
      );

  static String bodyEmbeddingId(String chunkId) => embeddingId(
        sourceKind: 'chunk',
        sourceId: chunkId,
        representation: EmbeddingRepresentation.body,
      );

  static String queryEmbeddingId(String traceId) => embeddingId(
        sourceKind: 'query',
        sourceId: traceId,
        representation: EmbeddingRepresentation.query,
      );

  static String traceId(String sessionId, String turnId) =>
      _id('tr', '$sessionId|$turnId');

  static String eventId(String traceId, int seq) => _id('evt', '$traceId|$seq');

  static String candidateId(
    String traceId,
    String strategyId,
    String chunkId,
  ) =>
      _id('cand', '$traceId|$strategyId|$chunkId');

  static String evidenceId(
    String traceId,
    String strategyId,
    String chunkId,
  ) =>
      _id('ev', '$traceId|$strategyId|$chunkId');

  static String vectorIndexEntryId(
    String embeddingId,
    String backendId,
    String strategyId,
    RetrievalLane lane,
  ) =>
      _id('idx', '$embeddingId|$backendId|$strategyId|${lane.dbValue}');

  static String buildJobId(String documentId, String strategyId) =>
      _id('job', '$documentId|$strategyId');

  static String sectionId(
    String documentId,
    String locator,
    int? pageNo,
    int? startOffset,
    int? endOffset,
  ) =>
      _id(
        'sec',
        '$documentId|$locator|${pageNo ?? -1}|${startOffset ?? -1}|${endOffset ?? -1}',
      );
}
