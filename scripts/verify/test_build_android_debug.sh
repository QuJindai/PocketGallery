#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

WORK="$TMP/gallery"
mkdir -p "$WORK/Android/src"
cat > "$WORK/Android/src/gradlew" <<'GRADLE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > gradle.args
mkdir -p app/build/outputs/apk/debug
printf apk > app/build/outputs/apk/debug/app-debug.apk
GRADLE
chmod +x "$WORK/Android/src/gradlew"

POCKETGALLERY_WORKTREE="$WORK" \
POCKETGALLERY_SKIP_MATERIALIZE=1 \
POCKETGALLERY_SKIP_UPSTREAM_PATCHES=1 \
  bash "$ROOT/scripts/build/build_android_debug.sh"

test "$(cat "$WORK/Android/src/gradle.args")" = "--no-daemon testDebugUnitTest assembleDebug assembleDebugAndroidTest"
test -f "$WORK/Android/src/app/build/outputs/apk/debug/app-debug.apk"
echo PASS
