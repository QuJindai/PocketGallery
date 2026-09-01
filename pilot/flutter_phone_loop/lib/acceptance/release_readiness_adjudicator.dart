import 'pocketgallery_build_identity.dart';

final class DeviceAcceptanceEvidence {
  DeviceAcceptanceEvidence._({
    required this.sourceCommit,
    required this.packageName,
    required this.versionCode,
    required this.baselineVersionCode,
    required this.signerSha256,
    required this.apkSha256,
    required this.phoneFunctionLoop,
    required this.deviceAcceptance,
    required this.mergeCandidate,
    required Map<String, String> gateStatuses,
    required _NestedGoldenEvidence? nestedGolden,
  })  : gateStatuses = Map<String, String>.unmodifiable(gateStatuses),
        _nestedGolden = nestedGolden;

  factory DeviceAcceptanceEvidence.fromJson(Map<String, dynamic> json) {
    final schema = _requiredString(json, 'schema');
    if (schema != 'pocketgallery.r50.handset-acceptance.v1') {
      throw FormatException('Unsupported device evidence schema: $schema');
    }
    final schemaVersion = _requiredInt(json, 'schemaVersion');
    if (schemaVersion != 1) {
      throw FormatException(
        'Unsupported device evidence schemaVersion: $schemaVersion',
      );
    }
    final identity = _requiredMap(json, 'identity');
    final baselineVersionCode = _nullableInt(
      json,
      'baselineVersionCode',
    );
    final nestedValue = json['nestedGolden'];
    final nestedGolden = nestedValue == null
        ? null
        : _NestedGoldenEvidence.fromJson(
            _mapValue(nestedValue, 'nestedGolden'),
          );
    return DeviceAcceptanceEvidence._(
      sourceCommit: _sourceCommit(identity, 'sourceCommit'),
      packageName: _requiredString(identity, 'packageName'),
      versionCode: _requiredInt(identity, 'versionCode'),
      baselineVersionCode: baselineVersionCode,
      signerSha256: _sha256(identity, 'signerSha256'),
      apkSha256: _sha256(identity, 'apkSha256'),
      phoneFunctionLoop: _releaseStatus(
        json,
        'PHONE_FUNCTION_LOOP',
      ),
      deviceAcceptance: _releaseStatus(json, 'DEVICE_ACCEPTANCE'),
      mergeCandidate: _requiredBool(json, 'MERGE_CANDIDATE'),
      gateStatuses: _gateStatuses(
        json,
        'gates',
        _handsetGateNames,
        _handsetGateStatuses,
      ),
      nestedGolden: nestedGolden,
    );
  }

  final String sourceCommit;
  final String packageName;
  final int versionCode;
  final int? baselineVersionCode;
  final String signerSha256;
  final String apkSha256;
  final String phoneFunctionLoop;
  final String deviceAcceptance;
  final bool mergeCandidate;
  final Map<String, String> gateStatuses;
  final _NestedGoldenEvidence? _nestedGolden;

  bool get allHandsetGatesPassed =>
      _handsetGateNames.every((name) => gateStatuses[name] == 'PASSED');

  bool get nestedGoldenPassed => _nestedGolden?.passedForRelease ?? false;
}

final class AutomatedReleaseEvidence {
  AutomatedReleaseEvidence._({
    required this.sourceCommit,
    required this.automatedGatesPassed,
    required this.packageName,
    required this.baselineVersionCode,
    required this.versionCode,
    required this.signerSha256,
    required this.apkSha256,
    required this.workflowIdentity,
  });

  factory AutomatedReleaseEvidence.fromJson(Map<String, dynamic> json) {
    final schema = _requiredString(json, 'schema');
    if (schema != 'pocketgallery.r50.automated-evidence.v1') {
      throw FormatException(
        'Unsupported automated evidence schema: $schema',
      );
    }
    return AutomatedReleaseEvidence._(
      sourceCommit: _sourceCommit(json, 'sourceCommit'),
      automatedGatesPassed: _requiredBool(
        json,
        'automatedGatesPassed',
      ),
      packageName: _requiredString(json, 'packageName'),
      baselineVersionCode: _requiredInt(json, 'baselineVersionCode'),
      versionCode: _requiredInt(json, 'versionCode'),
      signerSha256: _sha256(json, 'signerSha256'),
      apkSha256: _sha256(json, 'apkSha256'),
      workflowIdentity: _requiredNonEmptyString(
        json,
        'workflowIdentity',
      ),
    );
  }

  final String sourceCommit;
  final bool automatedGatesPassed;
  final String packageName;
  final int baselineVersionCode;
  final int versionCode;
  final String signerSha256;
  final String apkSha256;
  final String workflowIdentity;
}

final class ReleaseReadinessDecision {
  ReleaseReadinessDecision({
    required this.mergeReady,
    required List<String> reasons,
    required this.sourceCommit,
    required this.versionCode,
    required this.apkSha256,
  }) : reasons = List<String>.unmodifiable(reasons);

  final bool mergeReady;
  final List<String> reasons;
  final String sourceCommit;
  final int versionCode;
  final String apkSha256;

  Map<String, Object?> toJson() => <String, Object?>{
        'schema': 'pocketgallery.r50.merge-readiness.v1',
        'mergeReady': mergeReady,
        'reasons': reasons,
        'sourceCommit': sourceCommit,
        'versionCode': versionCode,
        'apkSha256': apkSha256,
      };
}

abstract final class ReleaseReadinessAdjudicator {
  static ReleaseReadinessDecision adjudicate(
    DeviceAcceptanceEvidence deviceReport,
    AutomatedReleaseEvidence automatedEvidence,
    String sidecarSha256,
  ) {
    final normalizedSidecar = _normalizeSha256(
      sidecarSha256,
      'sidecarSha256',
    );
    final reasons = <String>[];

    if (deviceReport.sourceCommit != automatedEvidence.sourceCommit) {
      reasons.add('SOURCE_COMMIT_MISMATCH');
    }
    if (deviceReport.packageName != PocketGalleryBuildIdentity.packageName ||
        automatedEvidence.packageName !=
            PocketGalleryBuildIdentity.packageName ||
        deviceReport.packageName != automatedEvidence.packageName) {
      reasons.add('PACKAGE_MISMATCH');
    }
    if (deviceReport.versionCode != 2023 ||
        deviceReport.baselineVersionCode != 2022 ||
        automatedEvidence.versionCode != 2023 ||
        automatedEvidence.baselineVersionCode != 2022 ||
        deviceReport.versionCode != automatedEvidence.versionCode) {
      reasons.add('VERSION_CODE_MISMATCH');
    }
    if (deviceReport.signerSha256 !=
            PocketGalleryBuildIdentity.canonicalSignerSha256 ||
        automatedEvidence.signerSha256 !=
            PocketGalleryBuildIdentity.canonicalSignerSha256 ||
        deviceReport.signerSha256 != automatedEvidence.signerSha256) {
      reasons.add('SIGNER_MISMATCH');
    }
    if (deviceReport.apkSha256 != automatedEvidence.apkSha256) {
      reasons.add('DEVICE_APK_DIGEST_MISMATCH');
    }
    if (normalizedSidecar != automatedEvidence.apkSha256) {
      reasons.add('SIDECAR_DIGEST_MISMATCH');
    }
    if (!automatedEvidence.automatedGatesPassed) {
      reasons.add('AUTOMATED_GATES_FAILED');
    }
    if (!deviceReport.allHandsetGatesPassed) {
      reasons.add('DEVICE_GATE_STATUS_INVALID');
    }
    if (deviceReport.phoneFunctionLoop != 'PASS') {
      reasons.add('PHONE_FUNCTION_LOOP_NOT_PASS');
    }
    if (!deviceReport.nestedGoldenPassed) {
      reasons.add('NESTED_GOLDEN_NOT_PASS');
    }
    if (deviceReport.deviceAcceptance != 'PASS') {
      reasons.add('DEVICE_ACCEPTANCE_NOT_PASS');
    }
    if (!deviceReport.mergeCandidate) {
      reasons.add('MERGE_CANDIDATE_FALSE');
    }

    return ReleaseReadinessDecision(
      mergeReady: reasons.isEmpty,
      reasons: reasons,
      sourceCommit: automatedEvidence.sourceCommit,
      versionCode: automatedEvidence.versionCode,
      apkSha256: automatedEvidence.apkSha256,
    );
  }
}

final class _NestedGoldenEvidence {
  _NestedGoldenEvidence._({
    required this.phase,
    required this.passed,
    required this.cleanupError,
    required Map<String, String> gateStatuses,
  }) : gateStatuses = Map<String, String>.unmodifiable(gateStatuses);

  factory _NestedGoldenEvidence.fromJson(Map<String, dynamic> json) {
    final schemaVersion = _requiredInt(json, 'schemaVersion');
    if (schemaVersion != 2) {
      throw FormatException(
        'Unsupported nested Golden schemaVersion: $schemaVersion',
      );
    }
    final phase = _requiredString(json, 'phase');
    if (!_goldenPhases.contains(phase)) {
      throw FormatException('Unknown nested Golden phase: $phase');
    }
    final cleanupValue = json['cleanupError'];
    if (cleanupValue != null && cleanupValue is! String) {
      throw const FormatException(
        'cleanupError must be a string or null',
      );
    }
    return _NestedGoldenEvidence._(
      phase: phase,
      passed: _requiredBool(json, 'passed'),
      cleanupError: cleanupValue as String?,
      gateStatuses: _gateStatuses(
        json,
        'gates',
        _goldenGateNames,
        _goldenGateStatuses,
      ),
    );
  }

  final String phase;
  final bool passed;
  final String? cleanupError;
  final Map<String, String> gateStatuses;

  bool get passedForRelease =>
      phase == 'COMPLETED' &&
      passed &&
      cleanupError == null &&
      _goldenGateNames.every((name) => gateStatuses[name] == 'PASSED');
}

Map<String, String> _gateStatuses(
  Map<String, dynamic> json,
  String key,
  List<String> requiredNames,
  Set<String> allowedStatuses,
) {
  final raw = json[key];
  if (raw is! List) throw FormatException('$key must be a list');
  final statuses = <String, String>{};
  for (final item in raw) {
    final gate = _mapValue(item, '$key item');
    final name = _requiredString(gate, 'name');
    final status = _requiredString(gate, 'status');
    if (!requiredNames.contains(name)) {
      throw FormatException('Unknown $key gate name: $name');
    }
    if (statuses.containsKey(name)) {
      throw FormatException('Duplicate $key gate name: $name');
    }
    if (!allowedStatuses.contains(status)) {
      throw FormatException('Unknown $key gate status: $status');
    }
    statuses[name] = status;
  }
  if (statuses.length != requiredNames.length ||
      !statuses.keys.toSet().containsAll(requiredNames)) {
    throw FormatException('$key must contain every required gate exactly once');
  }
  return statuses;
}

String _releaseStatus(Map<String, dynamic> json, String key) {
  final value = _requiredString(json, key);
  if (!_releaseStatuses.contains(value)) {
    throw FormatException('Unknown $key: $value');
  }
  return value;
}

String _sourceCommit(Map<String, dynamic> json, String key) {
  final value = _requiredString(json, key);
  if (!PocketGalleryBuildIdentity.isValidSourceCommit(value)) {
    throw FormatException('$key must be a forty-character hexadecimal commit');
  }
  return value;
}

String _sha256(Map<String, dynamic> json, String key) {
  return _normalizeSha256(_requiredString(json, key), key);
}

String _normalizeSha256(String value, String key) {
  if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value)) {
    throw FormatException('$key must be a sixty-four-character SHA-256');
  }
  return value.toLowerCase();
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) throw FormatException('Missing $key');
  return _mapValue(json[key], key);
}

Map<String, dynamic> _mapValue(Object? value, String key) {
  if (value is! Map) throw FormatException('$key must be an object');
  return Map<String, dynamic>.from(value);
}

String _requiredString(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) throw FormatException('Missing $key');
  final value = json[key];
  if (value is! String) throw FormatException('$key must be a string');
  return value;
}

String _requiredNonEmptyString(Map<String, dynamic> json, String key) {
  final value = _requiredString(json, key);
  if (value.trim().isEmpty) throw FormatException('$key must not be empty');
  return value;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) throw FormatException('Missing $key');
  final value = json[key];
  if (value is! int) throw FormatException('$key must be an integer');
  return value;
}

int? _nullableInt(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) throw FormatException('Missing $key');
  final value = json[key];
  if (value == null) return null;
  if (value is! int) throw FormatException('$key must be an integer or null');
  return value;
}

bool _requiredBool(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) throw FormatException('Missing $key');
  final value = json[key];
  if (value is! bool) throw FormatException('$key must be a boolean');
  return value;
}

const Set<String> _releaseStatuses = <String>{'PASS', 'FAIL', 'BLOCKED'};
const Set<String> _handsetGateStatuses = <String>{
  'PENDING',
  'RUNNING',
  'PASSED',
  'FAILED',
  'TIMEDOUT',
  'BLOCKED',
};
const Set<String> _goldenGateStatuses = _handsetGateStatuses;
const Set<String> _goldenPhases = <String>{
  'PREPARING',
  'RUNNING',
  'CLEANINGUP',
  'COMPLETED',
};

const List<String> _handsetGateNames = <String>[
  'H1_TARGET_DEVICE',
  'H2_BUILD_IDENTITY',
  'H3_UPGRADE_BASELINE',
  'H4_PHONE_FUNCTION_LOOP',
  'H5_VECTOR_3D_TRUTH',
  'H6_VECTOR_INTERACTION',
  'H7_RENDER_PERFORMANCE',
  'H8_MEMORY_THERMAL',
  'H9_DATA_PRESERVATION',
  'H10_REPORT_INTEGRITY',
];

const List<String> _goldenGateNames = <String>[
  'F1_IMPORT_CHUNK',
  'F2_FTS5',
  'F3_EMBEDDING',
  'F4_HYBRID_RERANK',
  'F5_EVIDENCE',
  'F6_GEMMA_CITATION',
  'F7_CHAT_REALWORLD',
  'F8_RUNTIME_LINEAGE',
  'F9_QUERY_VECTOR_IDENTITY',
  'F10_CONTEXT_BUDGET',
];
