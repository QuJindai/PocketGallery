import 'package:flutter/services.dart';

import 'pocketgallery_build_identity.dart';

abstract interface class DeviceDiagnosticsGateway {
  Future<DeviceIdentitySnapshot> readIdentity();

  Future<DeviceResourceSample> readResources();

  Future<void> setKeepScreenOn(bool enabled);
}

final class MethodChannelDeviceDiagnostics implements DeviceDiagnosticsGateway {
  const MethodChannelDeviceDiagnostics();

  static const MethodChannel channel = MethodChannel(
    'pocketgallery/device_diagnostics',
  );

  @override
  Future<DeviceIdentitySnapshot> readIdentity() async {
    final value = await channel.invokeMapMethod<String, Object?>('identity');
    return DeviceIdentitySnapshot.fromMap(value ?? const <String, Object?>{});
  }

  @override
  Future<DeviceResourceSample> readResources() async {
    final value = await channel.invokeMapMethod<String, Object?>('resources');
    return DeviceResourceSample.fromMap(value ?? const <String, Object?>{});
  }

  @override
  Future<void> setKeepScreenOn(bool enabled) {
    return channel.invokeMethod<void>('keepScreenOn', <String, Object?>{
      'enabled': enabled,
    });
  }
}

final class DeviceIdentitySnapshot {
  DeviceIdentitySnapshot._({
    required this.manufacturer,
    required this.model,
    required this.sdkInt,
    required this.refreshRateHz,
    required this.packageName,
    required this.versionName,
    required this.versionCode,
    required this.signerSha256,
    required this.apkSha256,
    required this.sourceCommit,
    required List<String> unavailableReasons,
  }) : unavailableReasons = List<String>.unmodifiable(unavailableReasons);

  factory DeviceIdentitySnapshot.fromMap(
    Map<String, Object?> value, {
    String sourceCommit = PocketGalleryBuildIdentity.sourceCommit,
  }) {
    final reasons = _decodeReasons(value['unavailableReasons']);
    final manufacturer = _stringOrNull(value['manufacturer']);
    final model = _stringOrNull(value['model']);
    final sdkInt = _intOrNull(value['sdkInt']);
    final refreshRateHz = _doubleOrNull(value['refreshRateHz']);
    final packageName = _stringOrNull(value['packageName']);
    final versionName = _stringOrNull(value['versionName']);
    final versionCode = _intOrNull(value['versionCode']);
    final signerSha256 = _sha256OrNull(value['signerSha256']);
    final apkSha256 = _sha256OrNull(value['apkSha256']);
    _recordMissing(reasons, manufacturer, 'MANUFACTURER_UNAVAILABLE');
    _recordMissing(reasons, model, 'MODEL_UNAVAILABLE');
    _recordMissing(reasons, sdkInt, 'SDK_INT_UNAVAILABLE');
    _recordMissing(reasons, refreshRateHz, 'REFRESH_RATE_UNAVAILABLE');
    _recordMissing(reasons, packageName, 'PACKAGE_NAME_UNAVAILABLE');
    _recordMissing(reasons, versionName, 'VERSION_NAME_UNAVAILABLE');
    _recordMissing(reasons, versionCode, 'VERSION_CODE_UNAVAILABLE');
    _recordMissing(reasons, signerSha256, 'SIGNER_SHA256_UNAVAILABLE');
    _recordMissing(reasons, apkSha256, 'APK_SHA256_UNAVAILABLE');
    if (!PocketGalleryBuildIdentity.isValidSourceCommit(sourceCommit)) {
      reasons.add('SOURCE_COMMIT_UNAVAILABLE');
    }

    return DeviceIdentitySnapshot._(
      manufacturer: manufacturer,
      model: model,
      sdkInt: sdkInt,
      refreshRateHz: refreshRateHz,
      packageName: packageName,
      versionName: versionName,
      versionCode: versionCode,
      signerSha256: signerSha256,
      apkSha256: apkSha256,
      sourceCommit: sourceCommit,
      unavailableReasons: reasons,
    );
  }

  final String? manufacturer;
  final String? model;
  final int? sdkInt;
  final double? refreshRateHz;
  final String? packageName;
  final String? versionName;
  final int? versionCode;
  final String? signerSha256;
  final String? apkSha256;
  final String sourceCommit;
  final List<String> unavailableReasons;

  bool get isTargetS24Ultra {
    final normalizedManufacturer = manufacturer?.trim().toLowerCase();
    final normalizedModel = model?.trim();
    return normalizedManufacturer == 'samsung' &&
        normalizedModel != null &&
        RegExp(
          r'^SM-S928[A-Z0-9]*$',
          caseSensitive: false,
        ).hasMatch(normalizedModel);
  }
}

final class DeviceResourceSample {
  DeviceResourceSample._({
    required this.capturedAt,
    required this.processPssKiB,
    required this.availableMemoryBytes,
    required this.totalMemoryBytes,
    required this.lowMemory,
    required this.lowMemoryThresholdBytes,
    required this.thermalStatus,
    required this.batteryTemperatureC,
    required List<String> unavailableReasons,
  }) : unavailableReasons = List<String>.unmodifiable(unavailableReasons);

  factory DeviceResourceSample.fromMap(Map<String, Object?> value) {
    final reasons = _decodeReasons(value['unavailableReasons']);
    final capturedAt = _dateTimeOrNull(value['capturedAtEpochMs']);
    final processPssKiB = _intOrNull(value['processPssKiB']);
    final availableMemoryBytes = _intOrNull(value['availableMemoryBytes']);
    final totalMemoryBytes = _intOrNull(value['totalMemoryBytes']);
    final lowMemory = _boolOrNull(value['lowMemory']);
    final lowMemoryThresholdBytes = _intOrNull(
      value['lowMemoryThresholdBytes'],
    );
    final thermalStatus = _intOrNull(value['thermalStatus']);
    final batteryTemperatureC = _doubleOrNull(value['batteryTemperatureC']);

    _recordMissing(reasons, capturedAt, 'CAPTURED_AT_UNAVAILABLE');
    _recordMissing(reasons, processPssKiB, 'PROCESS_PSS_UNAVAILABLE');
    _recordMissing(
      reasons,
      availableMemoryBytes,
      'AVAILABLE_MEMORY_UNAVAILABLE',
    );
    _recordMissing(reasons, totalMemoryBytes, 'TOTAL_MEMORY_UNAVAILABLE');
    _recordMissing(reasons, lowMemory, 'LOW_MEMORY_UNAVAILABLE');
    _recordMissing(
      reasons,
      lowMemoryThresholdBytes,
      'LOW_MEMORY_THRESHOLD_UNAVAILABLE',
    );
    _recordMissing(reasons, thermalStatus, 'THERMAL_STATUS_UNAVAILABLE');
    _recordMissing(
      reasons,
      batteryTemperatureC,
      'BATTERY_TEMPERATURE_UNAVAILABLE',
    );

    return DeviceResourceSample._(
      capturedAt: capturedAt,
      processPssKiB: processPssKiB,
      availableMemoryBytes: availableMemoryBytes,
      totalMemoryBytes: totalMemoryBytes,
      lowMemory: lowMemory,
      lowMemoryThresholdBytes: lowMemoryThresholdBytes,
      thermalStatus: thermalStatus,
      batteryTemperatureC: batteryTemperatureC,
      unavailableReasons: reasons,
    );
  }

  final DateTime? capturedAt;
  final int? processPssKiB;
  final int? availableMemoryBytes;
  final int? totalMemoryBytes;
  final bool? lowMemory;
  final int? lowMemoryThresholdBytes;
  final int? thermalStatus;
  final double? batteryTemperatureC;
  final List<String> unavailableReasons;
}

List<String> _decodeReasons(Object? value) {
  if (value is! Iterable<Object?>) return <String>[];
  final reasons = <String>{};
  for (final item in value) {
    final reason = _stringOrNull(item);
    if (reason != null) reasons.add(reason);
  }
  return reasons.toList(growable: true);
}

void _recordMissing(List<String> reasons, Object? value, String reason) {
  if (value == null && !reasons.contains(reason)) reasons.add(reason);
}

String? _stringOrNull(Object? value) {
  if (value is! String) return null;
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

String? _sha256OrNull(Object? value) {
  final normalized = _stringOrNull(value)?.toLowerCase();
  if (normalized == null) return null;
  return RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized) ? normalized : null;
}

int? _intOrNull(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.truncateToDouble()) {
    return value.toInt();
  }
  return null;
}

double? _doubleOrNull(Object? value) {
  if (value is! num || !value.isFinite) return null;
  return value.toDouble();
}

bool? _boolOrNull(Object? value) => value is bool ? value : null;

DateTime? _dateTimeOrNull(Object? value) {
  final epochMilliseconds = _intOrNull(value);
  if (epochMilliseconds == null) return null;
  try {
    return DateTime.fromMillisecondsSinceEpoch(epochMilliseconds, isUtc: true);
  } on ArgumentError {
    return null;
  }
}
