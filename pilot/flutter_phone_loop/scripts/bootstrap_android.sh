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

# Phone target is modern arm64. Raise minSdk only if the generated template
# exposes the standard Flutter minSdk assignment.
if [[ -f android/app/build.gradle.kts ]]; then
  python3 - <<'PY'
from pathlib import Path
p=Path("android/app/build.gradle.kts")
s=p.read_text()
s=s.replace("minSdk = flutter.minSdkVersion", "minSdk = 31")
p.write_text(s)
PY
elif [[ -f android/app/build.gradle ]]; then
  python3 - <<'PY'
from pathlib import Path
p=Path("android/app/build.gradle")
s=p.read_text()
s=s.replace("minSdkVersion flutter.minSdkVersion", "minSdkVersion 31")
p.write_text(s)
PY
fi

flutter pub get
echo "BOOTSTRAP_PASS"
