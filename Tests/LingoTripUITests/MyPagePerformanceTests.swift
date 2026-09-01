import XCTest

@MainActor
final class MyPagePerformanceTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    @MainActor
    func testMyPageTabRoundTripPerformance() throws {
        launch(on: "messages")

        let messagesTab = app.tabBars.buttons["信息"]
        let meTab = app.tabBars.buttons["我的"]
        let settingsEntry = app.buttons["设置，AI、语音与偏好"]
        XCTAssertTrue(messagesTab.waitForExistence(timeout: 5))
        XCTAssertTrue(meTab.exists)

        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()],
            options: options
        ) {
            meTab.tap()
            XCTAssertTrue(settingsEntry.waitForExistence(timeout: 3))
            messagesTab.tap()
            XCTAssertTrue(messagesTab.waitForExistence(timeout: 3))
        }
    }

    @MainActor
    func testFavoritesRoundTripPerformance() throws {
        launch(on: "me")

        let favoritesEntry = app.buttons["收藏夹，单词与语法点"]
        XCTAssertTrue(favoritesEntry.waitForExistence(timeout: 5))

        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()],
            options: options
        ) {
            favoritesEntry.tap()
            let back = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 3))
            back.tap()
            XCTAssertTrue(favoritesEntry.waitForExistence(timeout: 3))
        }
    }

    @MainActor
    func testSettingsRoundTripPerformance() throws {
        launch(on: "me")

        let settingsEntry = app.buttons["设置，AI、语音与偏好"]
        XCTAssertTrue(settingsEntry.waitForExistence(timeout: 5))

        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()],
            options: options
        ) {
            settingsEntry.tap()
            let back = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 3))
            back.tap()
            XCTAssertTrue(settingsEntry.waitForExistence(timeout: 3))
        }
    }

    @MainActor
    func testLegacyTabBarCapsuleIsInstalled() throws {
        app.launchEnvironment["UI_TEST_FORCE_LEGACY_CHROME"] = "1"
        launch(on: "me")

        let capsule = app.descendants(matching: .any)["LegacyTabBarCapsule"]
        XCTAssertTrue(capsule.waitForExistence(timeout: 5))
        let tabBar = app.tabBars.firstMatch
        let meTab = tabBar.buttons["我的"]
        XCTAssertTrue(meTab.exists)

        let capsuleFrame = capsule.frame
        XCTAssertGreaterThanOrEqual(capsuleFrame.height, 44)
        XCTAssertLessThanOrEqual(capsuleFrame.height, 64)
        XCTAssertLessThan(capsuleFrame.maxY, app.frame.maxY - 12)
        XCTAssertTrue(
            capsuleFrame.contains(
                CGPoint(x: meTab.frame.midX, y: meTab.frame.midY)
            )
        )
    }

    @MainActor
    private func launch(on tab: String) {
        app.launchEnvironment["UI_TEST_TAB"] = tab
        app.launch()
    }
}
