#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAKE="$TMP/fake-upstream"
DEST="$TMP/materialized"
mkdir -p "$FAKE"
git -C "$FAKE" init -q
git -C "$FAKE" config user.email test@example.invalid
git -C "$FAKE" config user.name PocketGallery-Test
printf 'one\n' > "$FAKE/value.txt"
git -C "$FAKE" add value.txt
git -C "$FAKE" commit -qm one
PIN="$(git -C "$FAKE" rev-parse HEAD)"
printf 'two\n' > "$FAKE/value.txt"
git -C "$FAKE" commit -qam two

bash "$ROOT/scripts/upstream/materialize.sh" "$DEST" "$FAKE" "$PIN"

test "$(git -C "$DEST" rev-parse HEAD)" = "$PIN"
test "$(cat "$DEST/value.txt")" = "one"
test -z "$(git -C "$DEST" status --porcelain)"
echo PASS
