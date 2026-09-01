#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-inner}"

source_files() {
  find . -type f \
    ! -path './MANIFEST.sha256' \
    ! -path './android/*' \
    ! -path './build/*' \
    ! -path './.dart_tool/*' \
    ! -name 'pubspec.lock' \
    ! -name '.metadata' \
    -print0 | sort -z | xargs -0 sha256sum | sed 's#  \./#  #'
}

case "$MODE" in
  inner)
    cd "$ROOT"
    sha256sum \
      ../../.github/workflows/pocketgallery-phone-pilot-apk.yml \
      ../../.github/workflows/pocketgallery-r46-tdd.yml
    source_files
    ;;
  outer)
    cd "$ROOT/../.."
    sha256sum \
      .github/workflows/pocketgallery-phone-pilot-apk.yml \
      .github/workflows/pocketgallery-r46-tdd.yml \
      PILOT_DROPIN_README.md
    find pilot/flutter_phone_loop -type f \
      ! -path 'pilot/flutter_phone_loop/android/*' \
      ! -path 'pilot/flutter_phone_loop/build/*' \
      ! -path 'pilot/flutter_phone_loop/.dart_tool/*' \
      ! -name 'pubspec.lock' \
      ! -name '.metadata' \
      -print0 | sort -z | xargs -0 sha256sum
    ;;
  *)
    echo "usage: $0 [inner|outer]" >&2
    exit 2
    ;;
esac
