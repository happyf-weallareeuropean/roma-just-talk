#!/usr/bin/env bash
set -euo pipefail

required_vars=(
  MACOS_DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64
  MACOS_DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD
  MACOS_DEVELOPER_ID_PROVISIONING_PROFILE_BASE64
)

for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "Missing required secret: ${var_name}" >&2
    exit 1
  fi
done

KEYCHAIN_PASSWORD="$(uuidgen)"
KEYCHAIN_PATH="${RUNNER_TEMP}/app-signing.keychain-db"
CERTIFICATE_PATH="${RUNNER_TEMP}/developer-id-application.p12"
PROFILE_PATH="${RUNNER_TEMP}/developer-id.provisionprofile"
PROFILE_PLIST_PATH="${RUNNER_TEMP}/developer-id-profile.plist"
PROFILE_DIR="${HOME}/Library/MobileDevice/Provisioning Profiles"

printf '%s' "${MACOS_DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64}" | base64 --decode > "${CERTIFICATE_PATH}"
printf '%s' "${MACOS_DEVELOPER_ID_PROVISIONING_PROFILE_BASE64}" | base64 --decode > "${PROFILE_PATH}"

security create-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_PATH}"
security set-keychain-settings -lut 21600 "${KEYCHAIN_PATH}"
security unlock-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_PATH}"
security import "${CERTIFICATE_PATH}" \
  -P "${MACOS_DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD}" \
  -A \
  -t cert \
  -f pkcs12 \
  -k "${KEYCHAIN_PATH}"
security list-keychains -d user -s "${KEYCHAIN_PATH}" $(security list-keychains -d user | tr -d '"')
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_PATH}"
security find-identity -v -p codesigning "${KEYCHAIN_PATH}"

security cms -D -i "${PROFILE_PATH}" > "${PROFILE_PLIST_PATH}"
PROFILE_UUID="$(/usr/libexec/PlistBuddy -c 'Print UUID' "${PROFILE_PLIST_PATH}")"
PROFILE_NAME="$(/usr/libexec/PlistBuddy -c 'Print Name' "${PROFILE_PLIST_PATH}")"

mkdir -p "${PROFILE_DIR}"
cp "${PROFILE_PATH}" "${PROFILE_DIR}/${PROFILE_UUID}.provisionprofile"

if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    echo "MACOS_PROVISIONING_PROFILE_SPECIFIER=${PROFILE_NAME}"
    echo "MACOS_PROVISIONING_PROFILE_UUID=${PROFILE_UUID}"
  } >> "${GITHUB_ENV}"
fi
