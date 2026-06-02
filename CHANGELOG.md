# Changelog

## v1.81 - Unreleased

- Improved final dictation cleanup for mid-sentence fragments, stray bracket wrappers, pause sounds, repeated words, obvious self-corrections, and spoken formatting/punctuation commands.
- Improved cleanup for hyphenated pause sounds such as "mm-hmm" and "uh-huh".
- Collapsed obvious repeated short sentences from dictated output.
- Added spoken quote and parenthesis formatting commands.
- Added guarded spoken slash, backslash, dash, and hyphen formatting commands.
- Added cursor-aware cleanup for standalone spoken punctuation fragments such as "comma" and "question mark".
- Improved cursor insertion spacing after punctuation and before dictated opening quotes or parentheses.
- Removed common ASR boilerplate such as video/subtitle closing phrases from dictated output.
- Improved cursor-context lookup for rich editors that expose focused text ranges without exposing the full field value.

## v1.80 - 2026-06-01

- Added guided macOS permission grants with PermissionFlow.
- Fixed permission refresh so Microphone and Accessibility grants update while VoiceInk is running.
- Added an inline "Relaunch to Apply" path for macOS permissions that TCC grants but only activates for a fresh process.
- Made Screen Context optional and removed it from the required setup gate.
- Avoided disruptive direct Screen Recording prompts and removed the noisy floating screen-recording hint.
- Added GitHub Actions build artifact packaging for the macOS app.
- Updated the project pitch toward pre-roll voice capture and rolling voice buffer language.
