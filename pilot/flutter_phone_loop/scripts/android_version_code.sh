#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_LINE="$(sed -n 's/^version:[[:space:]]*//p' "$ROOT/pubspec.yaml" | head -1)"

if [[ ! "$VERSION_LINE" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+([0-9]+)$ ]]; then
  echo "invalid pubspec version: ${VERSION_LINE:-missing}" >&2
  exit 2
fi

BUILD_NUMBER="${BASH_REMATCH[1]}"
printf '%d\n' "$((2000 + 10#$BUILD_NUMBER))"
