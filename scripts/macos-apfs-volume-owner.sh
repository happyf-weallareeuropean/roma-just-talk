#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <generated-uid> <diskutil-apfs-list-users-output>" >&2
  exit 2
fi

generated_uid="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
users_file="$2"

if ! [[ "$generated_uid" =~ ^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$ ]]; then
  echo "generated UID must be a UUID" >&2
  exit 2
fi
test -s "$users_file"

awk -v expected="$generated_uid" '
  function finish_target() {
    decided = 1
    result = owner ? 0 : 1
    exit result
  }

  /^[[:space:]]*\+--[[:space:]]+[0-9A-Fa-f-]+[[:space:]]*$/ {
    if (in_target) finish_target()
    record_uuid = $0
    sub(/^[[:space:]]*\+--[[:space:]]+/, "", record_uuid)
    sub(/[[:space:]]*$/, "", record_uuid)
    in_target = toupper(record_uuid) == expected
    owner = 0
    next
  }

  in_target && /^[[:space:]|]*Volume Owner:[[:space:]]*Yes[[:space:]]*$/ {
    owner = 1
  }

  END {
    if (decided) exit result
    exit (in_target && owner) ? 0 : 1
  }
' "$users_file"
