# Landing site

Static landing pages plus the full-screen `/demo` browser experience.

`GET /api/region` supports the Mac's local model setup suggestion. It returns only
a two-letter ISO country code, for example `{"countryCode":"TW"}`
(or `{"countryCode":null}` when unknown), using Vercel's
[`x-vercel-ip-country` header](https://vercel.com/docs/headers/request-headers#x-vercel-ip-country).
The handler does not log or store location and disables browser/CDN caching.
This is a preference hint, never authentication or a transcription service.
The Mac requests it once during eligible first local setup with a two-second timeout;
an explicit choice or existing model takes precedence, and lookup failure keeps English selected.
The onboarding explanation and Trust privacy disclosure identify this approximate IP-country
lookup, Vercel hosting, and that no audio is sent. The app does not persist the country.
TW/CN/HK/MO/SG suggest Chinese + English; all other/unknown countries suggest English.
On Apple silicon with macOS 15 or later, the bilingual choice uses the local Qwen model,
about 1 GB to download; automatic language
detection handles mixed speech and Traditional Chinese output. Existing explicit language
preferences remain intact. Its several-GB free-memory guidance reflects a larger runtime
footprint than the English-only Parakeet model, not the model download size.

The Trust section distinguishes current release behavior from future commitments.
Use the [Trust release checklist](../docs/TRUST_RELEASE_CHECKLIST.md) to verify those
commitments on a public download before strengthening its recommendation.

Mac download links open a setup dialog while the browser requests the archive.
The dialog does not claim that downloading succeeded. It shows a Terminal command
and an agent prompt, with the Open Anyway GUI alternative collapsed. Copy failures
select the text for manual copying. The command assumes the extracted app is at
`/Applications/roma just talk.app` and removes only its quarantine attribute; it
does not sign/notarize the app or grant macOS privacy permissions.

Keep `setup.js` and `setup.css` loaded on pages offering Mac downloads. Release
links, Trust disclosures, and the release evidence record must advance together.

Deploy from the repository root: the existing Vercel project has
`landing-vercel` configured as its Root Directory. The root `.vercelignore`
allows only site files and excludes app sources and private test results.
Run `vercel deploy --dry --json` there to inspect the upload, then
`vercel deploy` for a preview. Deploying from inside this directory duplicates
the configured root and fails. Advance production only with the verified release.

```sh
npm install
npm run dev
```

The demo starts browser speech recognition when the page loads. It keeps up to
the previous three seconds of recognized words in the tab, adds speech heard
while Left Shift is held, and inserts the claimed words on release. There is no
model download, site transcription API, or Roma microphone-audio upload. The
browser may process audio on the device or send it to its own speech provider.
Moving the pointer to the top edge, or tapping its slim touch handle, reveals
site navigation without framing the demo as a regular landing page.

```sh
npm test
npm run test:e2e
```

The browser test uses installed Chrome with a deterministic SpeechRecognition
implementation so it can prove the whole interaction without a network speech
service.

The separate macOS hardware lane proves the part that suite cannot: it starts a
CoreAudio WAV player 1.1 seconds before Left Shift, binds the player directly to
BlackHole's device UID, starts the timing clock when the first frame has played
through that device, waits for the final frame, and then releases Shift.
The player records the rendered mixer level, and the expected opening word proves
pre-trigger audio reached Chrome. The lane rejects fixtures below -30 dBFS RMS
and records a short, isolated BlackHole loopback before it starts speech
recognition. It then records accuracy and key-up latency from Chrome's real
speech service, restores, and verifies the original input and output. The lane
resets BlackHole's output gain after each
Chrome microphone open because the driver shares that gain with its input. CI
uses the public `samples/jfk.wav` fixture pinned to a whisper.cpp commit and
SHA-256, then restores and verifies BlackHole's prior gain and mute state.

```sh
ROMA_DEMO_AUDIO_PLAYER=/absolute/path/to/compiled/roma-play-wav \
ROMA_DEMO_AUDIO_FIXTURE=/absolute/path/to/fixture.wav \
ROMA_DEMO_EXPECTED_TRANSCRIPT="expected fixture words" \
bash scripts/run-real-audio-e2e.sh
```

This lane needs macOS, Google Chrome, BlackHole 2ch, `SwitchAudioSource`, Chrome
microphone permission, and network access to Chrome's speech provider. CI runs it
on a fresh Namespace Mac. It launches the signed Chrome app through macOS before
Playwright connects, then uploads the JSON timing receipt, screenshot, trace,
video, and browser logs. The 1.1-second lead is measured from the macOS timestamp
captured inside CoreAudio's played-back callback, then cross-checked against the
system realtime clock. It does not start when Node receives the player's output.
