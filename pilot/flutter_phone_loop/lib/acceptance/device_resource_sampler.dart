import 'dart:async';
import 'dart:math' as math;

import 'device_diagnostics.dart';

abstract interface class DeviceResourceSampling {
  bool get isRunning;

  Future<void> start();

  Future<ResourceAcceptanceSummary> stop();

  Future<ResourceAcceptanceSummary?> stopIfRunning();
}

final class ResourceAcceptanceSummary {
  ResourceAcceptanceSummary._({
    required List<DeviceResourceSample> samples,
    required List<String> reasonCodes,
    required this.startedAt,
    required this.finishedAt,
    required this.baselinePssKiB,
    required this.finalPssKiB,
    required this.pssGrowthKiB,
    required this.peakPssKiB,
    required this.minimumAvailableMemoryBytes,
    required this.maxThermalStatus,
    required this.peakBatteryTemperatureC,
  })  : samples = List<DeviceResourceSample>.unmodifiable(samples),
        reasonCodes = List<String>.unmodifiable(reasonCodes);

  factory ResourceAcceptanceSummary.evaluate(
    List<DeviceResourceSample> samples, {
    DateTime? startedAt,
    DateTime? finishedAt,
    bool readFailed = false,
  }) {
    final reasons = <String>{};
    if (readFailed || samples.isEmpty) {
      reasons.add('REQUIRED_EVIDENCE_UNAVAILABLE');
    }

    int? baselinePssKiB;
    int? finalPssKiB;
    int? peakPssKiB;
    int? minimumAvailableMemoryBytes;
    int? maxThermalStatus;
    double? peakBatteryTemperatureC;
    for (final sample in samples) {
      final pss = sample.processPssKiB;
      final available = sample.availableMemoryBytes;
      final lowMemory = sample.lowMemory;
      final threshold = sample.lowMemoryThresholdBytes;
      final thermal = sample.thermalStatus;
      if (pss == null ||
          available == null ||
          lowMemory == null ||
          threshold == null ||
          thermal == null) {
        reasons.add('REQUIRED_EVIDENCE_UNAVAILABLE');
      }
      if (pss != null) {
        baselinePssKiB ??= pss;
        finalPssKiB = pss;
        peakPssKiB = math.max(peakPssKiB ?? pss, pss);
      }
      if (available != null) {
        minimumAvailableMemoryBytes = math.min(
          minimumAvailableMemoryBytes ?? available,
          available,
        );
      }
      if (thermal != null) {
        maxThermalStatus = math.max(maxThermalStatus ?? thermal, thermal);
      }
      final battery = sample.batteryTemperatureC;
      if (battery != null && battery.isFinite) {
        peakBatteryTemperatureC = math.max(
          peakBatteryTemperatureC ?? battery,
          battery,
        );
      }
      if (lowMemory == true ||
          (available != null && threshold != null && available < threshold)) {
        reasons.add('MEMORY_PRESSURE');
      }
    }

    final pssGrowthKiB = baselinePssKiB == null || finalPssKiB == null
        ? null
        : finalPssKiB - baselinePssKiB;
    if (pssGrowthKiB != null &&
        pssGrowthKiB > maximumPssGrowthKiB) {
      reasons.add('MEMORY_PRESSURE');
    }
    if (maxThermalStatus != null &&
        maxThermalStatus >= severeThermalStatus) {
      reasons.add('THERMAL_LIMIT_EXCEEDED');
    }

    return ResourceAcceptanceSummary._(
      samples: samples,
      reasonCodes: reasons.toList(growable: false),
      startedAt: startedAt,
      finishedAt: finishedAt,
      baselinePssKiB: baselinePssKiB,
      finalPssKiB: finalPssKiB,
      pssGrowthKiB: pssGrowthKiB,
      peakPssKiB: peakPssKiB,
      minimumAvailableMemoryBytes: minimumAvailableMemoryBytes,
      maxThermalStatus: maxThermalStatus,
      peakBatteryTemperatureC: peakBatteryTemperatureC,
    );
  }

  static const int severeThermalStatus = 3;
  static const int maximumPssGrowthKiB = 512 * 1024;

  final List<DeviceResourceSample> samples;
  final List<String> reasonCodes;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final int? baselinePssKiB;
  final int? finalPssKiB;
  final int? pssGrowthKiB;
  final int? peakPssKiB;
  final int? minimumAvailableMemoryBytes;
  final int? maxThermalStatus;
  final double? peakBatteryTemperatureC;

  bool get passed => reasonCodes.isEmpty;
}

final class DeviceResourceSampler implements DeviceResourceSampling {
  DeviceResourceSampler({
    required this.diagnostics,
    this.interval = const Duration(seconds: 1),
    this.captureTimeout = const Duration(seconds: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DeviceDiagnosticsGateway diagnostics;
  final Duration interval;
  final Duration captureTimeout;
  final DateTime Function() _clock;
  final List<DeviceResourceSample> _samples = <DeviceResourceSample>[];
  Timer? _timer;
  Future<void> _pendingCapture = Future<void>.value();
  DateTime? _startedAt;
  bool _running = false;
  bool _readFailed = false;
  ResourceAcceptanceSummary? _lastSummary;

  @override
  bool get isRunning => _running;

  @override
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _samples.clear();
    _readFailed = false;
    _lastSummary = null;
    _startedAt = _clock();
    await _capture();
    if (!_running) return;
    final period = interval > Duration.zero
        ? interval
        : const Duration(seconds: 1);
    _timer = Timer.periodic(period, (_) {
      if (!_running) return;
      _pendingCapture = _pendingCapture.then((_) => _capture());
    });
  }

  @override
  Future<ResourceAcceptanceSummary> stop() async {
    if (!_running) {
      return _lastSummary ??
          ResourceAcceptanceSummary.evaluate(
            const <DeviceResourceSample>[],
            readFailed: true,
          );
    }
    _running = false;
    _timer?.cancel();
    _timer = null;
    await _pendingCapture;
    await _capture();
    final summary = ResourceAcceptanceSummary.evaluate(
      List<DeviceResourceSample>.of(_samples),
      startedAt: _startedAt,
      finishedAt: _clock(),
      readFailed: _readFailed,
    );
    _startedAt = null;
    _lastSummary = summary;
    return summary;
  }

  @override
  Future<ResourceAcceptanceSummary?> stopIfRunning() async {
    if (!_running) return null;
    return stop();
  }

  Future<void> _capture() async {
    try {
      _samples.add(
        await diagnostics.readResources().timeout(captureTimeout),
      );
    } catch (_) {
      _readFailed = true;
    }
  }
}
