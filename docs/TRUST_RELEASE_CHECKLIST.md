# Work behind the Trust commitments

Owner: Felix. Use this checklist before recommending a public Mac release for everyday use.
It turns the [landing commitments](../landing-vercel/index.html) into release work.
This is a manual checklist, not an implemented CI gate or evidence that a release passed.
No boxes below are completed by adding this document.

## Changes and proof required

Use synthetic audio, clipboard text, window text, and provider keys on a dedicated test Mac.
Do not test with a customer's recordings, credentials, or open documents.

| Customer expectation | Work to deliver | Evidence to record on the candidate download |
| --- | --- | --- |
| Off stops collection | Make Clipboard Context and Screen Context Off prevent their respective reads, not just exclude content from an AI request. | Exercise each switch Off and On with distinguishable synthetic clipboard/window text. Observe the clipboard-read and window-capture paths as well as outbound requests. No network traffic alone does not prove no local reads. Record permission state and whether any other visible window was captured. |
| I know when my speech leaves the Mac | Explain microphone buffering and each cloud transfer before use; make local transcription and cloud text processing separate choices. | Record capture and outbound audio before, during, and after the shortcut with local/cloud models and each buffer setting. Test AI Enhancement Off/On separately. Record destinations and categories of data, not private payloads. Verify displayed explanations against those observations. |
| Credentials receive appropriate protection | Store provider keys in macOS Keychain in the public build, including upgrades from preference-based storage. | Use a disposable canary key. Verify save, relaunch, replace, and delete. Check preferences, logs, and exports for the canary without printing it. Test migration on a separate upgrade account; do not claim migration proof from a fresh install. |
| Saving and deleting history are understandable | Explain the default retention policy and distinguish deleting audio from deleting records. | Make sample recordings, apply both cleanup modes, and delete records manually. Relaunch and inspect remaining files and text. Verify that only selected records are removed and that wording never promises deletion from a provider's systems. |
| Installation works with normal Mac protections | Produce a correctly signed and Apple-notarized release; explain each permission before requesting it. | Download the public file through the normal browser path on a clean Mac. Keep quarantine and Gatekeeper enabled. Check signature, notarization, first launch, and permission prompts. A successful Open Anyway flow for an ad hoc build does not pass the notarization requirement. |
| I can rely on ordinary dictation | Test the actual download before recommending everyday use. | Exercise first and later dictations, pre-shortcut speech, cancellation, permissions denied/revoked, text insertion without overwriting surrounding text, and quitting. Verify capture stops on quit. Record Mac, macOS, model, target apps, failures, and skipped cases. |

For a defect fix, reproduce failure on the known-bad build and success on the candidate using
the same input and user-relevant conditions. A baseline that does not fail is not valid
regression proof. Record the baseline and candidate versions and the test-tool version.

Existing starting points:

- [Runtime E2E guide](RUNTIME_E2E_HARNESS.md) covers real microphone input, shortcuts,
  insertion, and rendered text.
- [Remote E2E stage](remote-e2e-stage.md) provides dedicated Namespace Macs and distribution
  testing. Its CI-artifact path is not, by itself, proof of the public release download.

The privacy, credential, and history observations above still need their own test procedures.
Do not mark them passed because the runtime or distribution lane passed.

## Public release record

- [ ] Identify the public download URL, version, source commit, and SHA-256. Preserve the file
  unchanged during testing. If packaging, signing, or any bytes change, test the resulting file.
- [ ] Record each check as pass, fail, or not tested. Include the tested hardware, macOS,
  settings, models, and applications. A successful compile is not a passed runtime test.
- [ ] Put results and remaining limitations in that release's notes, with links to redacted
  evidence. Separate completed protections from planned changes. Include privacy behavior
  changes so users can decide about upgrading before they install.
- [ ] Check the release notes contain the relevant changelog entries.
- [ ] Update the Trust version, evidence links, current recommendation, and pinned download
  links together. Do not recommend everyday use while the requirements above remain unverified
  or fail. An evaluation release must retain its label and material limitations.

Start the release note evidence record with these fields:

```text
Version / source commit:
Public download URL / SHA-256:
Test date / Mac / macOS:
Settings / models / target applications:
Check / result / evidence link:
Known-bad and candidate regression evidence, where applicable:
Known problems / cases not tested:
Privacy changes since the prior release:
Recommendation: evaluation only or everyday use, with the evidence supporting it.
```

## Handling a report

- [ ] Acknowledge the report and tell the person what you understand. Do not promise a
  response time or fix date you cannot meet.
- [ ] Start from their description. Try a synthetic reproduction yourself. If more evidence
  is needed, request the smallest useful piece and explain how to remove private details.
  Customer debugging and retesting remain optional.
- [ ] Keep privacy and security reports private. Record what you reproduced, what remains
  uncertain, and the next action. Tell the reporter if no fix is available yet.
- [ ] When a fix ships, identify it in release notes and reply with the fixed version.
  Do not present an unshipped commit as an available fix.
- [ ] Publish a technical summary only after the risk is addressed. Exclude identifying
  information and private-message quotations unless the person explicitly permits them.
