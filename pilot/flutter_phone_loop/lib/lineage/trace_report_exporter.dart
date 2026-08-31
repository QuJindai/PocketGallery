import 'dart:convert';
import 'dart:typed_data';

import 'trace_snapshot.dart';

abstract final class TraceReportExporter {
  static final RegExp _sensitivePayloadKey = RegExp(
    r'(authorization|credential|password|secret|token|vector|raw.*text|document.*text|chunk.*text|content|body)',
    caseSensitive: false,
  );

  static Uint8List encodeRedacted(TraceSnapshot snapshot) {
    final trace = snapshot.trace;
    final queryEmbedding = snapshot.queryEmbedding;
    final report = <String, Object?>{
      'schema': 'pocketgallery.r46.lineage-report.v1',
      'trace': <String, Object?>{
        'traceId': trace.traceId,
        'sessionId': trace.sessionId,
        'turnId': trace.turnId,
        'query': trace.queryText,
        'requestedMode': trace.requestedMode,
        'finalMode': trace.finalMode,
        'scope': _decodeJson(trace.scopeJson),
        'activeStrategyId': trace.activeStrategyId,
        'startedAt': trace.startedAt.toUtc().toIso8601String(),
        'completedAt': trace.completedAt?.toUtc().toIso8601String(),
        'status': trace.status.name,
        'failureStage': trace.failureStage,
        'failureCode': trace.failureCode,
      },
      'queryEmbedding': queryEmbedding == null
          ? null
          : <String, Object?>{
              'embeddingId': queryEmbedding.embeddingId,
              'representation': queryEmbedding.representation.name,
              'modelIdentity': queryEmbedding.modelIdentity,
              'taskMode': queryEmbedding.taskMode,
              'dimension': queryEmbedding.dimension,
              'norm': queryEmbedding.norm,
              'vectorSha256': queryEmbedding.vectorSha256,
              'generationMs': queryEmbedding.generationMs,
              'truthKind': queryEmbedding.truthKind.dbValue,
            },
      'events': <Object?>[
        for (final event in snapshot.events)
          <String, Object?>{
            'seq': event.seq,
            'stage': event.stage,
            'kind': event.kind,
            'truthKind': event.truthKind.dbValue,
            'lane': event.lane.dbValue,
            'strategyId': event.strategyId,
            'timestampUs': event.timestampUs,
            'durationUs': event.durationUs,
            'payload': _sanitizePayload(_decodeJson(event.payloadJson)),
          },
      ],
      'candidates': <Object?>[
        for (final record in snapshot.candidates)
          <String, Object?>{
            'candidateId': record.candidateId,
            'strategyId': record.strategyId,
            'lane': record.lane.dbValue,
            'chunkId': record.chunkId,
            'embeddingId': record.embeddingId,
            'sourceChannels': record.sourceChannels,
            'ftsRank': record.ftsRank,
            'rawBm25': record.rawBm25,
            'vectorRank': record.vectorRank,
            'rawCosine': record.rawCosine,
            'fusionRank': record.fusionRank,
            'fusionScore': record.fusionScore,
            'rerankRank': record.rerankRank,
            'rerankScore': record.rerankScore,
            'finalRank': record.finalRank,
            'selectedForEvidence': record.selectedForEvidence,
            'dropReason': record.dropReason,
          },
      ],
      'evidence': <Object?>[
        for (final record in snapshot.evidence)
          <String, Object?>{
            'evidenceId': record.evidenceId,
            'strategyId': record.strategyId,
            'lane': record.lane.dbValue,
            'anchor': record.anchor,
            'candidateId': record.candidateId,
            'chunkId': record.chunkId,
            'selectionRank': record.selectionRank,
            'score': record.score,
            'tokenCount': record.tokenCount,
            'selectionReason': record.selectionReason,
          },
      ],
      'citations': <Object?>[
        for (final record in snapshot.citations)
          <String, Object?>{
            'citationId': record.citationId,
            'anchor': record.anchor,
            'evidenceId': record.evidenceId,
            'chunkId': record.chunkId,
            'documentId': record.documentId,
            'sectionId': record.sectionId,
            'pageNo': record.pageNo,
            'status': record.citationStatus,
          },
      ],
      'experiments': <Object?>[
        for (final run in snapshot.experimentRuns)
          <String, Object?>{
            'experimentRunId': run.experimentRunId,
            'strategyId': run.strategyId,
            'lane': run.lane.dbValue,
            'status': run.status.name,
            'startedAt': run.startedAt?.toUtc().toIso8601String(),
            'completedAt': run.completedAt?.toUtc().toIso8601String(),
            'completedItems': run.completedItems,
            'totalItems': run.totalItems,
            'metrics': _sanitizePayload(_decodeJson(run.metricJson)),
            'failureCode': run.failureCode,
          },
      ],
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(report)));
  }

  static Object? _decodeJson(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return jsonDecode(value);
    } catch (_) {
      return const <String, Object?>{'malformed': true};
    }
  }

  static Object? _sanitizePayload(Object? value) {
    if (value is List) {
      return <Object?>[
        for (final item in value) _sanitizePayload(item),
      ];
    }
    if (value is Map) {
      final result = <String, Object?>{};
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      for (final key in keys) {
        if (_sensitivePayloadKey.hasMatch(key)) continue;
        result[key] = _sanitizePayload(value[key]);
      }
      return result;
    }
    return value;
  }
}
