import 'package:flutter_test/flutter_test.dart';
import 'package:pocketgallery_phone_pilot/acceptance/device_diagnostics.dart';
import 'package:pocketgallery_phone_pilot/acceptance/device_resource_sampler.dart';

void main() {
  group('ResourceAcceptanceSummary', () {
    test('accepts MODERATE thermal state and the exact PSS growth limit', () {
      final summary = ResourceAcceptanceSummary.evaluate(<DeviceResourceSample>[
        _sample(pssKiB: 100000, thermalStatus: 2),
        _sample(pssKiB: 100000 + 512 * 1024, thermalStatus: 2),
      ]);

      expect(summary.passed, isTrue);
      expect(summary.reasonCodes, isEmpty);
      expect(summary.maxThermalStatus, 2);
      expect(summary.pssGrowthKiB, 512 * 1024);
    });

    test('rejects SEVERE thermal state', () {
      final summary = ResourceAcceptanceSummary.evaluate(<DeviceResourceSample>[
        _sample(thermalStatus: 2),
        _sample(thermalStatus: 3),
      ]);

      expect(summary.passed, isFalse);
      expect(summary.reasonCodes, contains('THERMAL_LIMIT_EXCEEDED'));
    });

    test('rejects Android low-memory state', () {
      final summary = ResourceAcceptanceSummary.evaluate(<DeviceResourceSample>[
        _sample(),
        _sample(lowMemory: true),
      ]);

      expect(summary.reasonCodes, contains('MEMORY_PRESSURE'));
    });

    test('rejects available memory below Android threshold', () {
      final summary = ResourceAcceptanceSummary.evaluate(<DeviceResourceSample>[
        _sample(),
        _sample(
          availableMemoryBytes: 255 * 1024 * 1024,
          lowMemoryThresholdBytes: 256 * 1024 * 1024,
        ),
      ]);

      expect(summary.reasonCodes, contains('MEMORY_PRESSURE'));
      expect(summary.minimumAvailableMemoryBytes, 255 * 1024 * 1024);
    });

    test('rejects final PSS growth above 512 MiB', () {
      final summary = ResourceAcceptanceSummary.evaluate(<DeviceResourceSample>[
        _sample(pssKiB: 100000),
        _sample(pssKiB: 100001 + 512 * 1024),
      ]);

      expect(summary.reasonCodes, contains('MEMORY_PRESSURE'));
    });

    test('keeps battery temperature and peak PSS as evidence only', () {
      final summary = ResourceAcceptanceSummary.evaluate(<DeviceResourceSample>[
        _sample(pssKiB: 100000, batteryTemperatureC: 58),
        _sample(pssKiB: 700000, batteryTemperatureC: 61),
        _sample(pssKiB: 100000, batteryTemperatureC: 59),
      ]);

      expect(summary.passed, isTrue);
      expect(summary.peakPssKiB, 700000);
      expect(summary.peakBatteryTemperatureC, 61);
    });
  });

  test('sampler maps read errors to required evidence unavailable', () async {
    final diagnostics = _FakeDiagnostics(<Object>[StateError('native read')]);
    final sampler = DeviceResourceSampler(
      diagnostics: diagnostics,
      interval: const Duration(days: 1),
    );

    await sampler.start();
    final summary = await sampler.stop();

    expect(summary.reasonCodes, contains('REQUIRED_EVIDENCE_UNAVAILABLE'));
    expect(summary.samples, isEmpty);
  });

  test('stopIfRunning captures one final sample and is idempotent', () async {
    final diagnostics = _FakeDiagnostics(<Object>[
      _sample(pssKiB: 100000),
      _sample(pssKiB: 100100),
    ]);
    final sampler = DeviceResourceSampler(
      diagnostics: diagnostics,
      interval: const Duration(days: 1),
    );

    expect(sampler.isRunning, isFalse);
    await sampler.start();
    expect(sampler.isRunning, isTrue);
    final first = await sampler.stopIfRunning();
    final second = await sampler.stopIfRunning();

    expect(first, isNotNull);
    expect(first!.samples, hasLength(2));
    expect(second, isNull);
    expect(diagnostics.resourceReads, 2);
    expect(sampler.isRunning, isFalse);
  });
}

DeviceResourceSample _sample({
  int pssKiB = 100000,
  int availableMemoryBytes = 2 * 1024 * 1024 * 1024,
  int lowMemoryThresholdBytes = 256 * 1024 * 1024,
  bool lowMemory = false,
  int thermalStatus = 0,
  double batteryTemperatureC = 32,
}) {
  return DeviceResourceSample.fromMap(<String, Object?>{
    'capturedAtEpochMs': DateTime.utc(2026, 9, 1).millisecondsSinceEpoch,
    'processPssKiB': pssKiB,
    'availableMemoryBytes': availableMemoryBytes,
    'totalMemoryBytes': 12 * 1024 * 1024 * 1024,
    'lowMemory': lowMemory,
    'lowMemoryThresholdBytes': lowMemoryThresholdBytes,
    'thermalStatus': thermalStatus,
    'batteryTemperatureC': batteryTemperatureC,
    'unavailableReasons': const <String>[],
  });
}

final class _FakeDiagnostics implements DeviceDiagnosticsGateway {
  _FakeDiagnostics(this.outcomes);

  final List<Object> outcomes;
  int resourceReads = 0;

  @override
  Future<DeviceIdentitySnapshot> readIdentity() {
    throw UnimplementedError();
  }

  @override
  Future<DeviceResourceSample> readResources() async {
    final outcome = outcomes[resourceReads++];
    if (outcome is DeviceResourceSample) return outcome;
    throw outcome;
  }

  @override
  Future<void> setKeepScreenOn(bool enabled) async {}
}
