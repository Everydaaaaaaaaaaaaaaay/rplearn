import XCTest

@MainActor
final class LearningPromotionTests: XCTestCase {
    func testPromotionResumesStoryAndRequiresExplicitConfirmation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["UI_TEST_TAB"] = "learning"
        app.launchEnvironment["UI_TEST_LEARNING_PROMOTION"] = "1"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
        app.launch()
        let begin = app.buttons["learning.promotion.begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 15))
        if !begin.isHittable { app.swipeUp() }
        begin.tap()
        let next = app.buttons["learning.promotion.continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        next.tap()
        XCTAssertTrue(app.staticTexts["Take your time. We can read it together."].waitForExistence(timeout: 5))
        app.navigationBars["水平进阶"].buttons.firstMatch.tap()
        XCTAssertTrue(begin.waitForExistence(timeout: 5))
        begin.tap()
        XCTAssertTrue(app.staticTexts["Take your time. We can read it together."].waitForExistence(timeout: 5))
        next.tap()
        let confirm = app.buttons["learning.promotion.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        app.buttons["继续保留当前水平"].tap()
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()
        app.buttons["确认进入下一水平"].tap()
        let back = app.buttons["返回英语旅程"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "进阶完成确认"; evidence.lifetime = .keepAlways; add(evidence)
        back.tap()
        XCTAssertTrue(app.staticTexts["小学四年级"].waitForExistence(timeout: 5))
        XCTAssertFalse(begin.exists)
    }
}
