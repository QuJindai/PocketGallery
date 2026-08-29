#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 3 ]]; then
  echo 'usage: verify_canonical_signer.sh SIGN_DIR ALIAS EXPECTED_SHA256' >&2
  exit 64
fi

SIGN_DIR="$1"
ALIAS="$2"
EXPECTED_SHA256="$(tr '[:upper:]' '[:lower:]' <<<"$3" | tr -d '[:space:]:')"
KEYSTORE="$SIGN_DIR/r3.keystore"
PASSFILE="$SIGN_DIR/password"

if [[ -z "$ALIAS" || ! "$EXPECTED_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
  echo 'SIGNING_IDENTITY_INPUT_INVALID: alias or expected SHA-256 is invalid' >&2
  exit 64
fi

if [[ ! -s "$KEYSTORE" || ! -s "$PASSFILE" ]]; then
  echo 'SIGNING_IDENTITY_MISSING: canonical keystore cache is unavailable; refusing to create or rotate an identity' >&2
  exit 74
fi

PASSWORD="$(<"$PASSFILE")"
if [[ -z "$PASSWORD" ]]; then
  echo 'SIGNING_IDENTITY_MISSING: canonical keystore password is empty; refusing to create or rotate an identity' >&2
  exit 74
fi

CERT_FILE="$(mktemp)"
trap 'rm -f "$CERT_FILE"' EXIT
if ! keytool -exportcert \
  -keystore "$KEYSTORE" \
  -storepass "$PASSWORD" \
  -alias "$ALIAS" \
  -file "$CERT_FILE" \
  >/dev/null 2>&1; then
  echo 'SIGNING_IDENTITY_UNREADABLE: cached keystore could not be verified' >&2
  exit 76
fi

ACTUAL_SHA256="$(sha256sum "$CERT_FILE" | awk '{print $1}')"
if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
  echo "SIGNING_IDENTITY_MISMATCH: expected=$EXPECTED_SHA256 actual=$ACTUAL_SHA256" >&2
  exit 75
fi

echo "CANONICAL_SIGNER_VERIFIED=$ACTUAL_SHA256"
