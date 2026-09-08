# Transcription language preferences

On macOS, `SelectedLanguage` stores the user's language choice. Model selection,
startup, metadata refresh, streaming toggles, and opening settings must not replace
that choice with a model compatibility fallback. Existing values, including `en`,
remain authoritative; there is no migration that guesses whether an old value was
chosen explicitly.

The selected model resolves an effective language at the picker and request
boundaries using its language options. For example, a saved `auto` uses `en` with
English-only Parakeet and returns to `auto` with Qwen. Native Apple resolves an
unsupported language to `en-US`; models supporting Auto-detect use `auto` instead.
Qwen and cloud requests omit a forced-language hint for `auto`; local Whisper
uses its Auto-detect language value.
English-only Whisper also resolves its prompt for English without replacing the
saved preference or prompt.

Only explicit language choices, onboarding choices, Power Mode application/restore,
and preference reset/import own writes. Power Mode preserves the selected or
snapshotted language; the current model still determines its effective request
language. Missing preferences retain the existing platform registration/default
behavior.

Regression coverage: `TranscriptionModelManagerTests` exercises selection, startup
reload, and metadata refresh across English-only and bilingual models. Core checks
cover request fallback, explicit English, Auto-detect, native/cloud language sets,
Whisper prompts, and Power Mode restoration. A runtime bilingual comparison must
control and record the effective language; changing only the model does not create
an equivalent recognition experiment.
