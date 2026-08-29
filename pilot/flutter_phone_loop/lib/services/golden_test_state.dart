enum GoldenRunPhase { preparing, running, cleaningUp, completed }

enum GoldenGateStatus { pending, running, passed, failed, timedOut, blocked }

extension GoldenGateStatusTerminal on GoldenGateStatus {
  bool get isTerminal => switch (this) {
        GoldenGateStatus.passed ||
        GoldenGateStatus.failed ||
        GoldenGateStatus.timedOut ||
        GoldenGateStatus.blocked =>
          true,
        GoldenGateStatus.pending || GoldenGateStatus.running => false,
      };
}

class GoldenGateSnapshot {
  const GoldenGateSnapshot({
    required this.name,
    required this.label,
    required this.timeout,
    this.status = GoldenGateStatus.pending,
    this.detail = '',
    this.startedAt,
    this.finishedAt,
  });

  final String name;
  final String label;
  final Duration timeout;
  final GoldenGateStatus status;
  final String detail;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  Duration? get duration {
    final started = startedAt;
    final finished = finishedAt;
    if (started == null || finished == null) return null;
    return finished.difference(started);
  }

  GoldenGateSnapshot copyWith({
    GoldenGateStatus? status,
    String? detail,
    Object? startedAt = _unset,
    Object? finishedAt = _unset,
  }) {
    return GoldenGateSnapshot(
      name: name,
      label: label,
      timeout: timeout,
      status: status ?? this.status,
      detail: detail ?? this.detail,
      startedAt: identical(startedAt, _unset)
          ? this.startedAt
          : startedAt as DateTime?,
      finishedAt: identical(finishedAt, _unset)
          ? this.finishedAt
          : finishedAt as DateTime?,
    );
  }

  Map<String, Object?> toJson() => {
        'name': name,
        'label': label,
        'timeoutMs': timeout.inMilliseconds,
        'status': status.name,
        'detail': detail,
        'startedAt': startedAt?.toIso8601String(),
        'finishedAt': finishedAt?.toIso8601String(),
        'durationMs': duration?.inMilliseconds,
      };

  factory GoldenGateSnapshot.fromJson(Map<String, dynamic> json) {
    return GoldenGateSnapshot(
      name: _requiredString(json, 'name'),
      label: _requiredString(json, 'label'),
      timeout: Duration(milliseconds: _requiredInt(json, 'timeoutMs')),
      status: _enumByName(
        GoldenGateStatus.values,
        _requiredString(json, 'status'),
        'status',
      ),
      detail: _requiredString(json, 'detail'),
      startedAt: _optionalDateTime(json, 'startedAt'),
      finishedAt: _optionalDateTime(json, 'finishedAt'),
    );
  }
}

class GoldenTestSnapshot {
  const GoldenTestSnapshot({
    required this.runId,
    required this.phase,
    required this.startedAt,
    required this.updatedAt,
    required this.gates,
    this.cleanupError,
  });

  static const int currentSchemaVersion = 2;

  final String runId;
  final GoldenRunPhase phase;
  final DateTime startedAt;
  final DateTime updatedAt;
  final List<GoldenGateSnapshot> gates;
  final String? cleanupError;

  int get schemaVersion => currentSchemaVersion;

  int get completedCount =>
      gates.where((gate) => gate.status.isTerminal).length;

  int get percent {
    if (phase == GoldenRunPhase.completed) return 100;
    if (phase == GoldenRunPhase.cleaningUp) return 95;
    if (phase == GoldenRunPhase.preparing || gates.isEmpty) return 0;
    return (completedCount * 90 / gates.length).round();
  }

  bool get passed =>
      phase == GoldenRunPhase.completed &&
      gates.isNotEmpty &&
      cleanupError == null &&
      gates.every((gate) => gate.status == GoldenGateStatus.passed);

  Duration get elapsed => updatedAt.difference(startedAt);

  GoldenGateSnapshot? get currentGate {
    for (final gate in gates) {
      if (gate.status == GoldenGateStatus.running) return gate;
    }
    for (final gate in gates) {
      if (gate.status == GoldenGateStatus.pending) return gate;
    }
    return null;
  }

  GoldenGateSnapshot? gate(String name) {
    for (final gate in gates) {
      if (gate.name == name) return gate;
    }
    return null;
  }

  GoldenTestSnapshot copyWith({
    GoldenRunPhase? phase,
    DateTime? updatedAt,
    List<GoldenGateSnapshot>? gates,
    Object? cleanupError = _unset,
  }) {
    return GoldenTestSnapshot(
      runId: runId,
      phase: phase ?? this.phase,
      startedAt: startedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      gates: gates ?? this.gates,
      cleanupError: identical(cleanupError, _unset)
          ? this.cleanupError
          : cleanupError as String?,
    );
  }

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'runId': runId,
        'phase': phase.name,
        'startedAt': startedAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'percent': percent,
        'completedCount': completedCount,
        'passed': passed,
        'cleanupError': cleanupError,
        'gates': gates.map((gate) => gate.toJson()).toList(growable: false),
      };

  factory GoldenTestSnapshot.fromJson(Map<String, dynamic> json) {
    final schemaVersion = _requiredInt(json, 'schemaVersion');
    if (schemaVersion != currentSchemaVersion) {
      throw FormatException('Unsupported Golden Test schema: $schemaVersion');
    }
    final rawGates = json['gates'];
    if (rawGates is! List) {
      throw const FormatException('Golden Test gates must be a list');
    }
    return GoldenTestSnapshot(
      runId: _requiredString(json, 'runId'),
      phase: _enumByName(
        GoldenRunPhase.values,
        _requiredString(json, 'phase'),
        'phase',
      ),
      startedAt: DateTime.parse(_requiredString(json, 'startedAt')),
      updatedAt: DateTime.parse(_requiredString(json, 'updatedAt')),
      gates: rawGates
          .map((gate) {
            if (gate is! Map) {
              throw const FormatException('Golden Test gate must be an object');
            }
            return GoldenGateSnapshot.fromJson(
              Map<String, dynamic>.from(gate),
            );
          })
          .toList(growable: false),
      cleanupError: json['cleanupError'] as String?,
    );
  }
}

const Object _unset = Object();

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('$key must be a string');
  return value;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('$key must be an integer');
  return value;
}

DateTime? _optionalDateTime(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('$key must be a string or null');
  return DateTime.parse(value);
}

T _enumByName<T extends Enum>(List<T> values, String name, String key) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('Unknown $key: $name');
}
