#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/work/Android/src/app" "$TMP/overlay/Android/src/app"
printf 'upstream\n' > "$TMP/work/Android/src/app/keep.txt"
printf 'pocket\n' > "$TMP/overlay/Android/src/app/add.txt"

bash "$ROOT/scripts/overlay/apply.sh" "$TMP/work" "$TMP/overlay/Android"

test "$(cat "$TMP/work/Android/src/app/keep.txt")" = "upstream"
test "$(cat "$TMP/work/Android/src/app/add.txt")" = "pocket"
echo PASS
