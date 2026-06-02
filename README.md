<div align="center">
  <img src="docs/assets/roma-just-talk-logo.png" width="180" height="180" />
  <h1>roma-just-talk</h1>
  <p>speak before you press the hotkey.</p>
  <p>rethink UX: pre-roll voice capture, -87% bin size & -83% ram usage (780mb → 132mb), local & cloud stt solution both available.</p>
  <p>did u know speak is 3~4x faster than type? now u know</p>

  [![License](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
  ![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-brightgreen)
  [![GitHub release (latest by date)](https://img.shields.io/github/v/release/happyf-weallareeuropean/roma-just-talk)](https://github.com/happyf-weallareeuropean/roma-just-talk/releases)
  ![GitHub all releases](https://img.shields.io/github/downloads/happyf-weallareeuropean/roma-just-talk/total)
  ![GitHub stars](https://img.shields.io/github/stars/happyf-weallareeuropean/roma-just-talk?style=social)
  <p>
    <a href="https://github.com/happyf-weallareeuropean/roma-just-talk/releases">Download</a> •
    <a href="https://github.com/Beingpax/VoiceInk">Upstream VoiceInk</a>
  </p>

  <a href="https://github.com/happyf-weallareeuropean/roma-just-talk/releases/latest">
    <img src="https://img.shields.io/badge/Download%20Latest-macOS%20App-blue?style=for-the-badge&logo=apple" alt="Download roma-just-talk" width="250"/>
  </a>
</div>

---

roma-just-talk is a native macOS voice-to-text app forked from [VoiceInk](https://github.com/Beingpax/VoiceInk).

Most dictation apps wait for the hotkey, then open the mic. That means you pause, prepare, press, then speak. This fork explores the other direction: keep a short rolling voice buffer, so the app can catch what you already started saying.

VoiceInk made dictation feel instant after recording starts. roma-just-talk is interested in the moment before that: speech that begins naturally, then gets committed when you press the shortcut.

![VoiceInk Mac App](https://github.com/user-attachments/assets/12367379-83e7-48a6-b52c-4488a6a04bba)

## What Makes This Different

- **Speak before the hotkey**: a short pre-roll buffer can include the words you said just before triggering capture
- **Pre-roll capture UX**: not always transcribing, just buffering enough that recording does not start from zero
- **Local or cloud**: use local models when you want control, cloud/custom models when you want speed, quality, or experiments
- **Less ceremony**: talk first, decide what to do with it second
- **Built on VoiceInk**: keeps the strong macOS base, shortcuts, dictionary, app-aware modes, and transcription pipeline

Current status: app bundle name, icon, and many internal labels still come from VoiceInk. The fork direction is changing first; full rebrand comes after the UX proves itself.

## Features

- 🎙️ **Pre-Roll Capture**: Keep a short mic buffer so the start of your thought is not lost
- 🧪 **Model Playground**: Run local models, cloud providers, or custom endpoints depending on the workflow
- ⚡ **Power Mode**: Intelligent app detection automatically applies your perfect pre-configured settings based on the app/ URL you're on
- 🧠 **Context Aware**: Smart AI that understands your screen content and adapts to the context
- 🎯 **Global Shortcuts**: Configurable keyboard shortcuts for quick recording and push-to-talk functionality
- 📝 **Personal Dictionary**: Train the AI to understand your unique terminology with custom words, industry terms, and smart text replacements
- 🔄 **Smart Modes**: Instantly switch between AI-powered modes optimized for different writing styles and contexts
- 🤖 **AI Assistant**: Built-in voice assistant mode for a quick chatGPT like conversational assistant

## Get Started

### Download
Download the latest fork release from [GitHub Releases](https://github.com/happyf-weallareeuropean/roma-just-talk/releases).

The current published app asset is still based on the upstream VoiceInk release while this fork gets its own build and release flow.

#### Homebrew
Upstream VoiceInk can also be installed via `brew`:

```shell
brew install --cask voiceink
```

### Build from Source
You can build the app yourself by following [BUILDING.md](BUILDING.md).

## Requirements

- macOS 14.4 or later

## Documentation

- [Building from Source](BUILDING.md) - Detailed instructions for building the project
- [Windows Port Direction](docs/windows-port.md) - Least-redundant path toward Windows support
- [Contributing Guidelines](CONTRIBUTING.md) - Original upstream contribution notes
- [Code of Conduct](CODE_OF_CONDUCT.md) - Our community standards

## Contributing

This fork is early. Issues, experiments, and focused patches are welcome when they help the pre-roll dictation direction.

Useful contributions right now:
- Reporting bugs via [issues](https://github.com/happyf-weallareeuropean/roma-just-talk/issues)
- Testing pre-roll capture in real macOS writing workflows
- Improving rough docs left over from the upstream project
- Proposing focused changes that make speak-before-hotkey dictation faster, calmer, or more reliable

For build instructions, see [BUILDING.md](BUILDING.md).

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

## Support

If you encounter any issues or have questions, please:
1. Check the existing issues in the GitHub repository
2. Create a new issue if your problem isn't already reported
3. Provide as much detail as possible about your environment and the problem

## Acknowledgments

roma-just-talk is built on top of [VoiceInk](https://github.com/Beingpax/VoiceInk). The core app, original product direction, and much of the current implementation come from Pax and the VoiceInk project.

### Core Technology
- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) - High-performance inference of OpenAI's Whisper model
- [FluidAudio](https://github.com/FluidInference/FluidAudio) - Used for Parakeet model implementation

### Essential Dependencies
- [Sparkle](https://github.com/sparkle-project/Sparkle) - Keeping VoiceInk up to date
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) - User-customizable keyboard shortcuts
- [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin) - Launch at login functionality
- [MediaRemoteAdapter](https://github.com/ejbills/mediaremote-adapter) - Media playback control during recording
- [Zip](https://github.com/marmelroy/Zip) - File compression and decompression utilities
- [SelectedTextKit](https://github.com/tisfeng/SelectedTextKit) - A modern macOS library for getting selected text
- [Swift Atomics](https://github.com/apple/swift-atomics) - Low-level atomic operations for thread-safe concurrent programming


---

Built from VoiceInk, then pointed at speak-before-hotkey dictation.
