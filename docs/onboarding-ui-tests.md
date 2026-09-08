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

## Short-window visual check

The disposable Mac can constrain the hosted content to 950 × 697 points even when the requested onboarding window is taller. Compare the Taiwan suggestion and explicit English screenshots at that same actual content size: the complete setup subtitle, Next, and Skip must remain visible, while the model list scrolls within the remaining height. Exercise the real navigation controls in the same fixture. A passing AX press alone does not establish visibility: macOS can press an offscreen control.

The known-bad fixed 420-point minimum model panel visibly clipped Next and Skip and truncated the subtitle. Retain that screenshot alongside the candidate at matching dimensions; larger-window screenshots cannot establish the short-window regression.

## Full production window on a smaller desktop

The hosted model panel check does not exercise the app scene's sizing. Launch the packaged app on the same 1280 × 800 point display with a 697-point visible desktop, retaining the menu bar and Dock. Record the screen's `visibleFrame`, backing scale, app window frame, content rectangle, build hash, and actual screen captures. The known-bad v1.95.1 candidate had a 950 × 812 point window, extending below the desktop even though its isolated model panel passed.

`testProductionOnboardingWindowFitsVisibleDesktopAndKeepsUserResize` calls the actual window configurator and checks frame containment and repeated-configuration resize preservation. Run the identical test against the known-bad configurator and candidate on that smaller display. The complete app additionally must fit after SwiftUI settles; this catches a scene constraint that enlarges the window after AppKit configures it.

Walk the actual welcome, each permission page (including audio device and shortcut choices), model selection, and tutorial. Navigation must remain visible above the Dock; informational content may scroll. Exercise real Next/Skip controls and the tutorial's existing completion rules. Compare known-bad and candidate screenshots at identical display geometry. Reopen onboarding through Settings, then finish it and verify the main window's saved position and size return. Finally resize an onboarding window and confirm subsequent view updates do not recenter it. Record those full-window results separately from the six regional component tests.

The window accessor keys configuration by the existing main/setup identity and reapplies it when SwiftUI updates a reused representable or attaches it to a different window. It coalesces pending updates and skips unchanged window/configuration pairs, so ordinary view updates do not reset placement. `testWindowAccessorReconfiguresAfterSwiftUIReusesItsView` changes a real `NSHostingView` root configuration and waits for the callbacks on its actual window. Retain a known-bad control with the old make-only callback (and an unused configuration ID solely to compile the same test). This bridge regression supplements the actual Settings Reset and saved-main-frame walkthrough; it does not replace them.

The main window manager retains its live frame while that window temporarily hosts setup, and restores it once on return. Cross-launch placement keeps the existing AppKit autosave behavior. In the observed SwiftUI window, an explicit `saveFrame(usingName:)` call at Reset did not produce a frame that `setFrameUsingName` could restore; retaining the live frame avoids making an in-process role transition depend on persistence. Validate this with the actual moved-window Settings Reset → Skip walkthrough, keeping the diagnostic save/restore failure receipt.
