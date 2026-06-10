# Releasing

## Gatekeeper Requirements

Public macOS DMG releases must follow the `v1.79` trust model:

- Developer ID Application signature.
- Hardened runtime enabled.
- Production distribution entitlements.
- App notarized and stapled.
- DMG signed, notarized, and stapled.
- CI proof artifacts for `codesign`, `notarytool`, `stapler`, `spctl`, and SHA-256.

Do not upload a `make local`, `scripts/build-app.sh`, or other ad-hoc artifact as a public DMG. Local/ad-hoc builds can still be useful for debugging, but normal users will hit Gatekeeper trust failures.

## Required GitHub Secrets

- `APPLE_TEAM_ID`
- `MACOS_DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64`
- `MACOS_DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD`
- `MACOS_DEVELOPER_ID_PROVISIONING_PROFILE_BASE64`
- `APP_STORE_CONNECT_API_KEY_ID`
- `APP_STORE_CONNECT_API_ISSUER_ID`
- `APP_STORE_CONNECT_API_KEY_BASE64`

`MACOS_DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64` is a base64-encoded `.p12` export for the Developer ID Application certificate. `MACOS_DEVELOPER_ID_PROVISIONING_PROFILE_BASE64` is a base64-encoded Developer ID provisioning profile matching the app identifier and capabilities. `APP_STORE_CONNECT_API_KEY_BASE64` is a base64-encoded App Store Connect `.p8` API key.

## Release Gate

The `Build notarized macOS DMG` workflow must pass before publishing a DMG release. Use only the notarized DMG from that workflow artifact. The workflow refuses ad-hoc signatures, checks for the Apple team identifier, and requires `embedded.provisionprofile` before packaging.
