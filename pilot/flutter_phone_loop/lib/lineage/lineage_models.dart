import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

enum TruthKind { real, derived }

enum RetrievalLane { active, shadow, experimental }

enum EmbeddingRepresentation { body, heading, sentence, query }

enum VectorCommitStatus { pending, committed, failed }

enum TraceStatus { running, complete, failed }

enum BuildState {
  prepared,
  lexicalCommitted,
  lineageCommitted,
  vectorCommitted,
  ready,
}

enum BuildJobStatus { pending, running, complete, failed, cancelled }

enum ExperimentRunStatus { pending, running, complete, failed, cancelled }

extension TruthKindStorage on TruthKind {
  String get dbValue => name.toUpperCase();
}

TruthKind truthKindFromDb(String value) => switch (value.toUpperCase()) {
  'REAL' => TruthKind.real,
  'DERIVED' => TruthKind.derived,
  _ => throw StateError('Unknown truth kind: $value'),
};

extension RetrievalLaneStorage on RetrievalLane {
  String get dbValue => name.toUpperCase();
}

RetrievalLane retrievalLaneFromDb(String value) =>
    switch (value.toUpperCase()) {
      'ACTIVE' => RetrievalLane.active,
      'SHADOW' => RetrievalLane.shadow,
      'EXPERIMENTAL' => RetrievalLane.experimental,
      _ => throw StateError('Unknown retrieval lane: $value'),
    };

EmbeddingRepresentation embeddingRepresentationFromDb(String value) =>
    EmbeddingRepresentation.values.firstWhere(
      (item) => item.name == value,
      orElse: () => throw StateError('Unknown representation: $value'),
    );

TraceStatus traceStatusFromDb(String value) => TraceStatus.values.firstWhere(
  (item) => item.name == value,
  orElse: () => throw StateError('Unknown trace status: $value'),
);

BuildJobStatus buildJobStatusFromDb(String value) =>
    BuildJobStatus.values.firstWhere(
      (item) => item.name == value,
      orElse: () => throw StateError('Unknown build job status: $value'),
    );

ExperimentRunStatus experimentRunStatusFromDb(String value) =>
    ExperimentRunStatus.values.firstWhere(
      (item) => item.name == value,
      orElse: () => throw StateError('Unknown experiment run status: $value'),
    );

class LineageEmbedding {
  LineageEmbedding({
    required this.embeddingId,
    required this.sourceKind,
    required this.sourceId,
    required this.documentId,
    required this.chunkId,
    required this.representation,
    required this.spanStart,
    required this.spanEnd,
    required this.modelIdentity,
    required this.taskMode,
    required this.dimension,
    required this.norm,
    required Uint8List vectorF32,
    required this.vectorSha256,
    required this.generationMs,
    required this.generatedAt,
    this.truthKind = TruthKind.real,
  }) : vectorF32 = Uint8List.fromList(vectorF32);

  factory LineageEmbedding.fromVector({
    required String embeddingId,
    required String sourceKind,
    required String sourceId,
    String? documentId,
    String? chunkId,
    required EmbeddingRepresentation representation,
    int? spanStart,
    int? spanEnd,
    required List<double> vector,
    required String modelIdentity,
    required String taskMode,
    int generationMs = 0,
    DateTime? generatedAt,
    TruthKind truthKind = TruthKind.real,
  }) {
    if (vector.isEmpty || vector.any((value) => !value.isFinite)) {
      throw ArgumentError.value(
        vector,
        'vector',
        'Vector must be finite and non-empty',
      );
    }
    final bytes = encodeFloat32(vector);
    final persisted = decodeFloat32(bytes);
    final norm = vectorNorm(persisted);
    if (!norm.isFinite || norm <= 0) {
      throw ArgumentError.value(
        vector,
        'vector',
        'Vector norm must be finite and non-zero',
      );
    }
    return LineageEmbedding(
      embeddingId: embeddingId,
      sourceKind: sourceKind,
      sourceId: sourceId,
      documentId: documentId,
      chunkId: chunkId,
      representation: representation,
      spanStart: spanStart,
      spanEnd: spanEnd,
      modelIdentity: modelIdentity,
      taskMode: taskMode,
      dimension: persisted.length,
      norm: norm,
      vectorF32: bytes,
      vectorSha256: sha256.convert(bytes).toString(),
      generationMs: generationMs,
      generatedAt: (generatedAt ?? DateTime.now()).toUtc(),
      truthKind: truthKind,
    );
  }

  factory LineageEmbedding.test({
    required String embeddingId,
    required String sourceKind,
    required String sourceId,
    String? documentId,
    required String? chunkId,
    required EmbeddingRepresentation representation,
    int? spanStart,
    int? spanEnd,
    required List<double> vector,
    required String modelIdentity,
    required String taskMode,
  }) => LineageEmbedding.fromVector(
    embeddingId: embeddingId,
    sourceKind: sourceKind,
    sourceId: sourceId,
    documentId: documentId,
    chunkId: chunkId,
    representation: representation,
    spanStart: spanStart,
    spanEnd: spanEnd,
    vector: vector,
    modelIdentity: modelIdentity,
    taskMode: taskMode,
    generatedAt: DateTime.utc(2026, 1, 1),
  );

  final String embeddingId;
  final String sourceKind;
  final String sourceId;
  final String? documentId;
  final String? chunkId;
  final EmbeddingRepresentation representation;
  final int? spanStart;
  final int? spanEnd;
  final String modelIdentity;
  final String taskMode;
  final int dimension;
  final double norm;
  final Uint8List vectorF32;
  final String vectorSha256;
  final int generationMs;
  final DateTime generatedAt;
  final TruthKind truthKind;

  List<double> get vector => decodeFloat32(vectorF32);

  void validate() {
    if (embeddingId.isEmpty || sourceKind.isEmpty || sourceId.isEmpty) {
      throw ArgumentError('Embedding identity fields must be non-empty');
    }
    if (dimension <= 0 || vectorF32.length != dimension * 4) {
      throw ArgumentError('Embedding dimension/blob length mismatch');
    }
    final decoded = decodeFloat32(vectorF32);
    if (decoded.any((value) => !value.isFinite)) {
      throw ArgumentError('Embedding contains non-finite values');
    }
    final calculatedNorm = vectorNorm(decoded);
    if (!calculatedNorm.isFinite || calculatedNorm <= 0) {
      throw ArgumentError('Embedding norm must be finite and non-zero');
    }
    if ((calculatedNorm - norm).abs() > 1e-5) {
      throw ArgumentError('Embedding norm does not match persisted vector');
    }
    final calculatedSha = sha256.convert(vectorF32).toString();
    if (calculatedSha != vectorSha256) {
      throw ArgumentError('Embedding SHA-256 does not match persisted vector');
    }
  }

  static Uint8List encodeFloat32(List<double> vector) {
    final data = ByteData(vector.length * 4);
    for (var i = 0; i < vector.length; i++) {
      data.setFloat32(i * 4, vector[i], Endian.little);
    }
    return data.buffer.asUint8List();
  }

  static List<double> decodeFloat32(Uint8List bytes) {
    if (bytes.length % 4 != 0) {
      throw ArgumentError.value(
        bytes.length,
        'bytes.length',
        'Float32 BLOB length must be divisible by 4',
      );
    }
    final data = ByteData.sublistView(bytes);
    return List<double>.generate(
      bytes.length ~/ 4,
      (index) => data.getFloat32(index * 4, Endian.little),
      growable: false,
    );
  }

  static double vectorNorm(List<double> vector) {
    var sum = 0.0;
    for (final value in vector) {
      sum += value * value;
    }
    return math.sqrt(sum);
  }
}

class LineageTrace {
  const LineageTrace({
    required this.traceId,
    required this.sessionId,
    required this.turnId,
    required this.queryText,
    required this.requestedMode,
    required this.finalMode,
    required this.scopeJson,
    required this.activeStrategyId,
    required this.startedAt,
    required this.completedAt,
    required this.status,
    required this.failureStage,
    required this.failureCode,
  });

  final String traceId;
  final String sessionId;
  final String turnId;
  final String queryText;
  final String requestedMode;
  final String finalMode;
  final String scopeJson;
  final String activeStrategyId;
  final DateTime startedAt;
  final DateTime? completedAt;
  final TraceStatus status;
  final String? failureStage;
  final String? failureCode;
}

class TraceEventRecord {
  const TraceEventRecord({
    required this.eventId,
    required this.traceId,
    required this.seq,
    required this.stage,
    required this.kind,
    required this.truthKind,
    required this.lane,
    required this.strategyId,
    required this.timestampUs,
    required this.durationUs,
    required this.payloadJson,
  });

  final String eventId;
  final String traceId;
  final int seq;
  final String stage;
  final String kind;
  final TruthKind truthKind;
  final RetrievalLane lane;
  final String strategyId;
  final int timestampUs;
  final int? durationUs;
  final String payloadJson;
}

class CandidateRecord {
  const CandidateRecord({
    required this.candidateId,
    required this.traceId,
    required this.strategyId,
    required this.lane,
    required this.chunkId,
    required this.embeddingId,
    required this.sourceChannels,
    required this.ftsRank,
    required this.rawBm25,
    required this.vectorRank,
    required this.rawCosine,
    required this.fusionRank,
    required this.fusionScore,
    required this.rerankRank,
    required this.rerankScore,
    required this.finalRank,
    required this.selectedForEvidence,
    required this.dropReason,
  });

  final String candidateId;
  final String traceId;
  final String strategyId;
  final RetrievalLane lane;
  final String chunkId;
  final String? embeddingId;
  final String sourceChannels;
  final int? ftsRank;
  final double? rawBm25;
  final int? vectorRank;
  final double? rawCosine;
  final int? fusionRank;
  final double? fusionScore;
  final int? rerankRank;
  final double? rerankScore;
  final int? finalRank;
  final bool selectedForEvidence;
  final String? dropReason;
}

class RerankFeatureRecord {
  const RerankFeatureRecord({
    required this.featureId,
    required this.traceId,
    required this.strategyId,
    required this.lane,
    required this.candidateId,
    required this.chunkId,
    required this.normalizedLexicalAffinity,
    required this.cosine,
    required this.dualChannelAgreement,
    required this.queryWindowCoverage,
    required this.headingMatch,
    required this.exactTermMatch,
    required this.sourceDiversity,
    required this.rerankScore,
    required this.contributionJson,
  });

  final String featureId;
  final String traceId;
  final String strategyId;
  final RetrievalLane lane;
  final String candidateId;
  final String chunkId;
  final double normalizedLexicalAffinity;
  final double cosine;
  final double dualChannelAgreement;
  final double queryWindowCoverage;
  final double headingMatch;
  final double exactTermMatch;
  final double sourceDiversity;
  final double rerankScore;
  final String contributionJson;
}

class RouterDecisionRecord {
  const RouterDecisionRecord({
    required this.decisionId,
    required this.traceId,
    required this.strategyId,
    required this.lane,
    required this.ftsHitCount,
    required this.top1Cosine,
    required this.top2Cosine,
    required this.top1Top2Gap,
    required this.dualChannel,
    required this.lexicalGatePass,
    required this.semanticStrengthGatePass,
    required this.semanticGapGatePass,
    required this.finalUseKnowledge,
    required this.ruleProfile,
    required this.decisionReason,
  });

  final String decisionId;
  final String traceId;
  final String strategyId;
  final RetrievalLane lane;
  final int ftsHitCount;
  final double? top1Cosine;
  final double? top2Cosine;
  final double? top1Top2Gap;
  final bool dualChannel;
  final bool lexicalGatePass;
  final bool semanticStrengthGatePass;
  final bool semanticGapGatePass;
  final bool finalUseKnowledge;
  final String ruleProfile;
  final String decisionReason;
}

class EvidenceRecord {
  const EvidenceRecord({
    required this.evidenceId,
    required this.traceId,
    required this.strategyId,
    required this.lane,
    required this.anchor,
    required this.candidateId,
    required this.chunkId,
    required this.selectionRank,
    required this.score,
    required this.tokenCount,
    required this.selectionReason,
  });

  final String evidenceId;
  final String traceId;
  final String strategyId;
  final RetrievalLane lane;
  final String? anchor;
  final String candidateId;
  final String chunkId;
  final int selectionRank;
  final double score;
  final int tokenCount;
  final String selectionReason;
}

class PromptBudgetRecord {
  const PromptBudgetRecord({
    required this.traceId,
    required this.strategyId,
    required this.lane,
    required this.modelContextLimit,
    required this.systemTokens,
    required this.historyTokens,
    required this.evidenceTokens,
    required this.queryTokens,
    required this.outputReserveTokens,
    required this.totalPrefillTokens,
    required this.remainingTokens,
    required this.trimmedHistoryMessages,
    required this.trimmedEvidenceItems,
    required this.trimDetailJson,
  });

  final String traceId;
  final String strategyId;
  final RetrievalLane lane;
  final int modelContextLimit;
  final int systemTokens;
  final int historyTokens;
  final int evidenceTokens;
  final int queryTokens;
  final int outputReserveTokens;
  final int totalPrefillTokens;
  final int remainingTokens;
  final int trimmedHistoryMessages;
  final int trimmedEvidenceItems;
  final String trimDetailJson;
}

class GenerationStatsRecord {
  const GenerationStatsRecord({
    required this.traceId,
    required this.strategyId,
    required this.lane,
    required this.ttftMs,
    required this.generationMs,
    required this.outputTokens,
    required this.decodeTokensPerSecond,
    required this.backend,
    required this.nativeSessionRebuilt,
    required this.sessionResetReason,
  });

  final String traceId;
  final String strategyId;
  final RetrievalLane lane;
  final int? ttftMs;
  final int generationMs;
  final int? outputTokens;
  final double? decodeTokensPerSecond;
  final String? backend;
  final bool nativeSessionRebuilt;
  final String? sessionResetReason;
}

class CitationRecord {
  const CitationRecord({
    required this.citationId,
    required this.traceId,
    required this.anchor,
    required this.evidenceId,
    required this.chunkId,
    required this.documentId,
    required this.sectionId,
    required this.pageNo,
    required this.citationStatus,
  });

  final String citationId;
  final String traceId;
  final String anchor;
  final String? evidenceId;
  final String? chunkId;
  final String? documentId;
  final String? sectionId;
  final int? pageNo;
  final String citationStatus;
}

class ExperimentRunRecord {
  const ExperimentRunRecord({
    required this.experimentRunId,
    required this.traceId,
    required this.strategyId,
    required this.lane,
    required this.status,
    required this.startedAt,
    required this.completedAt,
    required this.completedItems,
    required this.totalItems,
    required this.metricJson,
    required this.failureCode,
    this.failureDetail,
  });

  final String experimentRunId;
  final String traceId;
  final String strategyId;
  final RetrievalLane lane;
  final ExperimentRunStatus status;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int completedItems;
  final int totalItems;
  final String? metricJson;
  final String? failureCode;
  final String? failureDetail;

  ExperimentRunRecord copyWith({
    String? experimentRunId,
    String? traceId,
    String? strategyId,
    RetrievalLane? lane,
    ExperimentRunStatus? status,
    DateTime? startedAt,
    DateTime? completedAt,
    int? completedItems,
    int? totalItems,
    String? metricJson,
    String? failureCode,
    String? failureDetail,
  }) => ExperimentRunRecord(
    experimentRunId: experimentRunId ?? this.experimentRunId,
    traceId: traceId ?? this.traceId,
    strategyId: strategyId ?? this.strategyId,
    lane: lane ?? this.lane,
    status: status ?? this.status,
    startedAt: startedAt ?? this.startedAt,
    completedAt: completedAt ?? this.completedAt,
    completedItems: completedItems ?? this.completedItems,
    totalItems: totalItems ?? this.totalItems,
    metricJson: metricJson ?? this.metricJson,
    failureCode: failureCode ?? this.failureCode,
    failureDetail: failureDetail ?? this.failureDetail,
  );
}

class BuildJobRecord {
  const BuildJobRecord({
    required this.jobId,
    required this.jobType,
    required this.strategyId,
    required this.documentId,
    required this.status,
    required this.totalItems,
    required this.completedItems,
    required this.checkpointJson,
    required this.currentSource,
    required this.failureCode,
    required this.failureDetail,
    required this.createdAt,
    required this.updatedAt,
  });

  final String jobId;
  final String jobType;
  final String strategyId;
  final String? documentId;
  final BuildJobStatus status;
  final int totalItems;
  final int completedItems;
  final String checkpointJson;
  final String? currentSource;
  final String? failureCode;
  final String? failureDetail;
  final DateTime createdAt;
  final DateTime updatedAt;
}
