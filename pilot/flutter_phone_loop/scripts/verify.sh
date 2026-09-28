#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
bash scripts/bootstrap_android.sh
flutter analyze
flutter test
echo "VERIFY_PASS"
