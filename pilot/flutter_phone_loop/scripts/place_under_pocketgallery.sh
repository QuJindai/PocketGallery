#!/usr/bin/env bash
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:?usage: place_under_pocketgallery.sh /path/to/PocketGallery}"
test -f "$DEST/.upstream-version"
mkdir -p "$DEST/pilot/flutter_phone_loop"
rsync -a --delete \
  --exclude '.git' --exclude 'build' --exclude '.dart_tool' \
  "$SRC/" "$DEST/pilot/flutter_phone_loop/"
echo "PLACED: $DEST/pilot/flutter_phone_loop"
