import '../services/golden_test_state.dart';

enum HandsetRunPhase {
  preparing,
  runningAutomated,
  awaitingInteraction,
  runningPostChecks,
  cleaningUp,
  completed,
}

enum HandsetGateStatus {
  pending,
  running,
  passed,
  failed,
  timedOut,
  blocked,
}

enum AcceptanceVerdict { pass, fail, blocked }

enum EvidenceMethod { measured, observed, derived, userAction }

extension HandsetGateStatusTerminal on HandsetGateStatus {
  bool get isTerminal => switch (this) {
        HandsetGateStatus.passed ||
        HandsetGateStatus.failed ||
        HandsetGateStatus.timedOut ||
        HandsetGateStatus.blocked =>
          true,
        HandsetGateStatus.pending || HandsetGateStatus.running => false,
      };
}

const Map<String, int> handsetGateWeights = <String, int>{
  'H1_TARGET_DEVICE': 3,
  'H2_BUILD_IDENTITY': 3,
  'H3_UPGRADE_BASELINE': 4,
  'H4_PHONE_FUNCTION_LOOP': 55,
  'H5_VECTOR_3D_TRUTH': 5,
  'H6_VECTOR_INTERACTION': 15,
  'H7_RENDER_PERFORMANCE': 5,
  'H8_MEMORY_THERMAL': 5,
  'H9_DATA_PRESERVATION': 3,
  'H10_REPORT_INTEGRITY': 2,
};

class AcceptanceEvidence {
  const AcceptanceEvidence({
    required this.code,
    required this.method,
    required this.source,
    required this.actual,
    required this.threshold,
    required this.unit,
    required this.available,
    required this.detail,
  });

  final String code;
  final EvidenceMethod method;
  final String source;
  final Object? actual;
  final Object? threshold;
  final String? unit;
  final bool available;
  final String detail;

  Map<String, Object?> toJson() => <String, Object?>{
        'code': code,
        'method': method.name,
        'source': source,
        'actual': _jsonScalar(actual, 'actual'),
        'threshold': _jsonScalar(threshold, 'threshold'),
        'unit': unit,
        'available': available,
        'detail': detail,
      };

  factory AcceptanceEvidence.fromJson(Map<String, dynamic> json) {
    return AcceptanceEvidence(
      code: _requiredString(json, 'code'),
      method: _enumByName(
        EvidenceMethod.values,
        _requiredString(json, 'method'),
        'method',
      ),
      source: _requiredString(json, 'source'),
      actual: _jsonScalar(json['actual'], 'actual'),
      threshold: _jsonScalar(json['threshold'], 'threshold'),
      unit: _optionalString(json, 'unit'),
      available: _requiredBool(json, 'available'),
      detail: _requiredString(json, 'detail'),
    );
  }
}

class HandsetGateSnapshot {
  const HandsetGateSnapshot({
    required this.name,
    required this.label,
    required this.status,
    required this.detail,
    required this.evidence,
    this.startedAt,
    this.finishedAt,
  });

  final String name;
  final String label;
  final HandsetGateStatus status;
  final String detail;
  final List<AcceptanceEvidence> evidence;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  Duration? get duration {
    final started = startedAt;
    final finished = finishedAt;
    if (started == null || finished == null) return null;
    return finished.difference(started);
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'label': label,
        'status': status.name,
        'detail': detail,
        'evidence': evidence
            .map((item) => item.toJson())
            .toList(growable: false),
        'startedAt': startedAt?.toUtc().toIso8601String(),
        'finishedAt': finishedAt?.toUtc().toIso8601String(),
        'durationMs': duration?.inMilliseconds,
      };

  factory HandsetGateSnapshot.fromJson(Map<String, dynamic> json) {
    final rawEvidence = json['evidence'];
    if (rawEvidence is! List) {
      throw const FormatException('evidence must be a list');
    }
    return HandsetGateSnapshot(
      name: _requiredString(json, 'name'),
      label: _requiredString(json, 'label'),
      status: _enumByName(
        HandsetGateStatus.values,
        _requiredString(json, 'status'),
        'status',
      ),
      detail: _requiredString(json, 'detail'),
      evidence: rawEvidence.map((item) {
        if (item is! Map) {
          throw const FormatException('evidence item must be an object');
        }
        return AcceptanceEvidence.fromJson(Map<String, dynamic>.from(item));
      }).toList(growable: false),
      startedAt: _optionalDateTime(json, 'startedAt'),
      finishedAt: _optionalDateTime(json, 'finishedAt'),
    );
  }
}

class HandsetAcceptanceSnapshot {
  HandsetAcceptanceSnapshot({
    required this.runId,
    required this.phase,
    required this.startedAt,
    required this.updatedAt,
    required List<HandsetGateSnapshot> gates,
    this.nestedGolden,
    this.cleanupError,
    this.reportPath,
    this.baselineVersionCode,
    this.mergeCandidate = false,
  }) : gates = List<HandsetGateSnapshot>.unmodifiable(gates);

  static const int currentSchemaVersion = 1;

  final String runId;
  final HandsetRunPhase phase;
  final DateTime startedAt;
  final DateTime updatedAt;
  final List<HandsetGateSnapshot> gates;
  final GoldenTestSnapshot? nestedGolden;
  final String? cleanupError;
  final String? reportPath;
  final int? baselineVersionCode;
  final bool mergeCandidate;

  int get schemaVersion => currentSchemaVersion;

  AcceptanceVerdict get verdict {
    final hasFailure = cleanupError != null ||
        gates.any(
          (gate) =>
              gate.status == HandsetGateStatus.failed ||
              gate.status == HandsetGateStatus.timedOut,
        );
    if (hasFailure) return AcceptanceVerdict.fail;
    final incomplete = phase != HandsetRunPhase.completed ||
        gates.isEmpty ||
        gates.any((gate) => gate.status != HandsetGateStatus.passed);
    return incomplete ? AcceptanceVerdict.blocked : AcceptanceVerdict.pass;
  }

  int get percent {
    if (phase == HandsetRunPhase.completed) return 100;
    var total = 0.0;
    for (final gate in gates) {
      final weight = handsetGateWeights[gate.name] ?? 0;
      if (gate.status.isTerminal) {
        total += weight;
      } else if (gate.name == 'H4_PHONE_FUNCTION_LOOP' &&
          gate.status == HandsetGateStatus.running &&
          nestedGolden != null) {
        total += weight * nestedGolden!.percent / 100;
      }
    }
    return total.round().clamp(0, 99).toInt();
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': schemaVersion,
        'runId': runId,
        'phase': phase.name,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'percent': percent,
        'verdict': verdict.name,
        'gates': gates.map((gate) => gate.toJson()).toList(growable: false),
        'nestedGolden': nestedGolden?.toJson(),
        'cleanupError': cleanupError,
        'reportPath': reportPath,
        'baselineVersionCode': baselineVersionCode,
        'mergeCandidate': mergeCandidate,
      };

  factory HandsetAcceptanceSnapshot.fromJson(Map<String, dynamic> json) {
    final schemaVersion = _requiredInt(json, 'schemaVersion');
    if (schemaVersion != currentSchemaVersion) {
      throw FormatException(
        'Unsupported handset acceptance schema: $schemaVersion',
      );
    }
    final rawGates = json['gates'];
    if (rawGates is! List) {
      throw const FormatException('gates must be a list');
    }
    final rawNested = json['nestedGolden'];
    return HandsetAcceptanceSnapshot(
      runId: _requiredString(json, 'runId'),
      phase: _enumByName(
        HandsetRunPhase.values,
        _requiredString(json, 'phase'),
        'phase',
      ),
      startedAt: DateTime.parse(_requiredString(json, 'startedAt')),
      updatedAt: DateTime.parse(_requiredString(json, 'updatedAt')),
      gates: rawGates.map((gate) {
        if (gate is! Map) {
          throw const FormatException('gate must be an object');
        }
        return HandsetGateSnapshot.fromJson(Map<String, dynamic>.from(gate));
      }).toList(growable: false),
      nestedGolden: rawNested == null
          ? null
          : GoldenTestSnapshot.fromJson(
              Map<String, dynamic>.from(rawNested as Map),
            ),
      cleanupError: _optionalString(json, 'cleanupError'),
      reportPath: _optionalString(json, 'reportPath'),
      baselineVersionCode: _optionalInt(json, 'baselineVersionCode'),
      mergeCandidate: _requiredBool(json, 'mergeCandidate'),
    );
  }
}

Object? _jsonScalar(Object? value, String key) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  throw FormatException('$key must be a JSON scalar');
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('$key must be a string');
  return value;
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('$key must be a string or null');
  }
  return value;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('$key must be an integer');
  return value;
}

int? _optionalInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! int) {
    throw FormatException('$key must be an integer or null');
  }
  return value;
}

bool _requiredBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('$key must be a boolean');
  return value;
}

DateTime? _optionalDateTime(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('$key must be a string or null');
  }
  return DateTime.parse(value);
}

T _enumByName<T extends Enum>(List<T> values, String name, String key) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('Unknown $key: $name');
}
