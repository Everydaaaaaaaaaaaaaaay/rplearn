import XCTest

@MainActor
final class LearningJourneyNavigationTests: XCTestCase {
    func testConfirmLevelReturnsToJourneyAndEdgeSwipeReturnsToMe() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["UI_TEST_TAB"] = "me"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
        app.launch()
        let entry = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "英语旅程，")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        entry.tap()
        let journey = app.navigationBars["英语旅程"]
        XCTAssertTrue(journey.waitForExistence(timeout: 10))
        let level = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "当前英语水平")).firstMatch
        XCTAssertTrue(level.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["登录后查看学习进度"].waitForExistence(timeout: 5),
                      "全局进度与主线应位于英语旅程，水平调整入口仍在原处")
        level.tap()
        let choice = app.buttons["placement.level.kindergarten"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.tap()
        app.buttons["完成"].tap()
        let confirmation = app.alerts["直接更改英语水平？"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["确认更改"].tap()
        XCTAssertTrue(journey.waitForExistence(timeout: 10), "确认后应返回英语旅程")
        XCTAssertTrue(level.waitForExistence(timeout: 5))
        XCTAssertTrue(level.label.contains("启蒙"), "应显示刚保存的水平")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "水平确认后返回英语旅程"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        XCTAssertTrue(journey.waitForNonExistence(timeout: 5), "左缘滑动应返回我的页")
        XCTAssertTrue(entry.isHittable)
    }
}
