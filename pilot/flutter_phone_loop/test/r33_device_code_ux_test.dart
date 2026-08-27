import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('R3.3 copies the HF user code before opening the browser', () {
    final oauth = File('lib/services/hf_oauth_device_service.dart').readAsStringSync();

    expect(oauth, contains("package:flutter/services.dart"));
    expect(oauth, contains('Clipboard.setData'));
    expect(oauth, contains('authorization.userCode'));
  });

  test('R3.3 can recover and surface the persisted pending user code', () {
    final oauth = File('lib/services/hf_oauth_device_service.dart').readAsStringSync();
    final setup = File('lib/services/model_setup_service.dart').readAsStringSync();

    expect(oauth, contains('getPendingUserCode'));
    expect(setup, contains('getPendingUserCode'));
    expect(setup, contains('已复制到剪贴板'));
  });

  test('R3.3 explicitly tells the user the HF page may require one paste', () {
    final home = File('lib/ui/home_page.dart').readAsStringSync();

    expect(home, contains('授权码已自动复制'));
    expect(home, contains('粘贴'));
  });

  test('R3.3 remains an in-place R3 upgrade', () {
    final bootstrap = File('scripts/bootstrap_android.sh').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(bootstrap, contains('com.qujindai.pocketgallery_phone_pilot.r3'));
    expect(pubspec, contains('version: 0.3.3+6'));
  });
}
