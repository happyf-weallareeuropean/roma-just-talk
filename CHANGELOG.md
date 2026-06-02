# Changelog

## v1.81 - Unreleased

- Improved final dictation cleanup for mid-sentence fragments, stray bracket wrappers, pause sounds, repeated words, obvious self-corrections, and spoken formatting/punctuation commands.
- Improved cleanup for hyphenated pause sounds such as "mm-hmm" and "uh-huh".
- Removed punctuated discourse fillers such as ", like," and ", you know." without dropping meaningful uses.
- Collapsed obvious repeated short sentences from dictated output.
- Expanded bounded self-correction cleanup for "never mind", "no sorry", and "or rather" corrections.
- Added spoken quote and parenthesis formatting commands.
- Added spoken square bracket and brace formatting commands.
- Preserved dictated quote and parenthesis fragments through final insertion cleanup.
- Formatted inline numbered-list dictation with multiple markers onto separate lines.
- Preserved dotted numeric text such as version numbers during punctuation cleanup.
- Added guarded spoken Markdown formatting for headings, task checkboxes, and code fences.
- Added guarded spoken Markdown formatting for inline code and links.
- Tightened spoken inline-code formatting so trailing prose stays outside backticks.
- Tightened spoken Markdown link formatting so trailing prose stays outside links.
- Added guarded spoken code-case formatting for camelCase, snake_case, kebab-case, and PascalCase identifiers.
- Tightened spoken code-case formatting so trailing prose stays outside identifiers.
- Added guarded spoken slash, backslash, dash, hyphen, at sign, dot, and underscore formatting commands.
- Added guarded spoken URL cleanup for "https colon slash slash" and "www dot" dictation.
- Tightened spoken URL cleanup so trailing prose after a domain stays outside the URL.
- Added guarded date, time, currency, and percent cleanup for natural dictation.
- Added guarded cleanup for spoken decimal values and word-based currency/percent amounts.
- Added guarded numeric month-date cleanup such as "June 2 2026".
- Tightened date and currency cleanup so verb phrases and weight units stay unchanged.
- Tightened compact symbol cleanup so prose such as "dot notation" stays unchanged.
- Added cursor-aware cleanup for standalone spoken punctuation fragments such as "comma" and "question mark".
- Avoided duplicate punctuation when ASR already punctuates spoken punctuation commands.
- Improved cursor insertion spacing after punctuation and before dictated opening quotes or parentheses.
- Preserved meaningful bracketed or parenthesized dictated text while still removing known non-speech labels.
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
