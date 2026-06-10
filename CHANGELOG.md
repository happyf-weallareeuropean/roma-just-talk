# Changelog

## v1.89 - Unreleased

- Restored the real Developer ID signed, notarized, and stapled DMG workflow and removed the fake ad-hoc DMG artifact from the app-zip build.
- Fixed Special shortcut flex-off handling so modifier-only shortcuts fail closed when the key-evidence event tap is unavailable.

## v1.88 - 2026-06-10

- Added a DMG build artifact alongside the app zip so Gatekeeper behavior can be tested against both packaging formats.
- Added Special shortcut sub-settings for keydown preload behavior, key-down-only flex, and empty-tap paste-last fallback.

## v1.87 - 2026-06-09

- Fixed a post-keyup latency regression by finalizing the recording file without restarting the pre-roll AudioUnit on every stop.

## v1.86 - 2026-06-09

- Reissued the release as v1.86 after the v1.84 and v1.85 tags failed before publishing an app asset.
- Hid the menu bar icon by default for fresh installs while keeping Dock-icon hiding as a separate setting.
- Added Special shortcut mode as the fresh default with Left Shift: start recording on keydown, decide on keyup, and cancel typing cases where another key was released during the hold.
- Fixed app zip packaging so the release harness preserves and verifies local macOS entitlements instead of stripping them during final signing.

## v1.83 - 2026-06-08

- Switched release packaging to a simple Airpods-style ad-hoc signed `.app.zip` build.
- Removed dashes from the generated app wrapper and bundle name so macOS shows roma just talk.

## v1.82 - 2026-06-08

- Renamed the generated app wrapper and bundle name to roma-just-talk so macOS system dialogs use the fork name.

## v1.81 - 2026-06-08

- Replaced the README, source app icon, and menu bar logo with the roma-just-talk split-keyboard mark.
- Changed fresh defaults to Parakeet V2, menu-bar-only mode, muted sound feedback, and launch-at-login, with Parakeet auto-downloaded for the selected default.
- Renamed the visible app shell to roma-just-talk while leaving bundle identifiers and update infrastructure unchanged.

## v1.80 - 2026-06-01

- Added guided macOS permission grants with PermissionFlow.
- Fixed permission refresh so Microphone and Accessibility grants update while VoiceInk is running.
- Added an inline "Relaunch to Apply" path for macOS permissions that TCC grants but only activates for a fresh process.
- Made Screen Context optional and removed it from the required setup gate.
- Avoided disruptive direct Screen Recording prompts and removed the noisy floating screen-recording hint.
- Added GitHub Actions build artifact packaging for the macOS app.
- Updated the project pitch toward pre-roll voice capture and rolling voice buffer language.
