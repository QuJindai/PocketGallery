#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
bash scripts/verify.sh
flutter build apk --debug --target-platform android-arm64
APK="build/app/outputs/flutter-apk/app-debug.apk"
test -f "$APK"
sha256sum "$APK" > "$APK.sha256"
echo "$APK"
