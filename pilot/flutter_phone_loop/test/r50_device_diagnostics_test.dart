import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketgallery_phone_pilot/acceptance/device_diagnostics.dart';
import 'package:pocketgallery_phone_pilot/acceptance/pocketgallery_build_identity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'method channel decodes S24U identity and resources without zero fallbacks',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      MethodCall? keepScreenOnCall;
      messenger.setMockMethodCallHandler(
        MethodChannelDeviceDiagnostics.channel,
        (call) async {
          switch (call.method) {
            case 'identity':
              return <String, Object?>{
                'manufacturer': 'samsung',
                'model': 'SM-S9280',
                'sdkInt': 36,
                'refreshRateHz': 120.0,
                'packageName':
                    'com.qujindai.pocketgallery_phone_pilot.r3',
                'versionName': '0.5.0',
                'versionCode': 2023,
                'signerSha256':
                    PocketGalleryBuildIdentity.canonicalSignerSha256,
                'apkSha256': List<String>.filled(64, 'B').join(),
                'unavailableReasons': <String>[],
              };
            case 'resources':
              return <String, Object?>{
                'capturedAtEpochMs': 1,
                'processPssKiB': 1024,
                'availableMemoryBytes': 8000000000,
                'totalMemoryBytes': 12000000000,
                'lowMemory': false,
                'lowMemoryThresholdBytes': 500000000,
                'thermalStatus': 2,
                'batteryTemperatureC': 35.2,
                'unavailableReasons': <String>[],
              };
            case 'keepScreenOn':
              keepScreenOnCall = call;
              return null;
            default:
              throw MissingPluginException(call.method);
          }
        },
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          MethodChannelDeviceDiagnostics.channel,
          null,
        ),
      );

      const gateway = MethodChannelDeviceDiagnostics();
      final identity = await gateway.readIdentity();
      final resources = await gateway.readResources();
      await gateway.setKeepScreenOn(true);

      expect(identity.manufacturer, 'samsung');
      expect(identity.model, 'SM-S9280');
      expect(identity.sdkInt, 36);
      expect(identity.refreshRateHz, 120.0);
      expect(identity.packageName, PocketGalleryBuildIdentity.packageName);
      expect(identity.versionName, '0.5.0');
      expect(identity.versionCode, 2023);
      expect(
        identity.signerSha256,
        PocketGalleryBuildIdentity.canonicalSignerSha256,
      );
      expect(identity.apkSha256, List<String>.filled(64, 'b').join());
      expect(identity.sourceCommit, PocketGalleryBuildIdentity.sourceCommit);
      expect(identity.isTargetS24Ultra, isTrue);

      expect(
        resources.capturedAt,
        DateTime.fromMillisecondsSinceEpoch(1, isUtc: true),
      );
      expect(resources.processPssKiB, 1024);
      expect(resources.availableMemoryBytes, 8000000000);
      expect(resources.totalMemoryBytes, 12000000000);
      expect(resources.lowMemory, isFalse);
      expect(resources.lowMemoryThresholdBytes, 500000000);
      expect(resources.thermalStatus, 2);
      expect(resources.batteryTemperatureC, 35.2);

      expect(keepScreenOnCall?.method, 'keepScreenOn');
      expect(keepScreenOnCall?.arguments, <String, Object?>{'enabled': true});
    },
  );

  testWidgets('missing native values stay null and carry stable reasons', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      MethodChannelDeviceDiagnostics.channel,
      (call) async => switch (call.method) {
        'identity' => <String, Object?>{
          'unavailableReasons': <String>['NATIVE_IDENTITY_PARTIAL'],
        },
        'resources' => <String, Object?>{
          'unavailableReasons': <String>['NATIVE_RESOURCES_PARTIAL'],
        },
        _ => throw MissingPluginException(call.method),
      },
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        MethodChannelDeviceDiagnostics.channel,
        null,
      ),
    );

    const gateway = MethodChannelDeviceDiagnostics();
    final identity = await gateway.readIdentity();
    final resources = await gateway.readResources();

    expect(identity.manufacturer, isNull);
    expect(identity.model, isNull);
    expect(identity.sdkInt, isNull);
    expect(identity.refreshRateHz, isNull);
    expect(identity.versionCode, isNull);
    expect(identity.signerSha256, isNull);
    expect(identity.apkSha256, isNull);
    expect(identity.isTargetS24Ultra, isFalse);
    expect(
      identity.unavailableReasons,
      containsAll(<String>[
        'NATIVE_IDENTITY_PARTIAL',
        'MANUFACTURER_UNAVAILABLE',
        'MODEL_UNAVAILABLE',
        'SDK_INT_UNAVAILABLE',
        'REFRESH_RATE_UNAVAILABLE',
        'SIGNER_SHA256_UNAVAILABLE',
        'APK_SHA256_UNAVAILABLE',
        'SOURCE_COMMIT_UNAVAILABLE',
      ]),
    );

    expect(resources.capturedAt, isNull);
    expect(resources.processPssKiB, isNull);
    expect(resources.availableMemoryBytes, isNull);
    expect(resources.totalMemoryBytes, isNull);
    expect(resources.lowMemory, isNull);
    expect(resources.lowMemoryThresholdBytes, isNull);
    expect(resources.thermalStatus, isNull);
    expect(resources.batteryTemperatureC, isNull);
    expect(
      resources.unavailableReasons,
      containsAll(<String>[
        'NATIVE_RESOURCES_PARTIAL',
        'CAPTURED_AT_UNAVAILABLE',
        'PROCESS_PSS_UNAVAILABLE',
        'AVAILABLE_MEMORY_UNAVAILABLE',
        'TOTAL_MEMORY_UNAVAILABLE',
        'LOW_MEMORY_UNAVAILABLE',
        'LOW_MEMORY_THRESHOLD_UNAVAILABLE',
        'THERMAL_STATUS_UNAVAILABLE',
        'BATTERY_TEMPERATURE_UNAVAILABLE',
      ]),
    );
  });
}
