#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKTREE="${1:?usage: apply.sh UPSTREAM_WORKTREE [OVERLAY_DIR] [PATCH_DIR]}"
OVERLAY_DIR="${2:-$ROOT/overlay/Android}"
PATCH_DIR="${3:-$ROOT/patches/upstream}"

if [[ ! -d "$WORKTREE/.git" && ! -d "$WORKTREE/Android" ]]; then
  echo "invalid upstream worktree: $WORKTREE" >&2
  exit 2
fi

if [[ "${POCKETGALLERY_SKIP_UPSTREAM_PATCHES:-0}" != "1" && -d "$PATCH_DIR" ]]; then
  if ! git -C "$WORKTREE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "upstream patches require a git worktree: $WORKTREE" >&2
    exit 2
  fi

  shopt -s nullglob
  patches=("$PATCH_DIR"/*.patch)
  shopt -u nullglob
  for patch in "${patches[@]}"; do
    git -C "$WORKTREE" apply --check "$patch"
    git -C "$WORKTREE" apply "$patch"
  done
fi

test -d "$OVERLAY_DIR"
mkdir -p "$WORKTREE/Android"
cp -a "$OVERLAY_DIR"/. "$WORKTREE/Android/"
