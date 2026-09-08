# FluidAudio runtime pin

Roma's macOS and iOS projects pin [negentropi/FluidAudio](https://github.com/negentropi/FluidAudio)
at `56c9c2167efa4363690243709dda4a84f29e5f49`, based directly on upstream
`50aa07193e84b9cf192d8f36041c24a9a4867cd6`. The macOS project and workspace
resolved locks use the same revision. The existing iOS resolved lock has no
FluidAudio entry; its project requirement supplies the exact revision when Xcode
resolves that graph. No unrelated dependency upgrade is included.

## Fork ownership

Roma owns one narrow SDK change: `MLMultiArray.resetData(to:)` uses checked byte
clearing for contiguous Float32 arrays reset to positive zero. Shape and stride
checks preserve logical layout, including singleton dimensions. Other types,
values (including negative zero), and noncontiguous layouts retain the original
scalar assignment. Model files, decoding policy, streaming scheduling, and app
commit behavior are unchanged by this patch.

The fork commit changes exactly these two files:

- [TdtDecoderState.swift](https://github.com/negentropi/FluidAudio/blob/56c9c2167efa4363690243709dda4a84f29e5f49/Sources/FluidAudio/ASR/Parakeet/SlidingWindow/TDT/Decoder/TdtDecoderState.swift)
- [RomaArrayResetTests.swift](https://github.com/negentropi/FluidAudio/blob/56c9c2167efa4363690243709dda4a84f29e5f49/Tests/FluidAudioTests/RomaArrayResetTests.swift)

Keep future changes bounded to this contract. Any upstream update requires an
explicit revision update, semantic verification, and fresh app acceptance.

## Release build gate

After `make local CONFIGURATION=Release`, run:

```sh
bash scripts/test-fluidaudio-package.sh
```

The script requires full Xcode, reads the exact source URL and revision from the
app's project lock, and verifies the clean resolved checkout at
`.local-build/SourcePackages/checkouts/FluidAudio`. Xcode's local repository origin
is followed once to verify the public source URL. An archive of that exact commit
is tested in a fresh `.local-build/fluidaudio-test-evidence/run.*/package` directory;
the dependency checkout is never patched or used as the test build directory.

The Release SwiftPM gate selects `RomaArrayResetTests` and requires five distinct
passing XCTest cases plus the successful five-test suite summary. A missing
suite, zero selected tests, build error, or failing test fails the gate. The cases
compare the complete backing allocation with scalar assignment, including prefix,
stride-gap, and suffix sentinels, for audio-sized arrays, contiguous and singleton
layouts, padded and transposed views, other numeric types, and nonzero or negative
zero values.

The macOS build workflow runs this gate immediately after the Release app build.
It uploads logs, source and toolchain provenance, and exit status as
`roma.fluidaudio-test-evidence`, including failed test attempts. The script does
not launch the app, change signing or TCC, or download models.

## Evidence boundary

Native SDK experiments found exact transcription-output parity across 32 public
PCM result rows, and all five standalone Core ML semantic methods passed for
both the original and candidate implementations. These experiments support the
narrow optimization; they are not full SwiftPM XCTest or app acceptance. The
original implementation also passes the semantic cases, as expected for a
behavior-preserving optimization.

At integration, full SwiftPM XCTest execution is pending on the Xcode CI runner:
the local Command Line Tools environment cannot provide XCTest. The workflow
artifact records that separate result. A fresh exact-revision app build and real
dictation latency/accuracy acceptance remain required. No app-level timing gain
or 250 ms app acceptance is established by the SDK experiments.
