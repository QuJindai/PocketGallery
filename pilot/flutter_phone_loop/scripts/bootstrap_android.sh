#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter is required (Flutter >=3.44 / Dart >=3.12)." >&2
  exit 2
fi

if [[ ! -d android ]]; then
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  flutter create \
    --platforms=android \
    --project-name=pocketgallery_phone_pilot \
    --org=com.qujindai \
    "$TMP/scaffold"
  cp -a "$TMP/scaffold/android" "$ROOT/android"
  [[ -f "$TMP/scaffold/.metadata" ]] && cp "$TMP/scaffold/.metadata" "$ROOT/.metadata"
fi

# R3 is the stable application identity. A private pilot keystore may be
# injected from outside the public repository through POCKETGALLERY_SIGNING_KEYSTORE.
# The delivered APK is signed with that stable key after CI; the private key is
# never committed to this public repository.
export PG_SIGNING_ENABLED=0
if [[ -n "${POCKETGALLERY_SIGNING_KEYSTORE:-}" && -f "${POCKETGALLERY_SIGNING_KEYSTORE}" ]]; then
  cp "${POCKETGALLERY_SIGNING_KEYSTORE}" android/app/pocketgallery-pilot.keystore
  : "${POCKETGALLERY_SIGNING_STORE_PASSWORD:?required when signing}"
  : "${POCKETGALLERY_SIGNING_KEY_PASSWORD:?required when signing}"
  : "${POCKETGALLERY_SIGNING_KEY_ALIAS:?required when signing}"
  export PG_SIGNING_ENABLED=1
fi

if [[ -f android/app/build.gradle.kts ]]; then
  python3 - <<'PY'
from pathlib import Path
import os
p=Path('android/app/build.gradle.kts')
s=p.read_text()
s=s.replace('minSdk = flutter.minSdkVersion', 'minSdk = 31')
s=s.replace(
    'applicationId = "com.qujindai.pocketgallery_phone_pilot"',
    'applicationId = "com.qujindai.pocketgallery_phone_pilot.r3"')
if os.environ.get('PG_SIGNING_ENABLED') == '1':
    store=os.environ['POCKETGALLERY_SIGNING_STORE_PASSWORD']
    key=os.environ['POCKETGALLERY_SIGNING_KEY_PASSWORD']
    alias=os.environ['POCKETGALLERY_SIGNING_KEY_ALIAS']
    signing=f'''    signingConfigs {{\n        create("pilot") {{\n            storeFile = file("pocketgallery-pilot.keystore")\n            storePassword = "{store}"\n            keyAlias = "{alias}"\n            keyPassword = "{key}"\n        }}\n    }}\n\n'''
    s=s.replace('    buildTypes {\n', signing+'    buildTypes {\n', 1)
    s=s.replace('    buildTypes {\n', '    buildTypes {\n        getByName("debug") {\n            signingConfig = signingConfigs.getByName("pilot")\n        }\n', 1)
p.write_text(s)
PY
elif [[ -f android/app/build.gradle ]]; then
  python3 - <<'PY'
from pathlib import Path
import os
p=Path('android/app/build.gradle')
s=p.read_text()
s=s.replace('minSdkVersion flutter.minSdkVersion', 'minSdkVersion 31')
s=s.replace(
    'applicationId "com.qujindai.pocketgallery_phone_pilot"',
    'applicationId "com.qujindai.pocketgallery_phone_pilot.r3"')
if os.environ.get('PG_SIGNING_ENABLED') == '1':
    store=os.environ['POCKETGALLERY_SIGNING_STORE_PASSWORD']
    key=os.environ['POCKETGALLERY_SIGNING_KEY_PASSWORD']
    alias=os.environ['POCKETGALLERY_SIGNING_KEY_ALIAS']
    signing=f'''    signingConfigs {{\n        pilot {{\n            storeFile file("pocketgallery-pilot.keystore")\n            storePassword "{store}"\n            keyAlias "{alias}"\n            keyPassword "{key}"\n        }}\n    }}\n\n'''
    s=s.replace('    buildTypes {\n', signing+'    buildTypes {\n', 1)
    s=s.replace('    buildTypes {\n', '    buildTypes {\n        debug {\n            signingConfig signingConfigs.pilot\n        }\n', 1)
p.write_text(s)
PY
fi

python3 - <<'PY'
from pathlib import Path
p=Path('android/app/src/main/AndroidManifest.xml')
s=p.read_text()
s=s.replace('android:label="pocketgallery_phone_pilot"', 'android:label="PocketGallery R3"')
if 'xmlns:tools=' not in s:
    s=s.replace(
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android"\n    xmlns:tools="http://schemas.android.com/tools">')
for perm in [
    'android.permission.INTERNET',
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.FOREGROUND_SERVICE',
    'android.permission.FOREGROUND_SERVICE_DATA_SYNC',
]:
    line=f'    <uses-permission android:name="{perm}" />'
    if line not in s:
        pos=s.find('>')+1
        s=s[:pos]+'\n'+line+s[pos:]
service='''        <service
            android:name="androidx.work.impl.foreground.SystemForegroundService"
            android:foregroundServiceType="dataSync"
            tools:node="merge" />'''
if 'androidx.work.impl.foreground.SystemForegroundService' not in s:
    s=s.replace('    </application>', service+'\n    </application>')
p.write_text(s)
PY

HOST_DIR="$ROOT/android_host"
KOTLIN_DIR="$ROOT/android/app/src/main/kotlin/com/qujindai/pocketgallery_phone_pilot"
mkdir -p "$KOTLIN_DIR"
cp "$HOST_DIR/MainActivity.kt" "$KOTLIN_DIR/MainActivity.kt"
cp "$HOST_DIR/DeviceDiagnosticsHost.kt" "$KOTLIN_DIR/DeviceDiagnosticsHost.kt"

grep -Rqs 'com.qujindai.pocketgallery_phone_pilot.r3' android/app/build.gradle* || exit 3
grep -q 'android:label="PocketGallery R3"' android/app/src/main/AndroidManifest.xml || exit 4

flutter pub get
echo "BOOTSTRAP_PASS"
