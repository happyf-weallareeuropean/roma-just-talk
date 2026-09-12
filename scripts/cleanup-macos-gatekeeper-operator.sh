#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 6 ] && [ "$#" -ne 7 ]; then
  echo "usage: $0 <setup-facts> <temporary-password-file> <credential-file> <cleanup-facts> <expected-username> <ownership-marker> [test-unprivileged]" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
setup_facts="$1"
password_file="$2"
credential_file="$3"
cleanup_facts="$4"
expected_username="$5"
ownership_marker="$6"
isolation_mode="${7:-privileged}"
if [ "$isolation_mode" = test-unprivileged ]; then
  privileged() { "$@"; }
elif [ "$isolation_mode" = privileged ]; then
  privileged() { sudo -n "$@"; }
else
  echo "invalid credential isolation mode" >&2
  exit 2
fi

case "$password_file" in
  */voiceink-remote-e2e-stage/operator-password) ;;
  *) echo "refusing unexpected temporary password path" >&2; exit 2 ;;
esac
case "$ownership_marker" in
  */voiceink-remote-e2e-stage/operator-credential-owned) ;;
  *) echo "refusing unexpected credential ownership marker path" >&2; exit 2 ;;
esac
test "$(basename "$credential_file")" = "Roma Distribution E2E Operator Credentials.txt"
mkdir -p "$(dirname "$cleanup_facts")"
cleanup_evidence_failed=false
if [[ -e "$cleanup_facts" || -L "$cleanup_facts" ]]; then
  echo "refusing to overwrite cleanup evidence" >&2
  exec 3> /dev/null
  cleanup_evidence_failed=true
else
  umask 077
  set -o noclobber
  exec 3> "$cleanup_facts"
  set +o noclobber
fi

credential_cleanup_failed=false
ownership_marker_valid=false
password_identity=""
credential_identity=""
if [ -L "$ownership_marker" ]; then
  echo "refusing symlinked credential ownership marker; credential targets preserved" >&2
  credential_cleanup_failed=true
elif [ -s "$ownership_marker" ]; then
  password_identity="$(sed -n 's/^password_file_identity=//p' "$ownership_marker")"
  credential_identity="$(sed -n 's/^credential_file_identity=//p' "$ownership_marker")"
  if [ "$(grep -c '^password_file_identity=' "$ownership_marker")" -eq 1 ] \
    && [ "$(grep -c '^credential_file_identity=' "$ownership_marker")" -eq 1 ] \
    && [[ "$password_identity" =~ ^[0-9]+:[0-9]+$ ]] \
    && [[ "$credential_identity" =~ ^[0-9]+:[0-9]+$ ]]; then
    ownership_marker_valid=true
  else
    echo "malformed credential ownership marker; credential targets preserved" >&2
    credential_cleanup_failed=true
  fi
elif [ -e "$ownership_marker" ]; then
  echo "empty credential ownership marker; credential targets preserved" >&2
  credential_cleanup_failed=true
elif [[ -e "$password_file" || -L "$password_file" \
  || -e "$credential_file" || -L "$credential_file" ]]; then
  echo "credential targets exist without ownership marker; preserved" >&2
  credential_cleanup_failed=true
fi

if [ "$ownership_marker_valid" = true ]; then

  remove_owned_target() {
    local target="$1" expected_identity="$2" quarantine_name="$3"
    local target_dir quarantine_dir isolated_target
    if [[ ! -e "$target" && ! -L "$target" ]]; then
      return
    fi
    target_dir="$(dirname "$target")"
    quarantine_dir="$(privileged /usr/bin/mktemp -d "$target_dir/.roma-credential-cleanup.XXXXXX")" \
      || return 2
    privileged /bin/chmod 700 "$quarantine_dir" || return 2
    isolated_target="$quarantine_dir/$quarantine_name"
    privileged /bin/mv "$target" "$isolated_target" || return 2
    if privileged /bin/test -L "$isolated_target"; then
      echo "credential target became a symlink after ownership was recorded; preserved at $isolated_target" >&2
      return 2
    fi
    actual_identity="$(privileged /usr/bin/stat -f '%d:%i' "$isolated_target")" \
      || return 2
    if [ "$actual_identity" != "$expected_identity" ]; then
      echo "credential target changed after ownership was recorded; preserved at $isolated_target" >&2
      return 2
    fi
    privileged /bin/rm -f "$isolated_target" || return 2
    privileged /bin/rmdir "$quarantine_dir" || return 2
  }
  password_cleanup_status=0
  credential_cleanup_status=0
  remove_owned_target "$password_file" "$password_identity" operator-password \
    || password_cleanup_status=$?
  remove_owned_target "$credential_file" "$credential_identity" operator-credential \
    || credential_cleanup_status=$?
  if [ "$password_cleanup_status" -eq 0 ] \
    && [ "$credential_cleanup_status" -eq 0 ]; then
    /bin/rm -f "$ownership_marker"
    ownership_marker_removed=true
  else
    ownership_marker_removed=false
    credential_cleanup_failed=true
  fi
  {
    printf 'credential_targets_owned=true\n'
    printf 'credential_file_removed=%s\n' "$([ "$credential_cleanup_status" -eq 0 ] && echo true || echo false)"
    printf 'temporary_password_file_removed=%s\n' "$([ "$password_cleanup_status" -eq 0 ] && echo true || echo false)"
    printf 'ownership_marker_removed=%s\n' "$ownership_marker_removed"
  } >&3
else
  {
    printf 'credential_targets_owned=unverified\n'
    printf 'credential_file_preserved=%s\n' "$([[ -e "$credential_file" || -L "$credential_file" ]] && echo true || echo false)"
    printf 'temporary_password_file_preserved=%s\n' "$([[ -e "$password_file" || -L "$password_file" ]] && echo true || echo false)"
  } >&3
fi

if [ -s "$setup_facts" ]; then
  test "$(grep -c '^account_short_name=' "$setup_facts")" -eq 1
  test "$(grep -c '^account_generated_uid=' "$setup_facts")" -eq 1
  operator_username="$(sed -n 's/^account_short_name=//p' "$setup_facts")"
  persisted_uid="$(sed -n 's/^account_generated_uid=//p' "$setup_facts")"
  test "$operator_username" = "$expected_username"
  /usr/bin/id "$operator_username" >/dev/null
  actual_uid="$(/usr/bin/dscl . -read "/Users/$operator_username" GeneratedUID | awk '{print $2}')"
  test "$actual_uid" = "$persisted_uid"
  "$ROOT/macos-apfs-volume-owner.sh" \
    "$persisted_uid" "$(dirname "$setup_facts")/distribution-operator-volume-owners.txt"
  current_volume_owners="$(dirname "$setup_facts")/distribution-operator-volume-owners-after.txt"
  if [[ -e "$current_volume_owners" || -L "$current_volume_owners" ]]; then
    echo "refusing to overwrite post-scenario APFS evidence" >&2
    exit 2
  fi
  set -o noclobber
  /usr/sbin/diskutil apfs listUsers / > "$current_volume_owners"
  set +o noclobber
  "$ROOT/macos-apfs-volume-owner.sh" "$actual_uid" "$current_volume_owners"
  test -d "/Users/$operator_username"
  {
    printf 'account_short_name=%s\n' "$operator_username"
    printf 'account_generated_uid=%s\n' "$persisted_uid"
    printf 'operator_verification=completed\n'
    printf 'directory_service_record_preserved=true\n'
    printf 'apfs_volume_owner_record_preserved=true\n'
    printf 'home_directory_preserved=true\n'
  } >&3
else
  printf 'operator_verification=not-completed\n' >&3
fi
if [ "$credential_cleanup_failed" = true ] \
  || [ "$cleanup_evidence_failed" = true ]; then
  printf 'cleanup=failed\n' >&3
  exec 3>&-
  exit 2
fi
printf 'cleanup=passed\n' >&3
exec 3>&-
