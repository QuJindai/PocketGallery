#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/.upstream-version"

WORKTREE="${POCKETGALLERY_WORKTREE:-$ROOT/.work/gallery-db-smoke}"
AVD_NAME="${POCKETGALLERY_AVD_NAME:-pocketgallery_p0b_api35}"
AVD_HOME="${POCKETGALLERY_AVD_HOME:-$ROOT/.work/avd}"
SYSTEM_IMAGE="${POCKETGALLERY_SYSTEM_IMAGE:-system-images;android-35;default;x86_64}"
TEST_CLASS="com.google.ai.edge.gallery.pocketgallery.knowledge.db.KnowledgeDatabaseInstrumentedTest"
LOG_DIR="$ROOT/.work/emulator"
EMULATOR_LOG="$LOG_DIR/p0b-api35.log"
mkdir -p "$LOG_DIR"

if [[ "${POCKETGALLERY_SKIP_MATERIALIZE:-0}" != "1" ]]; then
  mkdir -p "$(dirname "$WORKTREE")"
  bash "$ROOT/scripts/upstream/materialize.sh" "$WORKTREE"
fi
bash "$ROOT/scripts/overlay/apply.sh" "$WORKTREE"

ADB="$(command -v adb)"
AVDMANAGER="$(command -v avdmanager)"
EMULATOR="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}/emulator/emulator"
if [[ ! -x "$EMULATOR" ]]; then
  EMULATOR="$(command -v emulator)"
fi

# Keep avdmanager and emulator on the exact same explicit AVD directory. The
# GitHub runner can otherwise expose different legacy/default Android homes.
rm -rf "$AVD_HOME"
mkdir -p "$AVD_HOME"
export ANDROID_AVD_HOME="$AVD_HOME"

echo no | "$AVDMANAGER" create avd \
  --force \
  --name "$AVD_NAME" \
  --package "$SYSTEM_IMAGE" \
  >/dev/null

if ! "$EMULATOR" -list-avds | grep -Fxq "$AVD_NAME"; then
  echo "created AVD is not visible to emulator: $AVD_NAME" >&2
  echo "ANDROID_AVD_HOME=$ANDROID_AVD_HOME" >&2
  "$AVDMANAGER" list avd >&2 || true
  "$EMULATOR" -list-avds >&2 || true
  find "$ANDROID_AVD_HOME" -maxdepth 2 -type f -print >&2 || true
  exit 1
fi

"$ADB" kill-server >/dev/null 2>&1 || true
"$EMULATOR" \
  -avd "$AVD_NAME" \
  -no-window \
  -no-audio \
  -no-boot-anim \
  -no-snapshot \
  -gpu swiftshader_indirect \
  >"$EMULATOR_LOG" 2>&1 &
EMULATOR_PID=$!

cleanup() {
  "$ADB" emu kill >/dev/null 2>&1 || true
  kill "$EMULATOR_PID" >/dev/null 2>&1 || true
  wait "$EMULATOR_PID" >/dev/null 2>&1 || true
  rm -rf "$AVD_HOME"
}
trap cleanup EXIT

if ! timeout 180 "$ADB" wait-for-device; then
  echo "emulator did not appear in adb within 180 seconds" >&2
  tail -n 200 "$EMULATOR_LOG" >&2 || true
  exit 1
fi

booted=0
for _ in $(seq 1 180); do
  if ! kill -0 "$EMULATOR_PID" >/dev/null 2>&1; then
    echo "emulator exited before boot completed" >&2
    tail -n 200 "$EMULATOR_LOG" >&2 || true
    exit 1
  fi
  if [[ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; then
    booted=1
    break
  fi
  sleep 2
done

if [[ "$booted" != "1" ]]; then
  echo "emulator did not boot within the allowed window" >&2
  tail -n 200 "$EMULATOR_LOG" >&2 || true
  exit 1
fi

"$ADB" shell settings put global window_animation_scale 0 >/dev/null
"$ADB" shell settings put global transition_animation_scale 0 >/dev/null
"$ADB" shell settings put global animator_duration_scale 0 >/dev/null

PROJECT="$WORKTREE/$UPSTREAM_ANDROID_ROOT"
cd "$PROJECT"
./gradlew --no-daemon connectedDebugAndroidTest \
  "-Pandroid.testInstrumentationRunnerArguments.class=$TEST_CLASS"
