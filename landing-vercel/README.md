# Landing site

Static landing pages plus the full-screen `/demo` browser experience.

The Trust section distinguishes current release behavior from future commitments.
Use the [Trust release checklist](../docs/TRUST_RELEASE_CHECKLIST.md) to verify those
commitments on a public download before strengthening its recommendation.

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
