#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERIFIER="$ROOT/scripts/macos-apfs-volume-owner.sh"
FIXTURES="$ROOT/scripts/tests/fixtures/macos-apfs-volume-owner"
TARGET_UUID="A1B245F6-017B-4D48-86BB-B65281471D51"

expect_rejected() {
  local fixture="$1"
  if "$VERIFIER" "$TARGET_UUID" "$fixture"; then
    echo "expected APFS owner fixture to be rejected: $fixture" >&2
    exit 1
  fi
}

test -x "$VERIFIER"
"$VERIFIER" "$TARGET_UUID" "$FIXTURES/target-owner.txt"
"$VERIFIER" "$TARGET_UUID" "$FIXTURES/target-owner-piped.txt"
"$VERIFIER" "$(printf '%s' "$TARGET_UUID" | tr '[:upper:]' '[:lower:]')" \
  "$FIXTURES/target-owner.txt"
expect_rejected "$FIXTURES/next-record-owner.txt"
expect_rejected "$FIXTURES/target-missing.txt"

if "$VERIFIER" not-a-uuid "$FIXTURES/target-owner.txt" >/dev/null 2>&1; then
  echo "expected malformed generated UID to be rejected" >&2
  exit 1
fi

echo "macOS APFS volume-owner parser tests passed"
