#!/bin/bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo "Usage: $0 (after make local CONFIGURATION=Release)" >&2
  exit 2
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP_LOCK="$ROOT/VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
CHECKOUT="$ROOT/.local-build/SourcePackages/checkouts/FluidAudio"
EVIDENCE="$ROOT/.local-build/fluidaudio-test-evidence"
mkdir -p "$EVIDENCE"
RUN=$(mktemp -d "$EVIDENCE/run.XXXXXX")
exec > >(tee "$RUN/gate.log") 2>&1
trap 'RESULT=$?; printf "exit_code=%s\n" "$RESULT" > "$RUN/result.txt"' EXIT
echo "FluidAudio test evidence: $RUN"

PIN=$(python3 - "$APP_LOCK" <<'PY'
import json, re, sys
with open(sys.argv[1]) as source:
    pins = [pin for pin in json.load(source)["pins"] if pin["identity"] == "fluidaudio"]
assert len(pins) == 1, "Expected exactly one FluidAudio app pin"
pin = pins[0]
assert pin["kind"] == "remoteSourceControl", "FluidAudio must be a remote source pin"
assert set(pin["state"]) == {"revision"}, "FluidAudio must use an exact revision, not a branch or version"
assert re.fullmatch(r"[0-9a-f]{40}", pin["state"]["revision"]), "Invalid FluidAudio revision"
assert pin["location"].startswith("https://"), "Expected an HTTPS FluidAudio source"
print(pin["location"])
print(pin["state"]["revision"])
PY
)
EXPECTED_URL=$(printf '%s\n' "$PIN" | sed -n '1p')
EXPECTED_REVISION=$(printf '%s\n' "$PIN" | sed -n '2p')
{
  printf 'app_head=%s\n' "$(git -C "$ROOT" rev-parse HEAD)"
  printf 'app_lock=%s\n' "$APP_LOCK"
  shasum -a 256 "$APP_LOCK"
  printf 'expected_url=%s\nexpected_revision=%s\ncheckout=%s\n' "$EXPECTED_URL" "$EXPECTED_REVISION" "$CHECKOUT"
} > "$RUN/provenance.txt"

# xcodebuild fails with Command Line Tools alone; XCTest requires full Xcode.
xcodebuild -version | tee -a "$RUN/provenance.txt"
xcrun swift --version | tee -a "$RUN/provenance.txt"
xcode-select -p >> "$RUN/provenance.txt"

ACTUAL_REVISION=$(git -C "$CHECKOUT" rev-parse HEAD)
SOURCE_URL=$(git -C "$CHECKOUT" remote get-url origin)
# Xcode checkouts point at a local bare repository, whose origin is the public URL.
if [[ -d "$SOURCE_URL" ]]; then
  SOURCE_URL=$(git -C "$SOURCE_URL" remote get-url origin)
fi
printf 'actual_revision=%s\nactual_url=%s\n' "$ACTUAL_REVISION" "$SOURCE_URL" >> "$RUN/provenance.txt"
[[ "$ACTUAL_REVISION" == "$EXPECTED_REVISION" ]] || { echo "FluidAudio checkout revision differs from app lock"; exit 1; }
[[ "$SOURCE_URL" == "$EXPECTED_URL" ]] || { echo "FluidAudio checkout source differs from app lock"; exit 1; }
CHECKOUT_CHANGES=$(git --no-optional-locks -C "$CHECKOUT" status --porcelain --untracked-files=all)
[[ -z "$CHECKOUT_CHANGES" ]] || {
  echo "FluidAudio checkout has local changes; cannot prove the app used the pinned sources"
  exit 1
}

# Test an immutable snapshot; never build tests in or patch Xcode's dependency cache.
PACKAGE="$RUN/package"
mkdir "$PACKAGE"
git -C "$CHECKOUT" archive "$EXPECTED_REVISION" | tar -x -C "$PACKAGE"
# SwiftPM compiles the whole test target; upstream test helpers require DEBUG.
xcrun swift test --package-path "$PACKAGE" -c debug --filter RomaArrayResetTests 2>&1 | tee "$RUN/swift-test.log"

# SwiftPM can exit successfully when a filter selects zero tests.
python3 - "$RUN/swift-test.log" <<'PY'
import re, sys
from pathlib import Path
log = Path(sys.argv[1]).read_text()
assert not re.search(r"no matching test|executed 0 tests", log, re.IGNORECASE), "No XCTest cases selected"
summary = r"Test Suite 'RomaArrayResetTests' passed at [^\n]+\n\s*Executed 5 tests, with 0 failures \(0 unexpected\) in "
assert re.search(summary, log), "Missing successful five-test RomaArrayResetTests summary"
passed = re.findall(r"Test Case '-\[FluidAudioTests\.RomaArrayResetTests ([^\]]+)\]' passed", log)
assert len(passed) == len(set(passed)) == 5, "Expected five distinct passing RomaArrayResetTests cases"
print("PASS: five FluidAudio array reset XCTest cases at the app's exact revision")
PY
