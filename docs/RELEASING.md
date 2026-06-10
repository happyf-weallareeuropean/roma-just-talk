# Releasing

## Release Paths

### Legacy Local DMG

The `v1.80`, `v1.81`, and `v1.82` releases used a CI-built local app artifact and packaged it as a DMG outside the Developer ID workflow. This path does not need Apple signing secrets.

Use the `Build app zip` workflow for this path, download `roma-just-talk-app`, verify it against `roma-just-talk-signing-proof`, then wrap the app in a DMG. Release notes must say the artifact is ad-hoc signed, not Developer ID signed, and not notarized.

### Gatekeeper-Clean Developer ID DMG

Public macOS DMG releases must follow the `v1.79` trust model:

- Developer ID Application signature.
- Hardened runtime enabled.
- Production distribution entitlements.
- App notarized and stapled.
- DMG signed, notarized, and stapled.
- CI proof artifacts for `codesign`, `notarytool`, `stapler`, `spctl`, and SHA-256.

The `Build notarized macOS DMG` workflow is manual-only and requires the secrets below. Use it when a Gatekeeper-clean public DMG is required.

## Required GitHub Secrets

- `APPLE_TEAM_ID`
- `MACOS_DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64`
- `MACOS_DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD`
- `MACOS_DEVELOPER_ID_PROVISIONING_PROFILE_BASE64`
- `APP_STORE_CONNECT_API_KEY_ID`
- `APP_STORE_CONNECT_API_ISSUER_ID`
- `APP_STORE_CONNECT_API_KEY_BASE64`

`MACOS_DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64` is a base64-encoded `.p12` export for the Developer ID Application certificate. `MACOS_DEVELOPER_ID_PROVISIONING_PROFILE_BASE64` is a base64-encoded Developer ID provisioning profile matching the app identifier and capabilities. `APP_STORE_CONNECT_API_KEY_BASE64` is a base64-encoded App Store Connect `.p8` API key.

## Developer ID Release Gate

The `Build notarized macOS DMG` workflow must pass before publishing a DMG release. Use only the notarized DMG from that workflow artifact. The workflow refuses ad-hoc signatures, checks for the Apple team identifier, and requires `embedded.provisionprofile` before packaging.
