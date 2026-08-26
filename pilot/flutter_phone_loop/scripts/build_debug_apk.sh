#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
bash scripts/verify.sh
flutter build apk --debug --target-platform android-arm64 --split-per-abi
SRC="build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk"
APK="build/app/outputs/flutter-apk/app-debug.apk"
test -f "$SRC"
cp "$SRC" "$APK"
ABIS="$(unzip -Z1 "$APK" | grep -E '^lib/[^/]+/.*\.so$' | sed -E 's#^lib/([^/]+)/.*#\1#' | sort -u | paste -sd, -)"
test "$ABIS" = "arm64-v8a"
sha256sum "$APK" > "$APK.sha256"
echo "$APK"
