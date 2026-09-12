import Foundation
@testable import VoiceInkCore

final class UpdateExperienceTests: XCTestCase {
    func testTracksUseOnlyRomaReleaseFeeds() {
        XCTAssertEqual(VoiceInkUpdateTrack.stable.feedURL.absoluteString, "https://github.com/negentropi/roma-just-talk/releases/latest/download/appcast.xml")
        XCTAssertEqual(VoiceInkUpdateTrack.prerelease.feedURL.absoluteString, "https://github.com/negentropi/roma-just-talk/releases/latest/download/appcast-prerelease.xml")
        XCTAssertEqual(VoiceInkUpdatePreference.releaseHistoryURL.absoluteString, "https://github.com/negentropi/roma-just-talk/releases")
        XCTAssertFalse(VoiceInkUpdateTrack.stable.feedURL.absoluteString.localizedCaseInsensitiveContains("VoiceInk"))
    }

    func testTrackPreferenceDefaultsStableAndPreservesExplicitPrereleaseChoice() {
        withTemporaryDefaults { defaults in
            XCTAssertEqual(VoiceInkUpdatePreference.track(from: defaults), .stable)

            VoiceInkUpdatePreference.saveTrack(.prerelease, to: defaults)
            XCTAssertEqual(VoiceInkUpdatePreference.track(from: defaults), .prerelease)

            defaults.set("future-channel", forKey: VoiceInkUpdatePreference.trackKey)
            XCTAssertEqual(VoiceInkUpdatePreference.track(from: defaults), .stable)
        }
    }

    func testAutomaticUpdatesDefaultOnAndPreserveExplicitOptOut() {
        withTemporaryDefaults { defaults in
            XCTAssertTrue(VoiceInkUpdatePreference.automaticUpdatesEnabled(from: defaults))

            VoiceInkUpdatePreference.saveAutomaticUpdatesEnabled(false, to: defaults)
            XCTAssertFalse(VoiceInkUpdatePreference.automaticUpdatesEnabled(from: defaults))

            VoiceInkUpdatePreference.saveAutomaticUpdatesEnabled(true, to: defaults)
            XCTAssertTrue(VoiceInkUpdatePreference.automaticUpdatesEnabled(from: defaults))
        }
    }

    func testAutomaticUpdatesMigrateLegacySparkleOptOut() {
        withTemporaryDefaults { defaults in
            defaults.set(false, forKey: "SUAutomaticallyUpdate")

            XCTAssertFalse(VoiceInkUpdatePreference.migrateAutomaticUpdatesEnabled(from: defaults))
            XCTAssertEqual(
                defaults.object(forKey: VoiceInkUpdatePreference.automaticUpdatesEnabledKey) as? Bool,
                false
            )

            defaults.set(true, forKey: "SUAutomaticallyUpdate")
            XCTAssertFalse(VoiceInkUpdatePreference.automaticUpdatesEnabled(from: defaults))
        }
    }

    func testOptOutBlocksBackgroundUpdateButStillAllowsManualCheck() {
        XCTAssertFalse(VoiceInkUpdatePolicy.shouldHandleFoundUpdate(
            automaticUpdatesEnabled: false,
            userInitiated: false
        ))
        XCTAssertTrue(VoiceInkUpdatePolicy.shouldHandleFoundUpdate(
            automaticUpdatesEnabled: false,
            userInitiated: true
        ))
        XCTAssertTrue(VoiceInkUpdatePolicy.shouldHandleFoundUpdate(
            automaticUpdatesEnabled: true,
            userInitiated: false
        ))
    }

    func testCompactStatusExposesOnlyRelevantActions() {
        let downloading = VoiceInkUpdateStatus(phase: .downloading, version: "0.0.1", progress: 1.7)
        XCTAssertEqual(downloading.title, "Downloading 0.0.1…")
        XCTAssertEqual(downloading.progress, 1)
        XCTAssertTrue(downloading.canCancel)
        XCTAssertFalse(downloading.canRelaunch)

        let ready = VoiceInkUpdateStatus(phase: .ready, version: "0.0.1")
        XCTAssertEqual(ready.title, "0.0.1 is ready")
        XCTAssertTrue(ready.canCancel)
        XCTAssertTrue(ready.canRelaunch)

        let failed = VoiceInkUpdateStatus(phase: .failed, detail: "Network unavailable")
        XCTAssertEqual(failed.title, "Update failed")
        XCTAssertEqual(failed.detail, "Network unavailable")
        XCTAssertFalse(failed.canCancel)
        XCTAssertFalse(failed.canRelaunch)
    }
}
