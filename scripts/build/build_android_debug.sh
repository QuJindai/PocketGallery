#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/.upstream-version"

WORKTREE="${POCKETGALLERY_WORKTREE:-$ROOT/.work/gallery}"

if [[ "${POCKETGALLERY_SKIP_MATERIALIZE:-0}" != "1" ]]; then
  mkdir -p "$(dirname "$WORKTREE")"
  bash "$ROOT/scripts/upstream/materialize.sh" "$WORKTREE"
fi

bash "$ROOT/scripts/overlay/apply.sh" "$WORKTREE"

PROJECT="$WORKTREE/$UPSTREAM_ANDROID_ROOT"
cd "$PROJECT"
./gradlew --no-daemon testDebugUnitTest lintDebug assembleDebug
