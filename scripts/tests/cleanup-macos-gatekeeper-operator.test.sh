#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLEANER="$ROOT/scripts/cleanup-macos-gatekeeper-operator.sh"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/roma-gatekeeper-cleanup.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT
LOCAL_USER="$(/usr/bin/id -un)"
LOCAL_UID="$(/usr/bin/dscl . -read "/Users/$LOCAL_USER" GeneratedUID | awk '{print $2}')"

prepare_case() {
  local case_name="$1" setup_content="$2" ownership="$3"
  CASE_ROOT="$TEMP_ROOT/$case_name"
  SETUP_FACTS="$CASE_ROOT/setup-facts.txt"
  PASSWORD_FILE="$CASE_ROOT/voiceink-remote-e2e-stage/operator-password"
  CREDENTIAL_FILE="$CASE_ROOT/Roma Distribution E2E Operator Credentials.txt"
  CLEANUP_FACTS="$CASE_ROOT/evidence/distribution-operator-cleanup.txt"
  OWNERSHIP_MARKER="$CASE_ROOT/voiceink-remote-e2e-stage/operator-credential-owned"
  mkdir -p "$(dirname "$PASSWORD_FILE")"
  printf 'temporary-secret' > "$PASSWORD_FILE"
  printf 'temporary-credential' > "$CREDENTIAL_FILE"
  if [ "$setup_content" != missing ]; then
    printf '%b' "$setup_content" > "$SETUP_FACTS"
    mkdir -p "$(dirname "$SETUP_FACTS")"
    {
      printf 'Cryptographic user for disk5s1s1 (1 found)\n|\n'
      printf '+-- %s\n' "$LOCAL_UID"
      printf '    Type: Local Open Directory User\n'
      printf '    Volume Owner: Yes\n'
    } > "$(dirname "$SETUP_FACTS")/distribution-operator-volume-owners.txt"
  fi
  if [ "$ownership" = owned ]; then
    {
      printf 'password_file_identity=%s\n' "$(stat -f '%d:%i' "$PASSWORD_FILE")"
      printf 'credential_file_identity=%s\n' "$(stat -f '%d:%i' "$CREDENTIAL_FILE")"
    } > "$OWNERSHIP_MARKER"
  elif [ "$ownership" = mismatched ]; then
    {
      printf 'password_file_identity=1:1\n'
      printf 'credential_file_identity=1:1\n'
    } > "$OWNERSHIP_MARKER"
  fi
}

assert_targets_removed() {
  test ! -e "$PASSWORD_FILE"
  test ! -e "$CREDENTIAL_FILE"
  grep -Fxq 'credential_file_removed=true' "$CLEANUP_FACTS"
  grep -Fxq 'temporary_password_file_removed=true' "$CLEANUP_FACTS"
}

prepare_case unowned missing unowned
if "$CLEANER" "$SETUP_FACTS" "$PASSWORD_FILE" "$CREDENTIAL_FILE" \
  "$CLEANUP_FACTS" "$LOCAL_USER" "$OWNERSHIP_MARKER" test-unprivileged; then
  echo "expected unowned credential targets to be preserved with failed cleanup" >&2
  exit 1
fi
test -e "$PASSWORD_FILE"
test -e "$CREDENTIAL_FILE"
grep -Fxq 'credential_targets_owned=unverified' "$CLEANUP_FACTS"
grep -Fxq 'operator_verification=not-completed' "$CLEANUP_FACTS"
grep -Fxq 'cleanup=failed' "$CLEANUP_FACTS"

prepare_case missing missing owned
"$CLEANER" "$SETUP_FACTS" "$PASSWORD_FILE" "$CREDENTIAL_FILE" \
  "$CLEANUP_FACTS" "$LOCAL_USER" "$OWNERSHIP_MARKER" test-unprivileged
assert_targets_removed
grep -Fxq 'operator_verification=not-completed' "$CLEANUP_FACTS"

prepare_case valid "account_short_name=$LOCAL_USER\naccount_generated_uid=$LOCAL_UID\n" owned
"$CLEANER" "$SETUP_FACTS" "$PASSWORD_FILE" "$CREDENTIAL_FILE" \
  "$CLEANUP_FACTS" "$LOCAL_USER" "$OWNERSHIP_MARKER" test-unprivileged
assert_targets_removed
grep -Fxq "account_short_name=$LOCAL_USER" "$CLEANUP_FACTS"
grep -Fxq "account_generated_uid=$LOCAL_UID" "$CLEANUP_FACTS"
grep -Fxq 'operator_verification=completed' "$CLEANUP_FACTS"
test -s "$(dirname "$SETUP_FACTS")/distribution-operator-volume-owners-after.txt"
grep -Fxq 'cleanup=passed' "$CLEANUP_FACTS"

prepare_case malformed "account_short_name=unexpected-user\naccount_generated_uid=$LOCAL_UID\n" owned
if "$CLEANER" "$SETUP_FACTS" "$PASSWORD_FILE" "$CREDENTIAL_FILE" \
  "$CLEANUP_FACTS" "$LOCAL_USER" "$OWNERSHIP_MARKER" test-unprivileged; then
  echo "expected malformed operator facts to be rejected" >&2
  exit 1
fi
assert_targets_removed

prepare_case duplicate "account_short_name=$LOCAL_USER\naccount_short_name=$LOCAL_USER\naccount_generated_uid=$LOCAL_UID\n" owned
if "$CLEANER" "$SETUP_FACTS" "$PASSWORD_FILE" "$CREDENTIAL_FILE" \
  "$CLEANUP_FACTS" "$LOCAL_USER" "$OWNERSHIP_MARKER" test-unprivileged; then
  echo "expected duplicate operator facts to be rejected" >&2
  exit 1
fi
assert_targets_removed

prepare_case mismatched missing mismatched
if "$CLEANER" "$SETUP_FACTS" "$PASSWORD_FILE" "$CREDENTIAL_FILE" \
  "$CLEANUP_FACTS" "$LOCAL_USER" "$OWNERSHIP_MARKER" test-unprivileged; then
  echo "expected mismatched ownership marker to be rejected" >&2
  exit 1
fi
mismatched_passwords=("$(dirname "$PASSWORD_FILE")"/.roma-credential-cleanup.*/operator-password)
mismatched_credentials=("$(dirname "$CREDENTIAL_FILE")"/.roma-credential-cleanup.*/operator-credential)
test "${#mismatched_passwords[@]}" -eq 1
test "${#mismatched_credentials[@]}" -eq 1
grep -Fxq 'temporary-secret' "${mismatched_passwords[0]}"
grep -Fxq 'temporary-credential' "${mismatched_credentials[0]}"
test ! -e "$PASSWORD_FILE"
test ! -e "$CREDENTIAL_FILE"
grep -Fxq 'credential_file_removed=false' "$CLEANUP_FACTS"
grep -Fxq 'temporary_password_file_removed=false' "$CLEANUP_FACTS"
grep -Fxq 'cleanup=failed' "$CLEANUP_FACTS"

prepare_case replacement missing owned
/bin/rm -f "$PASSWORD_FILE"
printf 'replacement-secret' > "$PASSWORD_FILE"
if "$CLEANER" "$SETUP_FACTS" "$PASSWORD_FILE" "$CREDENTIAL_FILE" \
  "$CLEANUP_FACTS" "$LOCAL_USER" "$OWNERSHIP_MARKER" test-unprivileged; then
  echo "expected replaced credential target to be rejected" >&2
  exit 1
fi
replacement_files=("$(dirname "$PASSWORD_FILE")"/.roma-credential-cleanup.*/operator-password)
test "${#replacement_files[@]}" -eq 1
grep -Fxq 'replacement-secret' "${replacement_files[0]}"
test ! -e "$PASSWORD_FILE"
test ! -e "$CREDENTIAL_FILE"
grep -Fxq 'credential_file_removed=true' "$CLEANUP_FACTS"
grep -Fxq 'temporary_password_file_removed=false' "$CLEANUP_FACTS"
grep -Fxq 'cleanup=failed' "$CLEANUP_FACTS"

prepare_case replacement-symlink missing owned
symlink_target="$CASE_ROOT/replacement-target.txt"
printf 'do-not-delete' > "$symlink_target"
rm "$PASSWORD_FILE"
ln -s "$symlink_target" "$PASSWORD_FILE"
if "$CLEANER" "$SETUP_FACTS" "$PASSWORD_FILE" "$CREDENTIAL_FILE" \
  "$CLEANUP_FACTS" "$LOCAL_USER" "$OWNERSHIP_MARKER" test-unprivileged; then
  echo "expected replaced symlink target to be rejected" >&2
  exit 1
fi
replacement_symlinks=("$(dirname "$PASSWORD_FILE")"/.roma-credential-cleanup.*/operator-password)
test "${#replacement_symlinks[@]}" -eq 1
test -L "${replacement_symlinks[0]}"
test "$(readlink "${replacement_symlinks[0]}")" = "$symlink_target"
grep -Fxq 'do-not-delete' "$symlink_target"
test ! -e "$CREDENTIAL_FILE"
grep -Fxq 'credential_file_removed=true' "$CLEANUP_FACTS"
grep -Fxq 'temporary_password_file_removed=false' "$CLEANUP_FACTS"
grep -Fxq 'cleanup=failed' "$CLEANUP_FACTS"

prepare_case cleanup-symlink missing owned
cleanup_target="$CASE_ROOT/cleanup-target.txt"
printf 'do-not-overwrite' > "$cleanup_target"
mkdir -p "$(dirname "$CLEANUP_FACTS")"
ln -s "$cleanup_target" "$CLEANUP_FACTS"
if "$CLEANER" "$SETUP_FACTS" "$PASSWORD_FILE" "$CREDENTIAL_FILE" \
  "$CLEANUP_FACTS" "$LOCAL_USER" "$OWNERSHIP_MARKER" test-unprivileged; then
  echo "expected symlinked cleanup evidence to be rejected" >&2
  exit 1
fi
grep -Fxq 'do-not-overwrite' "$cleanup_target"
test ! -e "$PASSWORD_FILE"
test ! -e "$CREDENTIAL_FILE"

prepare_case marker-symlink missing owned
marker_target="$CASE_ROOT/marker-target.txt"
mv "$OWNERSHIP_MARKER" "$marker_target"
ln -s "$marker_target" "$OWNERSHIP_MARKER"
if "$CLEANER" "$SETUP_FACTS" "$PASSWORD_FILE" "$CREDENTIAL_FILE" \
  "$CLEANUP_FACTS" "$LOCAL_USER" "$OWNERSHIP_MARKER" test-unprivileged; then
  echo "expected symlinked ownership marker to fail cleanup" >&2
  exit 1
fi
test -e "$PASSWORD_FILE"
test -e "$CREDENTIAL_FILE"
grep -Fxq 'cleanup=failed' "$CLEANUP_FACTS"

prepare_case marker-malformed missing owned
printf 'password_file_identity=not-an-inode\n' > "$OWNERSHIP_MARKER"
if "$CLEANER" "$SETUP_FACTS" "$PASSWORD_FILE" "$CREDENTIAL_FILE" \
  "$CLEANUP_FACTS" "$LOCAL_USER" "$OWNERSHIP_MARKER" test-unprivileged; then
  echo "expected malformed ownership marker to fail cleanup" >&2
  exit 1
fi
test -e "$PASSWORD_FILE"
test -e "$CREDENTIAL_FILE"
grep -Fxq 'cleanup=failed' "$CLEANUP_FACTS"

echo "macOS Gatekeeper operator cleanup tests passed"
