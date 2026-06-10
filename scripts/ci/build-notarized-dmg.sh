#!/usr/bin/env bash
set -euo pipefail

required_vars=(
  APPLE_TEAM_ID
  MACOS_PROVISIONING_PROFILE_SPECIFIER
  APP_STORE_CONNECT_API_KEY_ID
  APP_STORE_CONNECT_API_ISSUER_ID
  APP_STORE_CONNECT_API_KEY_BASE64
)

for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "Missing required secret: ${var_name}" >&2
    exit 1
  fi
done

APP_NAME="${APP_NAME:-roma just talk}"
SIGNING_IDENTITY="${DEVELOPER_ID_APPLICATION_IDENTITY:-Developer ID Application}"
DERIVED_DATA_PATH="${PWD}/.release-build"
ARCHIVE_PATH="${PWD}/dist/${APP_NAME}.xcarchive"
APP_PATH="${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app"
DIST_DIR="${PWD}/dist"
PROOF_DIR="${DIST_DIR}/signing-proof"
STAGE_DIR="${RUNNER_TEMP:-/tmp}/${APP_NAME}-dmg-stage"
APP_NOTARY_ZIP="${DIST_DIR}/${APP_NAME}.app.zip"
DMG_PATH="${DIST_DIR}/${APP_NAME}.dmg"
API_KEY_PATH="${RUNNER_TEMP:-/tmp}/AuthKey_${APP_STORE_CONNECT_API_KEY_ID}.p8"

rm -rf "${DERIVED_DATA_PATH}" "${ARCHIVE_PATH}" "${DIST_DIR}" "${STAGE_DIR}"
mkdir -p "${DIST_DIR}" "${PROOF_DIR}" "${STAGE_DIR}"

printf '%s' "${APP_STORE_CONNECT_API_KEY_BASE64}" | base64 --decode > "${API_KEY_PATH}"
chmod 600 "${API_KEY_PATH}"

xcodebuild \
  -project VoiceInk.xcodeproj \
  -scheme VoiceInk \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  -archivePath "${ARCHIVE_PATH}" \
  DEVELOPMENT_TEAM="${APPLE_TEAM_ID}" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="${SIGNING_IDENTITY}" \
  CODE_SIGN_ENTITLEMENTS="${PWD}/VoiceInk/VoiceInk.distribution.entitlements" \
  PROVISIONING_PROFILE_SPECIFIER="${MACOS_PROVISIONING_PROFILE_SPECIFIER}" \
  ENABLE_HARDENED_RUNTIME=YES \
  ONLY_ACTIVE_ARCH=NO \
  ARCHS="arm64 x86_64" \
  archive

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Archive did not produce app at ${APP_PATH}" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "${APP_PATH}" 2>&1 | tee "${PROOF_DIR}/app-codesign-verify.txt"
codesign -dvvv "${APP_PATH}" 2>&1 | tee "${PROOF_DIR}/app-codesign-details.txt"
codesign -d --entitlements :- "${APP_PATH}" > "${PROOF_DIR}/app-entitlements.plist" 2> "${PROOF_DIR}/app-entitlements.stderr"

if grep -q "Signature=adhoc" "${PROOF_DIR}/app-codesign-details.txt"; then
  echo "Refusing to package ad-hoc signed app" >&2
  exit 1
fi

grep -q "Authority=Developer ID Application" "${PROOF_DIR}/app-codesign-details.txt"
grep -q "TeamIdentifier=${APPLE_TEAM_ID}" "${PROOF_DIR}/app-codesign-details.txt"

if [[ ! -f "${APP_PATH}/Contents/embedded.provisionprofile" ]]; then
  echo "Refusing to package app without embedded.provisionprofile" >&2
  exit 1
fi

ditto -c -k --keepParent "${APP_PATH}" "${APP_NOTARY_ZIP}"
xcrun notarytool submit "${APP_NOTARY_ZIP}" \
  --key "${API_KEY_PATH}" \
  --key-id "${APP_STORE_CONNECT_API_KEY_ID}" \
  --issuer "${APP_STORE_CONNECT_API_ISSUER_ID}" \
  --wait 2>&1 | tee "${PROOF_DIR}/app-notarytool-submit.txt"

xcrun stapler staple "${APP_PATH}" 2>&1 | tee "${PROOF_DIR}/app-stapler-staple.txt"
xcrun stapler validate "${APP_PATH}" 2>&1 | tee "${PROOF_DIR}/app-stapler-validate.txt"

ditto "${APP_PATH}" "${STAGE_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGE_DIR}/Applications"
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${STAGE_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}" 2>&1 | tee "${PROOF_DIR}/dmg-create.txt"

codesign --force --timestamp --sign "${SIGNING_IDENTITY}" "${DMG_PATH}" 2>&1 | tee "${PROOF_DIR}/dmg-codesign.txt"
xcrun notarytool submit "${DMG_PATH}" \
  --key "${API_KEY_PATH}" \
  --key-id "${APP_STORE_CONNECT_API_KEY_ID}" \
  --issuer "${APP_STORE_CONNECT_API_ISSUER_ID}" \
  --wait 2>&1 | tee "${PROOF_DIR}/dmg-notarytool-submit.txt"
xcrun stapler staple "${DMG_PATH}" 2>&1 | tee "${PROOF_DIR}/dmg-stapler-staple.txt"
xcrun stapler validate "${DMG_PATH}" 2>&1 | tee "${PROOF_DIR}/dmg-stapler-validate.txt"

spctl -a -vv -t exec "${APP_PATH}" 2>&1 | tee "${PROOF_DIR}/app-spctl.txt"
spctl -a -vv -t open --context context:primary-signature "${DMG_PATH}" 2>&1 | tee "${PROOF_DIR}/dmg-spctl.txt"
shasum -a 256 "${DMG_PATH}" | tee "${PROOF_DIR}/dmg-sha256.txt"
