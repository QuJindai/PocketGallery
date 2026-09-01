import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../services/golden_test_state.dart';
import 'handset_acceptance_models.dart';
import 'pocketgallery_build_identity.dart';

abstract final class HandsetReportExporter {
  static final RegExp _prohibitedKey = RegExp(
    r'(authorization|credential|password|secret|token|vector|raw.*text|document.*text|chunk.*text|content|body)',
    caseSensitive: false,
  );
  static final RegExp _sensitiveText = RegExp(
    r'(bearer\s+|hf_[a-z0-9]|private\s+document|authorization|credential|password|secret|token)',
    caseSensitive: false,
  );
  static final RegExp _sha256 = RegExp(r'^[0-9a-fA-F]{64}$');
  static final RegExp _stableReasonCode = RegExp(
    r'^[A-Z][A-Z0-9_]*(?:\|[A-Z][A-Z0-9_]*)*$',
  );

  static const Map<String, String> _messages = <String, String>{
    'TARGET_MANUFACTURER': 'Handset manufacturer measured.',
    'TARGET_MODEL': 'Handset model measured.',
    'PACKAGE_NAME': 'Application package measured.',
    'VERSION_CODE': 'Application version code measured.',
    'SIGNER_SHA256': 'Signing certificate digest measured.',
    'APK_SHA256': 'Installed APK digest measured.',
    'SOURCE_COMMIT': 'Build source identity measured.',
    'BASELINE_VERSION_CODE': 'Upgrade baseline version measured.',
    'SAFE_LATENCY_MS': 'Frame latency measured.',
  };

  static Uint8List encodeRedacted(HandsetAcceptanceSnapshot snapshot) {
    _validateMergeCandidate(snapshot);
    final h4 = _gate(snapshot, 'H4_PHONE_FUNCTION_LOOP');
    final report = <String, Object?>{
      'schema': 'pocketgallery.r50.handset-acceptance.v1',
      'schemaVersion': 1,
      'runId': _safeIdentifier(snapshot.runId),
      'startedAt': snapshot.startedAt.toUtc().toIso8601String(),
      'updatedAt': snapshot.updatedAt.toUtc().toIso8601String(),
      'durationMs': snapshot.updatedAt
          .difference(snapshot.startedAt)
          .inMilliseconds,
      'PHONE_FUNCTION_LOOP': _phoneFunctionLoop(h4?.status),
      'DEVICE_ACCEPTANCE': snapshot.verdict.name.toUpperCase(),
      'MERGE_CANDIDATE': snapshot.mergeCandidate,
      'baselineVersionCode': snapshot.baselineVersionCode,
      'identity': _identitySummary(snapshot),
      'gates': <Map<String, Object?>>[
        for (final gate in snapshot.gates) _gateSummary(gate),
      ],
      'nestedGolden': _nestedGoldenSummary(snapshot),
    };
    validateNoProhibitedKeys(report);
    return Uint8List.fromList(utf8.encode(jsonEncode(report)));
  }

  static void validateNoProhibitedKeys(Map<String, Object?> value) {
    _validateValue(value);
  }

  static Future<Uri?> saveWithPicker(Uint8List bytes, String fileName) {
    return FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: 'application/json',
      type: FileType.custom,
      allowedExtensions: const <String>['json'],
    );
  }

  static Map<String, Object?> _gateSummary(HandsetGateSnapshot gate) {
    return <String, Object?>{
      'name': gate.name,
      'status': gate.status.name.toUpperCase(),
      'startedAt': gate.startedAt?.toUtc().toIso8601String(),
      'finishedAt': gate.finishedAt?.toUtc().toIso8601String(),
      'durationMs': gate.duration?.inMilliseconds,
      'evidence': <Map<String, Object?>>[
        for (final evidence in gate.evidence) _evidenceSummary(evidence),
      ],
    };
  }

  static Map<String, Object?> _evidenceSummary(AcceptanceEvidence evidence) {
    return <String, Object?>{
      'code': evidence.code,
      'method': evidence.method.name.toUpperCase(),
      'source': _safeSource(evidence.source),
      'actual': _approvedActual(evidence.code, evidence.actual),
      'threshold': _approvedThreshold(evidence.threshold),
      'unit': _approvedUnit(evidence.unit),
      'available': evidence.available,
      'message':
          _messages[evidence.code] ??
          (evidence.available ? 'Evidence recorded.' : 'Evidence unavailable.'),
    };
  }

  static Map<String, Object?>? _identitySummary(
    HandsetAcceptanceSnapshot snapshot,
  ) {
    final values = <String, Object?>{
      'manufacturer': _evidenceActual(snapshot, 'TARGET_MANUFACTURER'),
      'model': _evidenceActual(snapshot, 'TARGET_MODEL'),
      'packageName': _evidenceActual(snapshot, 'PACKAGE_NAME'),
      'versionCode': _evidenceActual(snapshot, 'VERSION_CODE'),
      'signerSha256': _evidenceActual(snapshot, 'SIGNER_SHA256'),
      'apkSha256': _evidenceActual(snapshot, 'APK_SHA256'),
      'sourceCommit': _evidenceActual(snapshot, 'SOURCE_COMMIT'),
    };
    final approved = <String, Object?>{
      for (final entry in values.entries)
        entry.key: _approvedActual(_identityCode(entry.key), entry.value),
    };
    return approved.values.every((value) => value == null) ? null : approved;
  }

  static String _identityCode(String field) => switch (field) {
    'manufacturer' => 'TARGET_MANUFACTURER',
    'model' => 'TARGET_MODEL',
    'packageName' => 'PACKAGE_NAME',
    'versionCode' => 'VERSION_CODE',
    'signerSha256' => 'SIGNER_SHA256',
    'apkSha256' => 'APK_SHA256',
    'sourceCommit' => 'SOURCE_COMMIT',
    _ => '',
  };

  static Map<String, Object?>? _nestedGoldenSummary(
    HandsetAcceptanceSnapshot snapshot,
  ) {
    final nested = snapshot.nestedGolden;
    if (nested == null) return null;
    return <String, Object?>{
      'schemaVersion': nested.schemaVersion,
      'runId': _safeIdentifier(nested.runId),
      'phase': nested.phase.name.toUpperCase(),
      'passed': nested.passed,
      'cleanupError': nested.cleanupError == null
          ? null
          : 'GOLDEN_CLEANUP_FAILED',
      'startedAt': nested.startedAt.toUtc().toIso8601String(),
      'updatedAt': nested.updatedAt.toUtc().toIso8601String(),
      'durationMs': nested.elapsed.inMilliseconds,
      'gates': <Map<String, Object?>>[
        for (final gate in nested.gates)
          <String, Object?>{
            'name': gate.name,
            'status': gate.status.name.toUpperCase(),
            'reasonCode': _goldenGateReason(gate.status, gate.detail),
            'timeoutMs': gate.timeout.inMilliseconds,
            'startedAt': gate.startedAt?.toUtc().toIso8601String(),
            'finishedAt': gate.finishedAt?.toUtc().toIso8601String(),
            'durationMs': gate.duration?.inMilliseconds,
          },
      ],
    };
  }

  static String? _goldenGateReason(GoldenGateStatus status, String detail) {
    if (status == GoldenGateStatus.passed) return null;
    final normalized = detail.trim();
    if (_stableReasonCode.hasMatch(normalized)) return normalized;
    return switch (status) {
      GoldenGateStatus.failed => 'GATE_FAILED',
      GoldenGateStatus.timedOut => 'GATE_TIMEOUT',
      GoldenGateStatus.blocked => 'GATE_BLOCKED',
      GoldenGateStatus.pending || GoldenGateStatus.running => 'GATE_INCOMPLETE',
      GoldenGateStatus.passed => null,
    };
  }

  static Object? _approvedActual(String code, Object? value) {
    if (value == null || value is num || value is bool) return value;
    if (value is! String || _sensitiveText.hasMatch(value)) return null;
    final normalized = value.trim();
    return switch (code) {
      'TARGET_MANUFACTURER' =>
        normalized.toLowerCase() == 'samsung' ? normalized : null,
      'TARGET_MODEL' =>
        RegExp(r'^SM-S928[A-Z0-9]*$', caseSensitive: false).hasMatch(normalized)
            ? normalized
            : null,
      'PACKAGE_NAME' =>
        normalized == PocketGalleryBuildIdentity.packageName
            ? normalized
            : null,
      'SIGNER_SHA256' || 'APK_SHA256' =>
        _sha256.hasMatch(normalized) ? normalized.toLowerCase() : null,
      'SOURCE_COMMIT' =>
        PocketGalleryBuildIdentity.isValidSourceCommit(normalized)
            ? normalized.toLowerCase()
            : null,
      'VERSION_NAME' =>
        RegExp(r'^[0-9]+(?:\.[0-9]+){1,3}$').hasMatch(normalized)
            ? normalized
            : null,
      _ => null,
    };
  }

  static Object? _approvedThreshold(Object? value) {
    if (value == null || value is num || value is bool) return value;
    if (value is! String ||
        value.length > 128 ||
        _sensitiveText.hasMatch(value)) {
      return null;
    }
    return RegExp(r'^[A-Za-z0-9^$.*+?()\[\]{}|\\._:/ -]+$').hasMatch(value)
        ? value
        : null;
  }

  static String? _approvedUnit(String? value) {
    const units = <String>{
      'ms',
      'Hz',
      'KiB',
      'MiB',
      'bytes',
      '°C',
      '%',
      'frames',
      'count',
    };
    return units.contains(value) ? value : null;
  }

  static String? _safeSource(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty ||
        normalized.length > 120 ||
        _sensitiveText.hasMatch(normalized)) {
      return null;
    }
    return RegExp(r'^[A-Za-z0-9._:/ -]+$').hasMatch(normalized)
        ? normalized
        : null;
  }

  static String _safeIdentifier(String value) {
    final normalized = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    if (normalized.isEmpty) return 'run';
    return normalized.length <= 120 ? normalized : normalized.substring(0, 120);
  }

  static String _phoneFunctionLoop(HandsetGateStatus? status) {
    return switch (status) {
      HandsetGateStatus.passed => 'PASS',
      HandsetGateStatus.failed || HandsetGateStatus.timedOut => 'FAIL',
      _ => 'BLOCKED',
    };
  }

  static HandsetGateSnapshot? _gate(
    HandsetAcceptanceSnapshot snapshot,
    String name,
  ) {
    for (final gate in snapshot.gates) {
      if (gate.name == name) return gate;
    }
    return null;
  }

  static Object? _evidenceActual(
    HandsetAcceptanceSnapshot snapshot,
    String code,
  ) {
    for (final gate in snapshot.gates) {
      for (final evidence in gate.evidence) {
        if (evidence.code == code && evidence.available) return evidence.actual;
      }
    }
    return null;
  }

  static void _validateMergeCandidate(HandsetAcceptanceSnapshot snapshot) {
    if (!snapshot.mergeCandidate) return;
    final requiredGatesPassed = handsetGateWeights.keys.every(
      (name) => _gate(snapshot, name)?.status == HandsetGateStatus.passed,
    );
    final manufacturer = _evidenceActual(snapshot, 'TARGET_MANUFACTURER');
    final model = _evidenceActual(snapshot, 'TARGET_MODEL');
    final packageName = _evidenceActual(snapshot, 'PACKAGE_NAME');
    final versionCode = _evidenceActual(snapshot, 'VERSION_CODE');
    final signer = _evidenceActual(snapshot, 'SIGNER_SHA256');
    final apkDigest = _evidenceActual(snapshot, 'APK_SHA256');
    final sourceCommit = _evidenceActual(snapshot, 'SOURCE_COMMIT');
    final baselineEvidence = _evidenceActual(snapshot, 'BASELINE_VERSION_CODE');
    final eligible =
        snapshot.verdict == AcceptanceVerdict.pass &&
        requiredGatesPassed &&
        snapshot.baselineVersionCode != null &&
        snapshot.baselineVersionCode! < 2023 &&
        baselineEvidence == snapshot.baselineVersionCode &&
        manufacturer is String &&
        manufacturer.toLowerCase() == 'samsung' &&
        model is String &&
        RegExp(r'^SM-S928[A-Z0-9]*$', caseSensitive: false).hasMatch(model) &&
        packageName == PocketGalleryBuildIdentity.packageName &&
        versionCode == 2023 &&
        signer is String &&
        signer.toLowerCase() ==
            PocketGalleryBuildIdentity.canonicalSignerSha256 &&
        apkDigest is String &&
        _sha256.hasMatch(apkDigest) &&
        sourceCommit is String &&
        PocketGalleryBuildIdentity.isValidSourceCommit(sourceCommit);
    if (!eligible) {
      throw const FormatException(
        'MERGE_CANDIDATE prerequisites are incomplete',
      );
    }
  }

  static void _validateValue(Object? value) {
    if (value == null || value is String || value is bool) {
      return;
    }
    if (value is num) {
      if (!value.isFinite) {
        throw const FormatException('Report numbers must be finite');
      }
      return;
    }
    if (value is List) {
      for (final item in value) {
        _validateValue(item);
      }
      return;
    }
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key;
        if (key is! String) {
          throw const FormatException('Report keys must be strings');
        }
        if (_prohibitedKey.hasMatch(key)) {
          throw FormatException('Prohibited report key: $key');
        }
        _validateValue(entry.value);
      }
      return;
    }
    throw FormatException('Unsupported report value: ${value.runtimeType}');
  }
}
