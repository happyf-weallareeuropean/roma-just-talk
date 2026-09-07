#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/built/roma\ just\ talk.app" >&2
  exit 2
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PACKAGE="$ROOT/VoiceInkQwen"
APP=$1
SHADER="$APP/Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
APP_LOCK="$ROOT/VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
test -s "$SHADER"

# The preceding Release build supplies the shader; reject a different dependency graph.
# Seed the standalone package's generated lock from that build, retaining its transitive pins.
cp "$APP_LOCK" "$PACKAGE/Package.resolved"
swift package --package-path "$PACKAGE" resolve
python3 - "$APP_LOCK" "$PACKAGE/Package.resolved" <<'PY'
import json, sys
app, package = [json.load(open(path)) for path in sys.argv[1:]]
app_pins = {pin["identity"]: pin for pin in app["pins"]}
assert package["pins"], "Qwen package resolved no dependencies"
for pin in package["pins"]:
    expected = app_pins.get(pin["identity"])
    assert expected is not None, f"Package absent from app graph: {pin['identity']}"
    assert pin["state"]["revision"] == expected["state"]["revision"], f"Revision mismatch: {pin['identity']}"
    assert pin["location"].rstrip("/").removesuffix(".git").lower() == expected["location"].rstrip("/").removesuffix(".git").lower(), f"Source mismatch: {pin['identity']}"
print(f"Verified {len(package['pins'])} package revisions against the app build graph")
PY

BUILD_ARGS=(--package-path "$PACKAGE" -c release --force-resolved-versions -Xswiftc -enable-testing)
swift build "${BUILD_ARGS[@]}" --build-tests
BIN_PATH=$(swift build "${BUILD_ARGS[@]}" --show-bin-path)
TEST_EXECUTABLE="$BIN_PATH/VoiceInkQwenPackageTests.xctest/Contents/MacOS/VoiceInkQwenPackageTests"
test -x "$TEST_EXECUTABLE"

# Pinned MLX resolves mlx.metallib beside the current executable before bundle lookup.
# SwiftPM tests have no Xcode-generated Metal bundle, so reuse the app's compiled shader.
cp "$SHADER" "$(dirname "$TEST_EXECUTABLE")/mlx.metallib"
cmp "$SHADER" "$(dirname "$TEST_EXECUTABLE")/mlx.metallib"
shasum -a 256 "$SHADER"
swift test "${BUILD_ARGS[@]}" --skip-build
