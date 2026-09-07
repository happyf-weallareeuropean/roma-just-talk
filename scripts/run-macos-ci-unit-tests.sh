#!/usr/bin/env bash
set -euo pipefail

# This provisions only the disposable CI test host, never an installed release app.
if [[ "${GITHUB_ACTIONS:-}" != true || "$(uname -s)" != Darwin ]]; then
  echo "Run this test provisioning script only on a disposable macOS Actions runner." >&2
  exit 2
fi
if [[ "$(id -u)" == 0 || "$(stat -f %u /dev/console)" != "$(id -u)" ]]; then
  echo "The test runner must own the logged-in desktop session." >&2
  exit 2
fi

cd "$(dirname "$0")/.."
evidence="$PWD/.local-build/onboarding-test-evidence"
probe=/tmp/roma-onboarding-diagnostic/ExternalAXProbe
app="$PWD/.local-build/Build/Products/Debug/roma just talk.app"
mkdir -p "$evidence" "$(dirname "$probe")"
xcrun swiftc Tools/OnboardingAccessibilityProbe.swift -o "$probe"

build_arguments=(
  -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug
  -destination 'platform=macOS' -parallel-testing-enabled NO
  -derivedDataPath "$PWD/.local-build" -xcconfig LocalBuild.xcconfig
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES
  DEVELOPMENT_TEAM= CODE_SIGN_ENTITLEMENTS="$PWD/VoiceInk/VoiceInk.local.entitlements"
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) LOCAL_BUILD'
  -only-testing:VoiceInkTests
)
xcodebuild build-for-testing "${build_arguments[@]}"

test "$(plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist")" = com.negentropi.RomaJustTalk
codesign --verify --deep --strict "$app"
identity() {
  codesign -dr - "$app" 2>&1 | sed -n \
    -e 's/^# designated => //p' -e 's/^designated => //p'
}
fingerprint() {
  shasum -a 256 "$app/Contents/MacOS/roma just talk" "$probe"
  identity
}
identity > "$evidence/host-requirement.txt"
test -s "$evidence/host-requirement.txt"
csreq -r "$evidence/host-requirement.txt" -b "$evidence/host.csreq"
fingerprint > "$evidence/identity-before.txt"
requirement_hex="$(xxd -p "$evidence/host.csreq" | tr -d '\n')"
test -n "$requirement_hex"

# Embedding the XCTest bundle changes the host requirement. Grant after the last
# build, then test without rebuilding; the child AX probe is attributed to its host.
grant_sql() {
  printf '%s\n' "INSERT OR REPLACE INTO access(
service,client,client_type,auth_value,auth_reason,auth_version,csreq,
indirect_object_identifier_type,indirect_object_identifier,flags
) VALUES('$1','com.negentropi.RomaJustTalk',0,2,4,1,X'$requirement_hex',0,'UNUSED',0);"
}
grant_sql kTCCServiceAccessibility | sudo sqlite3 '/Library/Application Support/com.apple.TCC/TCC.db'
grant_sql kTCCServiceMicrophone | sqlite3 "$HOME/Library/Application Support/com.apple.TCC/TCC.db"
killall tccd 2>/dev/null || true
sudo killall tccd 2>/dev/null || true
sleep 2

test_exit=0
xcodebuild test-without-building "${build_arguments[@]}" \
  -resultBundlePath "$evidence/Debug.xcresult" || test_exit=$?
fingerprint > "$evidence/identity-after.txt"
cmp "$evidence/identity-before.txt" "$evidence/identity-after.txt"
codesign --verify --deep --strict "$app"
exit "$test_exit"
