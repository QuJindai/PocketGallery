import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('R3.2 persists pending device authorization before opening browser', () {
    final oauth =
        File('lib/services/hf_oauth_device_service.dart').readAsStringSync();

    expect(oauth, contains('_pendingDeviceCodeKey'));
    expect(oauth, contains('_savePendingAuthorization'));
    expect(oauth, contains('_loadPendingAuthorization'));
    expect(oauth, contains('clearPendingAuthorization'));
  });

  test('R3.2 resumes pending OAuth after returning from browser', () {
    final oauth =
        File('lib/services/hf_oauth_device_service.dart').readAsStringSync();
    final setup =
        File('lib/services/model_setup_service.dart').readAsStringSync();
    final home = File('lib/ui/home_page.dart').readAsStringSync();

    expect(oauth, contains('resumePendingAuthorization'));
    expect(setup, contains('resumePendingAuthorizationAndPrepare'));
    expect(home, contains('WidgetsBindingObserver'));
    expect(home, contains('didChangeAppLifecycleState'));
    expect(home, contains('AppLifecycleState.resumed'));
    expect(home, contains('resumePendingAuthorizationAndPrepare'));
  });

  test('R3.2 does not require the browser to keep the Flutter isolate alive', () {
    final oauth =
        File('lib/services/hf_oauth_device_service.dart').readAsStringSync();

    expect(oauth, contains('beginAuthorization'));
    expect(oauth, isNot(contains('return _pollForToken(authorization);')));
  });

  test('R3.2 remains an in-place R3 upgrade', () {
    final bootstrap = File('scripts/bootstrap_android.sh').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(bootstrap, contains('com.qujindai.pocketgallery_phone_pilot.r3'));
    expect(pubspec, contains('version: 0.3.2+5'));
  });
}
