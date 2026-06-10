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

cd "${ROOT_DIR}"

make setup

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
  CODE_SIGN_ENTITLEMENTS="${ROOT_DIR}/VoiceInk/VoiceInk.local.entitlements" \
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
  codesign --force --deep --sign - "${APP_BUNDLE}"
  codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}" 2>&1 | tee "${PROOF_DIR}/codesign-verify.txt"
  codesign -dvvv "${APP_BUNDLE}" 2>&1 | tee "${PROOF_DIR}/codesign-details.txt"
fi

ditto -c -k --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"
shasum -a 256 "${ZIP_PATH}" | tee "${PROOF_DIR}/zip-sha256.txt"

echo "Built ${APP_NAME} at:"
echo "${APP_BUNDLE}"
echo
echo "Packaged:"
echo "${ZIP_PATH}"
