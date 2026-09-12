#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
candidate_app="${1:-$HOME/Applications/roma just talk.app}"

if [[ "${GITHUB_ACTIONS:-}" != true || "$(uname -s)" != Darwin ]]; then
  echo "Run the updater E2E only on a disposable macOS Actions runner." >&2
  exit 2
fi
if [[ "$(id -u)" == 0 || "$(stat -f %u /dev/console)" != "$(id -u)" ]]; then
  echo "The updater E2E runner must own the logged-in desktop session." >&2
  exit 2
fi
if [[ ! -d "$candidate_app" ]]; then
  echo "Candidate app not found: $candidate_app" >&2
  exit 2
fi

derived_data="$repo_root/.local-build"
sign_update="$derived_data/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
if [[ ! -x "$sign_update" ]]; then
  echo "Pinned Sparkle sign_update tool not found after the candidate build." >&2
  exit 2
fi

work_dir="$(mktemp -d "$derived_data/updater-e2e.XXXXXX")"
test_derived_data="$(mktemp -d "${RUNNER_TEMP:-/tmp}/roma-updater-e2e-derived.XXXXXX")"
secret_dir="$(mktemp -d "${RUNNER_TEMP:-/tmp}/roma-updater-e2e-key.XXXXXX")"
serve_dir="$work_dir/serve"
server_log="$work_dir/server.log"
build_log="$work_dir/build-for-testing.log"
test_log="$work_dir/test.log"
result_bundle="$work_dir/UpdaterE2E.xcresult"
private_key_file="$secret_dir/private-key"
mkdir -p "$serve_dir"

server_pid=""
cleanup() {
  pkill -TERM -x "roma just talk" 2>/dev/null || true
  defaults delete com.negentropi.RomaJustTalk 2>/dev/null || true
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$test_derived_data"
  rm -f "$private_key_file" "$secret_dir/keys"
  rmdir "$secret_dir" 2>/dev/null || true
}
trap cleanup EXIT

candidate_build="$(plutil -extract CFBundleVersion raw -o - "$candidate_app/Contents/Info.plist")"
candidate_version="$(plutil -extract CFBundleShortVersionString raw -o - "$candidate_app/Contents/Info.plist")"
if [[ ! "$candidate_build" =~ ^[0-9]+([.][0-9]+)*$ ]]; then
  echo "Candidate build is not Sparkle-numeric: $candidate_build" >&2
  exit 2
fi
if [[ ! "$candidate_version" =~ ^[0-9A-Za-z._+-]+$ ]]; then
  echo "Candidate display version is unsafe for the local appcast: $candidate_version" >&2
  exit 2
fi
node -e '
  const { compareBuilds } = require(process.argv[1]);
  if (compareBuilds(process.argv[2], "1") <= 0) process.exit(1);
' "$repo_root/scripts/assert-newer-sparkle-build.js" "$candidate_build"

node - <<'NODE' > "$secret_dir/keys"
const { generateKeyPairSync } = require("node:crypto");
const { privateKey } = generateKeyPairSync("ed25519");
const jwk = privateKey.export({ format: "jwk" });
console.log(Buffer.from(jwk.d, "base64url").toString("base64"));
console.log(Buffer.from(jwk.x, "base64url").toString("base64"));
NODE
sed -n '1p' "$secret_dir/keys" > "$private_key_file"
public_key="$(sed -n '2p' "$secret_dir/keys")"
chmod 600 "$private_key_file"
test "$(wc -c < "$private_key_file" | tr -d ' ')" -eq 45
test "$(printf '%s' "$public_key" | wc -c | tr -d ' ')" -eq 44

archive="$serve_dir/roma.just.talk.app.zip"
ditto -c -k --keepParent "$candidate_app" "$archive"
archive_size="$(stat -f %z "$archive")"
signature_output="$("$sign_update" --ed-key-file "$private_key_file" "$archive")"
archive_signature="$(printf '%s\n' "$signature_output" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
test -n "$archive_signature"

node "$repo_root/scripts/updater-e2e-server.js" "$serve_dir" 0 > "$server_log" 2>&1 &
server_pid="$!"
for _ in {1..100}; do
  grep -Eq '^READY [0-9]+$' "$server_log" && break
  kill -0 "$server_pid" 2>/dev/null || {
    cat "$server_log" >&2
    exit 1
  }
  sleep 0.1
done
port="$(sed -n 's/^READY \([0-9][0-9]*\)$/\1/p' "$server_log" | tail -1)"
test -n "$port"
feed_url="http://127.0.0.1:$port/appcast.xml"
archive_url="http://127.0.0.1:$port/roma.just.talk.app.zip"

cat > "$serve_dir/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>roma just talk updater E2E</title>
    <link>http://127.0.0.1:$port/</link>
    <description>Ephemeral Namespace updater verification.</description>
    <item>
      <title>roma just talk $candidate_version</title>
      <pubDate>Fri, 12 Sep 2026 00:00:00 +0000</pubDate>
      <sparkle:version>$candidate_build</sparkle:version>
      <sparkle:shortVersionString>$candidate_version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.4</sparkle:minimumSystemVersion>
      <enclosure url="$archive_url" length="$archive_size" type="application/octet-stream" sparkle:edSignature="$archive_signature" />
    </item>
  </channel>
</rss>
EOF
"$sign_update" --ed-key-file "$private_key_file" "$serve_dir/appcast.xml" --disable-signing-warning
"$sign_update" --verify --ed-key-file "$private_key_file" "$serve_dir/appcast.xml"

cd "$repo_root"
test_selector='VoiceInkUITests/UpdaterE2ETests/testSeamlessBackgroundUpdateInstallsAndRelaunches'
build_arguments=(
  -project VoiceInk.xcodeproj -scheme VoiceInkUpdaterE2E -configuration Release
  -destination 'platform=macOS' -parallel-testing-enabled NO
  -derivedDataPath "$test_derived_data" -xcconfig LocalBuild.xcconfig
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES
  DEVELOPMENT_TEAM= CODE_SIGN_ENTITLEMENTS="$repo_root/VoiceInk/VoiceInk.local.entitlements"
  CURRENT_PROJECT_VERSION=1 MARKETING_VERSION=0.0.0
  INFOPLIST_KEY_SUPublicEDKey="$public_key"
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) LOCAL_BUILD UPDATE_E2E'
  -only-testing:"$test_selector"
)
xcodebuild build-for-testing -quiet "${build_arguments[@]}" | tee "$build_log"

installed_app="$test_derived_data/Build/Products/Release/roma just talk.app"
test "$(plutil -extract CFBundleVersion raw -o - "$installed_app/Contents/Info.plist")" = 1
test "$(plutil -extract SUPublicEDKey raw -o - "$installed_app/Contents/Info.plist")" = "$public_key"
codesign --verify --deep --strict "$installed_app"

defaults delete com.negentropi.RomaJustTalk 2>/dev/null || true
defaults write com.negentropi.RomaJustTalk hasCompletedOnboarding -bool true
defaults write com.negentropi.RomaJustTalk CurrentTranscriptionModel -string roma-updater-e2e-no-model
defaults write com.negentropi.RomaJustTalk automaticUpdatesEnabled -bool true

export ROMA_UPDATE_FEED_URL="$feed_url"
export ROMA_UPDATE_EXPECTED_BUILD="$candidate_build"
export ROMA_UPDATE_EXPECTED_VERSION="$candidate_version"
export ROMA_UPDATE_INSTALL_APP_PATH="$installed_app"
test_exit=0
xcodebuild test-without-building "${build_arguments[@]}" \
  -resultBundlePath "$result_bundle" | tee "$test_log" || test_exit=$?

grep -Fq 'GET /appcast.xml' "$server_log"
grep -Fq 'GET /roma.just.talk.app.zip' "$server_log"
test "$(plutil -extract CFBundleVersion raw -o - "$installed_app/Contents/Info.plist")" = "$candidate_build"

{
  printf 'candidate_build=%s\n' "$candidate_build"
  printf 'candidate_version=%s\n' "$candidate_version"
  printf 'installed_build=%s\n' "$(plutil -extract CFBundleVersion raw -o - "$installed_app/Contents/Info.plist")"
  printf 'feed_url=%s\n' "$feed_url"
  printf 'archive_requested=true\n'
  printf 'test_exit=%s\n' "$test_exit"
} > "$work_dir/result.txt"

exit "$test_exit"
