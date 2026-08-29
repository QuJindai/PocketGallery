import 'dart:async';
import 'dart:convert';

import 'lineage_ids.dart';
import 'lineage_models.dart';
import 'lineage_store.dart';

class RuntimeLineageRecorder {
  RuntimeLineageRecorder({
    required this.store,
    this.strategyId = activeStrategyId,
    this.lane = RetrievalLane.active,
    this.maxCandidatesPerChannelStrategy = 50,
    this.retentionLimit = 200,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  static const activeStrategyId = 'active.r45-body-hybrid';

  final LineageStore store;
  final String strategyId;
  final RetrievalLane lane;
  final int maxCandidatesPerChannelStrategy;
  final int retentionLimit;
  final DateTime Function() clock;

  final Map<String, Future<void>> _traceQueues = {};
  final Map<String, int> _nextSequences = {};

  Future<LineageTrace> startTrace({
    required String sessionId,
    required String turnId,
    required String queryText,
    required String requestedMode,
    required String scopeJson,
  }) async {
    final traceId = LineageIds.traceId(sessionId, turnId);
    return _serialized(traceId, () async {
      final existing = await store.traceById(traceId);
      if (existing != null) return existing;
      final startedAt = clock().toUtc();
      final trace = LineageTrace(
        traceId: traceId,
        sessionId: sessionId,
        turnId: turnId,
        queryText: queryText,
        requestedMode: requestedMode,
        finalMode: 'pending',
        scopeJson: scopeJson,
        activeStrategyId: strategyId,
        startedAt: startedAt,
        completedAt: null,
        status: TraceStatus.running,
        failureStage: null,
        failureCode: null,
      );
      final event = await _createEvent(
        traceId: traceId,
        stage: 'trace',
        kind: 'trace.started',
        truthKind: TruthKind.real,
        durationUs: null,
        payload: {
          'requestedMode': requestedMode,
          'scope': _safeJsonValue(scopeJson),
        },
      );
      await store.runInTransaction(() async {
        await store.putTrace(trace);
        await store.appendEvent(event);
      });
      return trace;
    });
  }

  Future<void> event({
    required String traceId,
    required String stage,
    required String kind,
    TruthKind truthKind = TruthKind.real,
    int? durationUs,
    Map<String, Object?> payload = const {},
  }) =>
      _serialized(traceId, () async {
        final record = await _createEvent(
          traceId: traceId,
          stage: stage,
          kind: kind,
          truthKind: truthKind,
          durationUs: durationUs,
          payload: payload,
        );
        await store.appendEvent(record);
      });

  Future<void> candidates({
    required String traceId,
    required List<CandidateRecord> records,
  }) =>
      _serialized(traceId, () async {
        final counts = <String, int>{};
        final persisted = <CandidateRecord>[];
        for (final record in records) {
          _validateRecordScope(
            traceId,
            record.traceId,
            record.strategyId,
            record.lane,
          );
          final key =
              '${record.strategyId}|${record.lane.dbValue}|${record.sourceChannels}';
          final count = counts[key] ?? 0;
          if (count >= maxCandidatesPerChannelStrategy) continue;
          counts[key] = count + 1;
          persisted.add(record);
        }
        final capEvent = await _createEvent(
          traceId: traceId,
          stage: 'candidate',
          kind: 'candidate.pool_built',
          truthKind: TruthKind.real,
          durationUs: null,
          payload: {
            'received': records.length,
            'persisted': persisted.length,
            'droppedByCap': records.length - persisted.length,
            'capPerChannelStrategy': maxCandidatesPerChannelStrategy,
          },
        );
        await store.runInTransaction(() async {
          for (final record in persisted) {
            await store.putCandidate(record);
          }
          await store.appendEvent(capEvent);
        });
      });

  Future<void> routerDecision(RouterDecisionRecord record) =>
      _serialized(record.traceId, () async {
        _validateRecordScope(
          record.traceId,
          record.traceId,
          record.strategyId,
          record.lane,
        );
        final event = await _createEvent(
          traceId: record.traceId,
          stage: 'router',
          kind: 'router.evaluated',
          truthKind: TruthKind.real,
          durationUs: null,
          payload: {
            'ftsHitCount': record.ftsHitCount,
            'top1Cosine': record.top1Cosine,
            'top2Cosine': record.top2Cosine,
            'top1Top2Gap': record.top1Top2Gap,
            'dualChannel': record.dualChannel,
            'useKnowledge': record.finalUseKnowledge,
            'reason': record.decisionReason,
          },
        );
        await store.runInTransaction(() async {
          await store.putRouterDecision(record);
          await store.appendEvent(event);
        });
      });

  Future<void> evidence({
    required String traceId,
    required List<EvidenceRecord> records,
  }) =>
      _serialized(traceId, () async {
        for (final record in records) {
          _validateRecordScope(
            traceId,
            record.traceId,
            record.strategyId,
            record.lane,
          );
        }
        final event = await _createEvent(
          traceId: traceId,
          stage: 'evidence',
          kind: 'evidence.selected',
          truthKind: TruthKind.real,
          durationUs: null,
          payload: {'count': records.length},
        );
        await store.runInTransaction(() async {
          for (final record in records) {
            await store.putEvidence(record);
          }
          await store.appendEvent(event);
        });
      });

  Future<void> promptBudget(PromptBudgetRecord record) =>
      _serialized(record.traceId, () async {
        _validateRecordScope(
          record.traceId,
          record.traceId,
          record.strategyId,
          record.lane,
        );
        final event = await _createEvent(
          traceId: record.traceId,
          stage: 'context',
          kind: 'context.budgeted',
          truthKind: TruthKind.real,
          durationUs: null,
          payload: {
            'modelContextLimit': record.modelContextLimit,
            'totalPrefillTokens': record.totalPrefillTokens,
            'remainingTokens': record.remainingTokens,
            'trimmedHistoryMessages': record.trimmedHistoryMessages,
            'trimmedEvidenceItems': record.trimmedEvidenceItems,
          },
        );
        await store.runInTransaction(() async {
          await store.putPromptBudget(record);
          await store.appendEvent(event);
        });
      });

  Future<void> generation(GenerationStatsRecord record) =>
      _serialized(record.traceId, () async {
        _validateRecordScope(
          record.traceId,
          record.traceId,
          record.strategyId,
          record.lane,
        );
        final event = await _createEvent(
          traceId: record.traceId,
          stage: 'generation',
          kind: 'generation.completed',
          truthKind: TruthKind.real,
          durationUs: record.generationMs * 1000,
          payload: {
            'generationMs': record.generationMs,
            'ttftMs': record.ttftMs,
            'outputTokens': record.outputTokens,
            'decodeTokensPerSecond': record.decodeTokensPerSecond,
            'backend': record.backend,
          },
        );
        await store.runInTransaction(() async {
          await store.putGenerationStats(record);
          await store.appendEvent(event);
        });
      });

  Future<void> citations({
    required String traceId,
    required List<CitationRecord> records,
  }) =>
      _serialized(traceId, () async {
        final event = await _createEvent(
          traceId: traceId,
          stage: 'citation',
          kind: 'citation.resolved',
          truthKind: TruthKind.real,
          durationUs: null,
          payload: {
            'count': records.length,
            'resolved': records
                .where((record) => record.citationStatus == 'resolved')
                .length,
          },
        );
        await store.runInTransaction(() async {
          for (final record in records) {
            if (record.traceId != traceId) {
              throw ArgumentError('Citation trace does not match batch trace');
            }
            await store.putCitation(record);
          }
          await store.appendEvent(event);
        });
      });

  Future<void> completeTrace(
    String traceId, {
    required String finalMode,
  }) async {
    await _serialized(traceId, () async {
      final trace = await _requiredTrace(traceId);
      final completedAt = clock().toUtc();
      final event = await _createEvent(
        traceId: traceId,
        stage: 'trace',
        kind: 'trace.completed',
        truthKind: TruthKind.real,
        durationUs: completedAt
            .difference(trace.startedAt)
            .inMicroseconds
            .clamp(0, 1 << 62)
            .toInt(),
        payload: {'finalMode': finalMode},
      );
      await store.runInTransaction(() async {
        await store.appendEvent(event);
        await store.putTrace(LineageTrace(
          traceId: trace.traceId,
          sessionId: trace.sessionId,
          turnId: trace.turnId,
          queryText: trace.queryText,
          requestedMode: trace.requestedMode,
          finalMode: finalMode,
          scopeJson: trace.scopeJson,
          activeStrategyId: trace.activeStrategyId,
          startedAt: trace.startedAt,
          completedAt: completedAt,
          status: TraceStatus.complete,
          failureStage: null,
          failureCode: null,
        ));
      });
    });
    await store.pruneCompletedTraces(keep: retentionLimit);
  }

  Future<void> failTrace(
    String traceId, {
    required String stage,
    required Object error,
  }) =>
      _serialized(traceId, () async {
        final trace = await _requiredTrace(traceId);
        final completedAt = clock().toUtc();
        final errorCode = _errorCode(error);
        final detail = _sanitizeString(error.toString());
        final event = await _createEvent(
          traceId: traceId,
          stage: stage,
          kind: 'trace.failed',
          truthKind: TruthKind.real,
          durationUs: null,
          payload: {
            'failureStage': stage,
            'failureCode': errorCode,
            'detail': detail,
          },
        );
        await store.runInTransaction(() async {
          await store.appendEvent(event);
          await store.putTrace(LineageTrace(
            traceId: trace.traceId,
            sessionId: trace.sessionId,
            turnId: trace.turnId,
            queryText: trace.queryText,
            requestedMode: trace.requestedMode,
            finalMode: trace.finalMode,
            scopeJson: trace.scopeJson,
            activeStrategyId: trace.activeStrategyId,
            startedAt: trace.startedAt,
            completedAt: completedAt,
            status: TraceStatus.failed,
            failureStage: stage,
            failureCode: errorCode,
          ));
        });
      });

  Future<TraceEventRecord> _createEvent({
    required String traceId,
    required String stage,
    required String kind,
    required TruthKind truthKind,
    required int? durationUs,
    required Map<String, Object?> payload,
  }) async {
    final seq = await _nextSequence(traceId);
    return TraceEventRecord(
      eventId: LineageIds.eventId(traceId, seq),
      traceId: traceId,
      seq: seq,
      stage: stage,
      kind: kind,
      truthKind: truthKind,
      lane: lane,
      strategyId: strategyId,
      timestampUs: clock().toUtc().microsecondsSinceEpoch,
      durationUs: durationUs,
      payloadJson: jsonEncode(_sanitizeMap(payload)),
    );
  }

  Future<int> _nextSequence(String traceId) async {
    final cached = _nextSequences[traceId];
    if (cached != null) {
      _nextSequences[traceId] = cached + 1;
      return cached;
    }
    final existing = await store.eventsForTrace(traceId);
    final next = existing.isEmpty ? 1 : existing.last.seq + 1;
    _nextSequences[traceId] = next + 1;
    return next;
  }

  Future<LineageTrace> _requiredTrace(String traceId) async {
    final trace = await store.traceById(traceId);
    if (trace == null) throw StateError('Unknown trace: $traceId');
    return trace;
  }

  Future<T> _serialized<T>(
    String traceId,
    Future<T> Function() operation,
  ) async {
    final previous = _traceQueues[traceId] ?? Future<void>.value();
    final gate = Completer<void>();
    final gateFuture = gate.future;
    _traceQueues[traceId] = gateFuture;
    await previous.catchError((Object _) {});
    try {
      return await operation();
    } finally {
      gate.complete();
      if (identical(_traceQueues[traceId], gateFuture)) {
        _traceQueues.remove(traceId);
      }
    }
  }

  void _validateRecordScope(
    String expectedTraceId,
    String actualTraceId,
    String actualStrategyId,
    RetrievalLane actualLane,
  ) {
    if (expectedTraceId != actualTraceId ||
        strategyId != actualStrategyId ||
        lane != actualLane) {
      throw ArgumentError('Lineage record does not match recorder scope');
    }
  }

  Map<String, Object?> _sanitizeMap(Map<String, Object?> input) => {
        for (final entry in input.entries)
          entry.key: _sensitiveKey(entry.key)
              ? '[REDACTED]'
              : _sanitizeValue(entry.value),
      };

  Object? _sanitizeValue(Object? value) => switch (value) {
        String text => _sanitizeString(text),
        Map<String, Object?> map => _sanitizeMap(map),
        List<Object?> list => list.map(_sanitizeValue).toList(growable: false),
        _ => value,
      };

  Object? _safeJsonValue(String value) {
    try {
      return _sanitizeValue(jsonDecode(value));
    } catch (_) {
      return _sanitizeString(value);
    }
  }

  bool _sensitiveKey(String key) => RegExp(
        r'(authorization|password|passwd|token|secret|cookie|api[_-]?key)',
        caseSensitive: false,
      ).hasMatch(key);

  String _sanitizeString(String input) {
    var output = input.replaceAllMapped(
      RegExp(
        r'(authorization|password|passwd|token|secret|api[_-]?key)\s*[:=]\s*[^\s,;}]+',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}=[REDACTED]',
    );
    output = output.replaceAll(
      RegExp(r'Bearer\s+[^\s,;}]+', caseSensitive: false),
      'Bearer [REDACTED]',
    );
    return output.length <= 1000 ? output : output.substring(0, 1000);
  }

  String _errorCode(Object error) {
    final raw = error.runtimeType.toString();
    return raw
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match.group(1)}_${match.group(2)}',
        )
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '')
        .toUpperCase();
  }
}
