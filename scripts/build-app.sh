#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-roma just talk}"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${ROOT_DIR}/.app-build}"
DIST_DIR="${ROOT_DIR}/dist"
PROOF_DIR="${DIST_DIR}/signing-proof"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
ZIP_PATH="${DIST_DIR}/${APP_NAME}.app.zip"
BUILT_APP="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
ENTITLEMENTS_FILE="${ROOT_DIR}/VoiceInk/VoiceInk.local.entitlements"

cd "${ROOT_DIR}"

make setup

require_entitlement() {
  local key="$1"
  local file="$2"
  local key_path="${key//./\\.}"
  plutil -extract "${key_path}" raw "${file}" >/dev/null
}

plutil -lint "${ENTITLEMENTS_FILE}" >/dev/null
require_entitlement com.apple.security.automation.apple-events "${ENTITLEMENTS_FILE}"
require_entitlement com.apple.security.device.audio-input "${ENTITLEMENTS_FILE}"
require_entitlement com.apple.security.screen-capture "${ENTITLEMENTS_FILE}"

rm -rf "${DERIVED_DATA_PATH}" "${DIST_DIR}"
mkdir -p "${DIST_DIR}" "${PROOF_DIR}"

xcodebuild \
  -project VoiceInk.xcodeproj \
  -scheme VoiceInk \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  -xcconfig LocalBuild.xcconfig \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  DEVELOPMENT_TEAM="" \
  CODE_SIGN_ENTITLEMENTS="${ENTITLEMENTS_FILE}" \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) LOCAL_BUILD' \
  ONLY_ACTIVE_ARCH=YES \
  ARCHS=arm64 \
  build

if [[ ! -d "${BUILT_APP}" ]]; then
  echo "Build did not produce app at ${BUILT_APP}" >&2
  exit 1
fi

ditto "${BUILT_APP}" "${APP_BUNDLE}"
xattr -cr "${APP_BUNDLE}" || true

if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - --options runtime --timestamp=none --entitlements "${ENTITLEMENTS_FILE}" "${APP_BUNDLE}"
  codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}" 2>&1 | tee "${PROOF_DIR}/codesign-verify.txt"
  codesign -dvvv "${APP_BUNDLE}" 2>&1 | tee "${PROOF_DIR}/codesign-details.txt"
  codesign -d --entitlements :- "${APP_BUNDLE}" > "${PROOF_DIR}/entitlements.plist" 2> "${PROOF_DIR}/entitlements.stderr"
  require_entitlement com.apple.security.automation.apple-events "${PROOF_DIR}/entitlements.plist"
  require_entitlement com.apple.security.device.audio-input "${PROOF_DIR}/entitlements.plist"
  require_entitlement com.apple.security.screen-capture "${PROOF_DIR}/entitlements.plist"
fi

ditto -c -k --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"
shasum -a 256 "${ZIP_PATH}" | tee "${PROOF_DIR}/zip-sha256.txt"

echo "Built ${APP_NAME} at:"
echo "${APP_BUNDLE}"
echo
echo "Packaged:"
echo "${ZIP_PATH}"
