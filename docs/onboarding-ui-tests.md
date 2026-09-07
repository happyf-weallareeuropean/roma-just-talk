# macOS onboarding interaction tests

`OnboardingRegionViewTests` hosts the production model picker in a real AppKit window. Its country lookup is held by a test actor, so a test can press English, expand advanced choices, skip, or continue before releasing the Taiwan response. Model-file readiness is controlled through the existing download-client seam. Model and language persistence use the real managers and preferences, restored after each test.

## Accessibility boundary

SwiftUI exposes accessibility children as untyped objects. On macOS 26.3.1, a trusted external AX query exported the full tree, but its opaque SwiftUI objects did not survive a cast to `NSAccessibilityProtocol`. AppKit's deprecated informal methods also omitted those objects' labels and identifiers. The tests therefore read the public external AX tree and invoke `AXUIElementPerformAction` for real button presses. There are no private selectors, unsafe casts, production accessibility overrides, or direct calls to the view's action closures.

Each fixture configures its window through the production window manager, waits until it is key and active, then asynchronously launches the test-only `Tools/OnboardingAccessibilityProbe.swift` executable for each fresh query or press. A main-thread `waitUntilExit` would block the host from serving AX requests and is prohibited. The probe:

- Queries or presses only within the host process that launched it, and matches the fixture's unique window title, including a per-fixture UUID.
- Checks effective Accessibility trust before requesting any tree data.
- Discovers advertised attributes and records actual AX errors, foreground state, window identity, and a bounded tree. Transport failures or truncated traversal invalidate the receipt.
- Presses only one exact label or identifier match that advertises the public press action; ambiguous, disabled, unsupported, or failed actions fail the test. Immediately before pressing it rechecks the parent, active host, window identity, and enabled state.
- Has an eight-second traversal bound; the fixture has a twelve-second watchdog and terminates its child on failure or cancellation.

On macOS 26.3.1, an unlabeled checkbox advertises `AXDescription` but returns generic `AXError.failure`. That exact role/attribute/error combination is recorded as an unavailable optional description; the node cannot match a label press. All other unexpected attribute failures remain fatal. Identifier lookup is restricted to `AXButton` for Continue/Skip and `AXDisclosureTriangle` for advanced settings; language choices use labels. This avoids requesting unrelated optional menu identifiers. Tests verify the displayed English model card positively rather than inferring it from an absent Qwen label. Continue must report an explicit Boolean enabled state.

If SwiftUI temporarily reports `cannotComplete` while replacing a node, the fixture retries a fresh complete snapshot at most three times. It never retries a press already reported successful; unresolved errors still fail.

Every fixture requires a successful, trusted receipt for its own active host and exact window. It does not depend on a prior test or an Accessibility Inspector having activated the tree.

## Disposable CI setup

Run `scripts/run-macos-ci-unit-tests.sh` on the disposable macOS Actions runner. This script provisions that runner's Debug test host; do not use it against an installed release or a personal desktop.

The ordering matters:

1. Compile `Tools/OnboardingAccessibilityProbe.swift` to `/tmp/roma-onboarding-diagnostic/ExternalAXProbe`.
2. Build the Debug test app with `xcodebuild build-for-testing`.
3. Derive the **current** Debug app's designated requirement and record the app/probe hashes.
4. Grant that exact Debug host Accessibility and microphone access in the disposable runner; restart TCC to load the scoped grants.
5. Run all `VoiceInkTests` using `test-without-building`, then verify unchanged hashes and requirement.

The app is `com.negentropi.RomaJustTalk`, at `.local-build/Build/Products/Debug/roma just talk.app`. TCC audit evidence attributed the child probe's access to this host. Granting the standalone helper instead is insufficient. XCTest embeds its bundle in the app; changing test sources can change the host signature, so grants must follow the final build.

A console UID alone does not prove an unlocked, interactive desktop. A locked screen or a foreground permission prompt must fail the fixture's readiness checks. Record and resolve the actual runner state rather than weakening the assertions. The normal CI gate must not require an interactive permission click.

The helper is a test dependency and is not included in release packaging. Test results retain the AX receipt and window bitmap. A bitmap proves rendered content, not an unlocked desktop or a successful user interaction.

## Regression acceptance

Keep the protocol-cast known-bad control and the candidate under the same trusted activation and permission conditions. Require the known-bad test to fail and the candidate to pass. Then run all six actual interaction scenarios. The Continue persistence regression additionally requires the same Continue action to fail against the known-bad pre-fix view and pass against the candidate view. Rebuild, freeze, and regrant each changed Debug identity; do not compare an unauthorized host with an authorized one.

Source compilation, external tree enumeration, and a passing single scenario are separate receipts. None alone establishes the full onboarding regression gate.
