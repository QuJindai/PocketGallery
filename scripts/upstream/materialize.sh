#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/.upstream-version"

DEST="${1:?usage: materialize.sh DEST [REPO] [COMMIT]}"
REPO="${2:-$UPSTREAM_REPO}"
COMMIT="${3:-$UPSTREAM_COMMIT}"

if [[ -e "$DEST" ]]; then
  if [[ ! -d "$DEST/.git" ]]; then
    echo "destination exists and is not a git checkout: $DEST" >&2
    exit 2
  fi
  if [[ -n "$(git -C "$DEST" status --porcelain)" ]]; then
    echo "destination is dirty: $DEST" >&2
    exit 3
  fi
else
  git clone --filter=blob:none --no-checkout "$REPO" "$DEST"
fi

git -C "$DEST" fetch --force origin "$COMMIT"
git -C "$DEST" checkout --detach --force "$COMMIT"
git -C "$DEST" clean -ffdqx

ACTUAL="$(git -C "$DEST" rev-parse HEAD)"
if [[ "$ACTUAL" != "$COMMIT" ]]; then
  echo "upstream verification failed: expected $COMMIT got $ACTUAL" >&2
  exit 4
fi
