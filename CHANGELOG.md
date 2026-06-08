# Changelog

## v1.81 - Unreleased

- Replaced the README, source app icon, and menu bar logo with the roma-just-talk split-keyboard mark.
- Changed fresh defaults to Parakeet V2, menu-bar-only mode, muted sound feedback, and launch-at-login, with Parakeet auto-downloaded for the selected default.

## v1.80 - 2026-06-01

- Added guided macOS permission grants with PermissionFlow.
- Fixed permission refresh so Microphone and Accessibility grants update while VoiceInk is running.
- Added an inline "Relaunch to Apply" path for macOS permissions that TCC grants but only activates for a fresh process.
- Made Screen Context optional and removed it from the required setup gate.
- Avoided disruptive direct Screen Recording prompts and removed the noisy floating screen-recording hint.
- Added GitHub Actions build artifact packaging for the macOS app.
- Updated the project pitch toward pre-roll voice capture and rolling voice buffer language.
