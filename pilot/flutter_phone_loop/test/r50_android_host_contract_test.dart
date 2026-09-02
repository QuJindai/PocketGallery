import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('bootstrap installs the first-party diagnostics host safely', () async {
    final sourceRoot = Directory.current;
    final temporaryRoot = await Directory.systemTemp.createTemp(
      'pocketgallery-r50-android-host-',
    );
    addTearDown(() => temporaryRoot.delete(recursive: true));

    await _copyFile(
      p.join(sourceRoot.path, 'scripts', 'bootstrap_android.sh'),
      p.join(temporaryRoot.path, 'scripts', 'bootstrap_android.sh'),
    );
    for (final name in <String>[
      'MainActivity.kt',
      'DeviceDiagnosticsHost.kt',
    ]) {
      await _copyFile(
        p.join(sourceRoot.path, 'android_host', name),
        p.join(temporaryRoot.path, 'android_host', name),
      );
    }
    await File(p.join(temporaryRoot.path, 'pubspec.yaml'))
        .writeAsString('name: pocketgallery_phone_pilot\n');

    final fakeBin = Directory(p.join(temporaryRoot.path, 'fake-bin'));
    await fakeBin.create(recursive: true);
    final fakeFlutter = File(p.join(fakeBin.path, 'flutter'));
    await fakeFlutter.writeAsString(_fakeFlutter);
    final chmod = await Process.run('chmod', <String>['+x', fakeFlutter.path]);
    expect(chmod.exitCode, 0, reason: '${chmod.stderr}');

    final run = await Process.run(
      'bash',
      <String>['scripts/bootstrap_android.sh'],
      workingDirectory: temporaryRoot.path,
      environment: <String, String>{
        ...Platform.environment,
        'PATH': '${fakeBin.path}:${Platform.environment['PATH'] ?? ''}',
      },
    );

    expect(
      run.exitCode,
      0,
      reason: 'stdout:\n${run.stdout}\nstderr:\n${run.stderr}',
    );
    expect('${run.stdout}', contains('BOOTSTRAP_PASS'));

    final kotlinDirectory = p.join(
      temporaryRoot.path,
      'android',
      'app',
      'src',
      'main',
      'kotlin',
      'com',
      'qujindai',
      'pocketgallery_phone_pilot',
    );
    for (final name in <String>[
      'MainActivity.kt',
      'DeviceDiagnosticsHost.kt',
    ]) {
      final template = await File(
        p.join(temporaryRoot.path, 'android_host', name),
      ).readAsBytes();
      final installed = await File(p.join(kotlinDirectory, name)).readAsBytes();
      expect(installed, template, reason: '$name must be copied byte-for-byte');
    }

    final manifest = await File(
      p.join(
        temporaryRoot.path,
        'android',
        'app',
        'src',
        'main',
        'AndroidManifest.xml',
      ),
    ).readAsString();
    for (final forbidden in <String>[
      'ACCESS_FINE_LOCATION',
      'ACCESS_COARSE_LOCATION',
      'QUERY_ALL_PACKAGES',
      'READ_CONTACTS',
      'RECORD_AUDIO',
      'CAMERA',
      'Shizuku',
    ]) {
      expect(manifest, isNot(contains(forbidden)));
    }
  });
}

Future<void> _copyFile(String source, String destination) async {
  final target = File(destination);
  await target.parent.create(recursive: true);
  await File(source).copy(target.path);
}

const String _fakeFlutter = r'''#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "create" ]]; then
  target="${@: -1}"
  mkdir -p "$target/android/app/src/main/kotlin/com/qujindai/pocketgallery_phone_pilot"
  cat > "$target/android/app/build.gradle.kts" <<'GRADLE'
android {
    defaultConfig {
        applicationId = "com.qujindai.pocketgallery_phone_pilot"
        minSdk = flutter.minSdkVersion
    }
    buildTypes {
        getByName("release") {}
    }
}
GRADLE
  cat > "$target/android/app/src/main/AndroidManifest.xml" <<'MANIFEST'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:label="pocketgallery_phone_pilot">
    </application>
</manifest>
MANIFEST
  cat > "$target/android/app/src/main/kotlin/com/qujindai/pocketgallery_phone_pilot/MainActivity.kt" <<'KOTLIN'
package com.qujindai.pocketgallery_phone_pilot
class MainActivity
KOTLIN
  touch "$target/.metadata"
  exit 0
fi
if [[ "${1:-}" == "pub" && "${2:-}" == "get" ]]; then
  exit 0
fi
exit 64
''';
