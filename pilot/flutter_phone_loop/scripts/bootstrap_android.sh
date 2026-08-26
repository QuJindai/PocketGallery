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

# R1 was signed by an ephemeral GitHub debug key. Give R2 a distinct app id so
# it can be installed side-by-side without requiring an R1 uninstall.
if [[ -f android/app/build.gradle.kts ]]; then
  python3 - <<'PY'
from pathlib import Path
p=Path("android/app/build.gradle.kts")
s=p.read_text()
s=s.replace("minSdk = flutter.minSdkVersion", "minSdk = 31")
s=s.replace(
    'applicationId = "com.qujindai.pocketgallery_phone_pilot"',
    'applicationId = "com.qujindai.pocketgallery_phone_pilot.r2"')
p.write_text(s)
PY
elif [[ -f android/app/build.gradle ]]; then
  python3 - <<'PY'
from pathlib import Path
p=Path("android/app/build.gradle")
s=p.read_text()
s=s.replace("minSdkVersion flutter.minSdkVersion", "minSdkVersion 31")
s=s.replace(
    'applicationId "com.qujindai.pocketgallery_phone_pilot"',
    'applicationId "com.qujindai.pocketgallery_phone_pilot.r2"')
p.write_text(s)
PY
fi

# flutter_gemma can keep large model downloads alive with an Android foreground
# data-sync service. Inject the required declarations into the generated
# scaffold so the source tree remains small and deterministic.
python3 - <<'PY'
from pathlib import Path
p=Path('android/app/src/main/AndroidManifest.xml')
s=p.read_text()
s=s.replace(
    'android:label="pocketgallery_phone_pilot"',
    'android:label="PocketGallery R2"')
if 'xmlns:tools=' not in s:
    s=s.replace(
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android"\n    xmlns:tools="http://schemas.android.com/tools">')
permissions=[
    'android.permission.INTERNET',
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.FOREGROUND_SERVICE',
    'android.permission.FOREGROUND_SERVICE_DATA_SYNC',
]
for perm in permissions:
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

grep -Rqs 'com.qujindai.pocketgallery_phone_pilot.r2' android/app/build.gradle* || {
  echo 'R2 applicationId injection failed' >&2
  exit 3
}
grep -q 'android:label="PocketGallery R2"' android/app/src/main/AndroidManifest.xml || {
  echo 'R2 launcher label injection failed' >&2
  exit 4
}

flutter pub get
echo "BOOTSTRAP_PASS"
