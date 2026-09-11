#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <macos-app-bundle>" >&2
  exit 2
fi

app="$1"
name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")"
executable="$app/Contents/MacOS/$name"
test -x "$executable"
load_commands="$(otool -l "$executable")"

# Inspect Mach-O sections: stripping symbol names must not hide profiling work.
if ! awk '$1 == "cmd" && $2 == "LC_SEGMENT_64" { found = 1 } END { exit !found }' <<< "$load_commands"; then
  echo "Release app has no inspectable 64-bit Mach-O segments: $executable" >&2
  exit 1
fi
if awk '$1 == "sectname" && $2 ~ /^__llvm_(prf|cov)/ { found = 1 } END { exit !found }' <<< "$load_commands"; then
  echo "Release app contains LLVM test-coverage instrumentation: $executable" >&2
  exit 1
fi
echo "Verified release app contains no LLVM test-coverage instrumentation"
