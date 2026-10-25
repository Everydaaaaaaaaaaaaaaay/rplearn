import XCTest

@MainActor
final class CharacterLearningLayoutTests: XCTestCase {
    func testPendingFilterAndJourneyEntry() {
        let app = launch(state: "active")
        let ongoing = app.buttons["learning.history.20000000-0000-4000-8000-000000000001"]
        let retry = app.buttons["learning.history.20000000-0000-4000-8000-000000000002"]
        let complete = app.buttons["learning.history.20000000-0000-4000-8000-000000000003"]
        XCTAssertTrue(ongoing.waitForExistence(timeout: 10))
        XCTAssertTrue(ongoing.label.contains("获得 2 积分"))
        XCTAssertTrue(retry.label.contains("获得 3 积分"))
        XCTAssertTrue(complete.label.contains("获得 0 积分"))
        XCTAssertTrue(app.buttons["learning.start"].label.contains("继续挑战"))
        app.buttons["learning.history.filter"].tap()
        XCTAssertTrue(retry.exists)
        XCTAssertFalse(ongoing.exists)
        XCTAssertFalse(complete.exists)
        capture(app, name: "待补答筛选")
        app.buttons["learning.history.filter"].tap()
        XCTAssertTrue(complete.exists)
        app.buttons["learning.journey"].tap()
        XCTAssertTrue(app.navigationBars["学习进度"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["0/60 点"].exists)
        app.buttons["关闭学习进度"].tap()
        XCTAssertTrue(app.buttons["learning.journey"].waitForExistence(timeout: 5))
    }

    func testLargeTextDarkHistoryRemainsReadable() {
        let app = launch(state: "ready", large: true)
        let start = app.buttons["learning.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertTrue(start.label.contains("开始挑战"))
        capture(app, name: "最大字号深色挑战进度")
        let row = app.buttons["learning.history.20000000-0000-4000-8000-000000000002"]
        for _ in 0..<8 {
            if row.isHittable && row.frame.maxY < app.frame.maxY - 40 { break }
            app.swipeUp()
        }
        XCTAssertTrue(row.isHittable)
        XCTAssertTrue(row.label.contains("周末集市：询价、比较与表达偏好"))
        XCTAssertTrue(row.label.contains("补答 2 题"))
        XCTAssertTrue(row.label.contains("获得 3 积分"))
        XCTAssertLessThanOrEqual(row.frame.maxX, app.frame.maxX)
        capture(app, name: "最大字号深色长标题与补答")
    }

    private func launch(state: String, large: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
            "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9", "UI_TEST_TAB": "role-learning",
            "UI_TEST_LEARNING_PAGE_STATE": state]
        if large {
            app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            app.launchEnvironment["UI_TEST_CAPTURE_APPEARANCE"] = "dark"
        }
        app.launch()
        addTeardownBlock { app.terminate() }
        return app
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
