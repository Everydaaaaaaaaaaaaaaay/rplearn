import XCTest

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
            let back = app.buttons["返回"]
            XCTAssertTrue(back.waitForExistence(timeout: 3))
            back.tap()
            XCTAssertTrue(favoritesEntry.waitForExistence(timeout: 3))
        }
    }

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
            let back = app.buttons["返回"]
            XCTAssertTrue(back.waitForExistence(timeout: 3))
            back.tap()
            XCTAssertTrue(settingsEntry.waitForExistence(timeout: 3))
        }
    }

    private func launch(on tab: String) {
        app.launchEnvironment["UI_TEST_TAB"] = tab
        app.launch()
    }
}
