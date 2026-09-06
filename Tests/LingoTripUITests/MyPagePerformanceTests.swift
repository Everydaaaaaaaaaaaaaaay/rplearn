import XCTest

@MainActor
final class MyPagePerformanceTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
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
            let currentFavoritesEntry = app.buttons["收藏夹，单词与语法点"]
            XCTAssertTrue(currentFavoritesEntry.waitForExistence(timeout: 3))
            currentFavoritesEntry.tap()
            let back = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 3))
            back.tap()
            XCTAssertTrue(app.buttons["收藏夹，单词与语法点"].waitForExistence(timeout: 3))
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
            let currentSettingsEntry = app.buttons["设置，AI、语音与偏好"]
            XCTAssertTrue(currentSettingsEntry.waitForExistence(timeout: 3))
            currentSettingsEntry.tap()
            let back = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 3))
            back.tap()
            XCTAssertTrue(app.buttons["设置，AI、语音与偏好"].waitForExistence(timeout: 3))
        }
    }

    @MainActor
    func testQuickTapKeepsSceneFeedbackVisibleBeforeNavigation() throws {
        launch(on: "me")

        let favoritesEntry = app.buttons["收藏夹，单词与语法点"]
        XCTAssertTrue(favoritesEntry.waitForExistence(timeout: 5))

        let start = ContinuousClock.now
        favoritesEntry.tap()
        let favoritesNavigationBar = app.navigationBars["收藏夹"]
        XCTAssertTrue(favoritesNavigationBar.waitForExistence(timeout: 2))
        let elapsed = ContinuousClock.now - start

        XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(100))
        // XCUITest 轮询导航栏出现会引入额外的观测延迟；产品内部时序为 0.02 + 0.08 + 0.02 秒。
        XCTAssertLessThan(elapsed, .seconds(1.8))
    }

    @MainActor
    func testFavoritesSupportsLeadingEdgeSwipeBack() throws {
        launch(on: "me")

        let favoritesEntry = app.buttons["收藏夹，单词与语法点"]
        XCTAssertTrue(favoritesEntry.waitForExistence(timeout: 5))
        favoritesEntry.tap()
        XCTAssertTrue(app.navigationBars["收藏夹"].waitForExistence(timeout: 2))

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)

        XCTAssertTrue(favoritesEntry.waitForExistence(timeout: 2))
        XCTAssertFalse(app.navigationBars["收藏夹"].exists)
    }

    @MainActor
    func testSettingsSupportsLeadingEdgeSwipeBack() throws {
        launch(on: "me")

        let settingsEntry = app.buttons["设置，AI、语音与偏好"]
        XCTAssertTrue(settingsEntry.waitForExistence(timeout: 5))
        settingsEntry.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 2))

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)

        XCTAssertTrue(settingsEntry.waitForExistence(timeout: 2))
        XCTAssertFalse(app.navigationBars["设置"].exists)
    }

    @MainActor
    func testLegacyTabBarUsesNativeFullWidthAppearance() throws {
        app.launchEnvironment["UI_TEST_FORCE_LEGACY_CHROME"] = "1"
        launch(on: "me")

        let capsule = app.descendants(matching: .any)["LegacyTabBarCapsule"]
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        XCTAssertFalse(capsule.exists)
        XCTAssertEqual(tabBar.frame.minX, app.frame.minX, accuracy: 1)
        XCTAssertEqual(tabBar.frame.maxX, app.frame.maxX, accuracy: 1)
        XCTAssertEqual(tabBar.frame.maxY, app.frame.maxY, accuracy: 1)
        XCTAssertGreaterThanOrEqual(tabBar.frame.height, 49)

        let labels = ["信息", "联系人", "首页", "我的", "测试"]
        for label in labels {
            let item = tabBar.buttons[label]
            XCTAssertTrue(item.exists)
            XCTAssertTrue(tabBar.frame.contains(CGPoint(x: item.frame.midX, y: item.frame.midY)))
        }
    }

    @MainActor
    private func launch(on tab: String) {
        app.launchEnvironment["UI_TEST_TAB"] = tab
        app.launch()
    }
}
