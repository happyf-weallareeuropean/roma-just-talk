import AppKit
import XCTest

final class UpdaterE2ETests: XCTestCase {
    private let bundleIdentifier = "com.negentropi.RomaJustTalk"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSeamlessBackgroundUpdateInstallsAndRelaunches() throws {
        let environment = ProcessInfo.processInfo.environment
        let feedURL = try XCTUnwrap(
            environment["ROMA_UPDATE_FEED_URL"],
            "The updater E2E scheme did not provide ROMA_UPDATE_FEED_URL."
        )
        let expectedBuild = try XCTUnwrap(
            environment["ROMA_UPDATE_EXPECTED_BUILD"],
            "The updater E2E scheme did not provide ROMA_UPDATE_EXPECTED_BUILD."
        )
        let expectedVersion = try XCTUnwrap(
            environment["ROMA_UPDATE_EXPECTED_VERSION"],
            "The updater E2E scheme did not provide ROMA_UPDATE_EXPECTED_VERSION."
        )
        let installedAppPath = try XCTUnwrap(
            environment["ROMA_UPDATE_INSTALL_APP_PATH"],
            "The updater E2E scheme did not provide ROMA_UPDATE_INSTALL_APP_PATH."
        )
        let expectedBundleURL = normalizedBundleURL(URL(fileURLWithPath: installedAppPath))

        XCTAssertEqual(buildVersion(at: installedAppPath), "1")

        let app = XCUIApplication()
        app.launchEnvironment["ROMA_UPDATE_FEED_URL"] = feedURL
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        let mainWindow = app.windows.firstMatch
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 20))

        let downloadingTitle = mainWindow.staticTexts["Downloading \(expectedVersion)…"]
        XCTAssertTrue(
            downloadingTitle.waitForExistence(timeout: 45),
            "The background check never exposed embedded download progress."
        )
        assertNoUpdaterPopup(in: app)
        attachScreenshot(of: app, named: "Embedded update download")

        let status = mainWindow.descendants(matching: .any)["update-status"]
        let relaunch = mainWindow.buttons["update-relaunch"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(
            relaunch.waitForExistence(timeout: 180),
            "The downloaded update never reached the embedded relaunch state."
        )
        XCTAssertTrue(mainWindow.staticTexts["\(expectedVersion) is ready"].exists)
        assertNoUpdaterPopup(in: app)
        attachScreenshot(of: app, named: "Embedded update ready")

        let originalApplication = try XCTUnwrap(runningApplications().first(where: {
            guard let bundleURL = $0.bundleURL else { return false }
            return normalizedBundleURL(bundleURL) == expectedBundleURL
        }))
        let originalPID = originalApplication.processIdentifier
        relaunch.click()

        XCTAssertTrue(
            waitUntil(timeout: 90) { self.buildVersion(at: installedAppPath) == expectedBuild },
            "Sparkle did not replace the launched bundle with build \(expectedBuild)."
        )
        XCTAssertTrue(
            waitUntil(timeout: 60) {
                NSRunningApplication(processIdentifier: originalPID) == nil
            },
            "The original Roma process did not terminate."
        )

        var relaunchedPID: pid_t?
        XCTAssertTrue(
            waitUntil(timeout: 60) {
                guard let relaunchedApplication = self.runningApplications().first(where: {
                    guard $0.processIdentifier != originalPID, let bundleURL = $0.bundleURL else {
                        return false
                    }
                    return self.normalizedBundleURL(bundleURL) == expectedBundleURL
                }) else {
                    return false
                }
                relaunchedPID = relaunchedApplication.processIdentifier
                return true
            },
            "Roma did not relaunch from the exact updated test-app path."
        )
        XCTAssertNotEqual(try XCTUnwrap(relaunchedPID), originalPID)

        let relaunchedApp = XCUIApplication()
        XCTAssertTrue(relaunchedApp.wait(for: .runningForeground, timeout: 30))
        XCTAssertEqual(buildVersion(at: installedAppPath), expectedBuild)
        attachScreenshot(of: relaunchedApp, named: "Updated app relaunched")
    }

    @MainActor
    private func assertNoUpdaterPopup(in app: XCUIApplication) {
        XCTAssertEqual(app.windows.count, 1, "The update must stay inside the existing app window.")
        XCTAssertEqual(app.sheets.count, 0, "The update must not present a sheet.")
        XCTAssertEqual(app.alerts.count, 0, "The update must not present an alert.")
        XCTAssertFalse(app.windows["Software Update"].exists)
    }

    @MainActor
    private func runningApplications() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
    }

    private func buildVersion(at appPath: String) -> String? {
        let infoURL = URL(fileURLWithPath: appPath)
            .appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let info = plist as? [String: Any] else {
            return nil
        }
        return info["CFBundleVersion"] as? String
    }

    private func normalizedBundleURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    @MainActor
    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return condition()
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
