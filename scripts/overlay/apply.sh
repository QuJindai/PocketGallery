#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKTREE="${1:?usage: apply.sh UPSTREAM_WORKTREE [OVERLAY_DIR]}"
OVERLAY_DIR="${2:-$ROOT/overlay/Android}"

if [[ ! -d "$WORKTREE/.git" && ! -d "$WORKTREE/Android" ]]; then
  echo "invalid upstream worktree: $WORKTREE" >&2
  exit 2
fi

test -d "$OVERLAY_DIR"
mkdir -p "$WORKTREE/Android"
cp -a "$OVERLAY_DIR"/. "$WORKTREE/Android/"
