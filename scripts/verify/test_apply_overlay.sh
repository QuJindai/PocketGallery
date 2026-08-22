#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PDF_PATCH="$ROOT/patches/upstream/0002-add-androidx-pdf-dependencies.patch"
if [[ ! -f "$PDF_PATCH" ]]; then
  echo "Missing P0C AndroidX PDF dependency patch: $PDF_PATCH" >&2
  exit 1
fi
grep -Fq 'implementation("androidx.pdf:pdf-core:1.0.0-alpha19")' "$PDF_PATCH"
grep -Fq 'implementation("androidx.pdf:pdf-document-service:1.0.0-alpha19")' "$PDF_PATCH"

WORK="$TMP/work"
OVERLAY="$TMP/overlay/Android"
PATCHES="$TMP/patches"
mkdir -p "$WORK/Android/src/app" "$OVERLAY/src/app" "$PATCHES"

printf 'dependencies {}\n' > "$WORK/Android/src/app/build.gradle.kts"
printf 'upstream\n' > "$WORK/Android/src/app/keep.txt"
printf 'pocket\n' > "$OVERLAY/src/app/add.txt"

git -C "$WORK" init -q
git -C "$WORK" config user.email test@example.invalid
git -C "$WORK" config user.name PocketGalleryTest
git -C "$WORK" add .
git -C "$WORK" commit -qm base

cat > "$WORK/Android/src/app/build.gradle.kts" <<'GRADLE'
dependencies {
  implementation("example:dependency:1")
}
GRADLE
git -C "$WORK" diff -- Android/src/app/build.gradle.kts > "$PATCHES/0001-add-test-dependency.patch"
git -C "$WORK" checkout -- Android/src/app/build.gradle.kts

bash "$ROOT/scripts/overlay/apply.sh" "$WORK" "$OVERLAY" "$PATCHES"

test "$(cat "$WORK/Android/src/app/keep.txt")" = "upstream"
test "$(cat "$WORK/Android/src/app/add.txt")" = "pocket"
grep -Fq 'implementation("example:dependency:1")' "$WORK/Android/src/app/build.gradle.kts"
echo PASS
