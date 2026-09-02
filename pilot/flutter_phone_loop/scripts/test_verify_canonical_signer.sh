#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFIER="$SCRIPT_DIR/verify_canonical_signer.sh"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

set +e
missing_output="$($VERIFIER "$TEST_ROOT/missing" pocketgallery-r3 "$(printf '0%.0s' {1..64})" 2>&1)"
missing_status=$?
set -e
if [[ "$missing_status" -ne 74 ]]; then
  echo "expected a missing identity to exit 74, got $missing_status"
  echo "$missing_output"
  exit 1
fi
test ! -e "$TEST_ROOT/missing/r3.keystore"
test ! -e "$TEST_ROOT/missing/password"

SIGN_DIR="$TEST_ROOT/signing"
mkdir -p "$SIGN_DIR"
TEST_PASSWORD='pocketgallery-test-password'
printf '%s' "$TEST_PASSWORD" > "$SIGN_DIR/password"
keytool -genkeypair -noprompt \
  -storetype JKS \
  -keystore "$SIGN_DIR/r3.keystore" \
  -storepass "$TEST_PASSWORD" \
  -keypass "$TEST_PASSWORD" \
  -alias pocketgallery-r3 \
  -keyalg RSA \
  -keysize 2048 \
  -validity 2 \
  -dname 'CN=PocketGallery Test, OU=CI, O=QuJindai, L=Local, ST=Local, C=CN' \
  >/dev/null 2>&1
keytool -exportcert \
  -keystore "$SIGN_DIR/r3.keystore" \
  -storepass "$TEST_PASSWORD" \
  -alias pocketgallery-r3 \
  -file "$TEST_ROOT/test-cert.der" \
  >/dev/null 2>&1
EXPECTED_SHA="$(sha256sum "$TEST_ROOT/test-cert.der" | awk '{print $1}')"
KEYSTORE_BEFORE="$(sha256sum "$SIGN_DIR/r3.keystore" | awk '{print $1}')"
PASSWORD_BEFORE="$(sha256sum "$SIGN_DIR/password" | awk '{print $1}')"

set +e
mismatch_output="$($VERIFIER "$SIGN_DIR" pocketgallery-r3 "$(printf 'f%.0s' {1..64})" 2>&1)"
mismatch_status=$?
set -e
if [[ "$mismatch_status" -ne 75 ]]; then
  echo "expected a mismatched identity to exit 75, got $mismatch_status"
  echo "$mismatch_output"
  exit 1
fi
grep -Fq 'SIGNING_IDENTITY_MISMATCH' <<<"$mismatch_output"

verified_output="$($VERIFIER "$SIGN_DIR" pocketgallery-r3 "$EXPECTED_SHA")"
grep -Fq "CANONICAL_SIGNER_VERIFIED=$EXPECTED_SHA" <<<"$verified_output"
test "$(sha256sum "$SIGN_DIR/r3.keystore" | awk '{print $1}')" = "$KEYSTORE_BEFORE"
test "$(sha256sum "$SIGN_DIR/password" | awk '{print $1}')" = "$PASSWORD_BEFORE"

echo 'PASS: canonical signer verifier is fail-closed and non-mutating'
