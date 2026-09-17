import XCTest

@MainActor
final class ReviewPilotTests: XCTestCase {
    func testRecallHidesAnswerAndUndoPreservesExposure() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = [
            "UI_TEST_SKIP_ONBOARDING": "1",
            "UI_TEST_REQUIRE_AUTHENTICATION": "0",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
            "UI_TEST_TAB": "review",
            "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9",
        ]
        app.launch()
        let choose = app.buttons["review.choose.cosy.0"]
        XCTAssertTrue(choose.waitForExistence(timeout: 20))
        choose.tap()
        let start = app.buttons["review.start"]
        if !start.isHittable { app.swipeUp() }
        XCTAssertTrue(start.isHittable)
        start.tap()
        let reveal = app.buttons["看看释义"]
        if !reveal.isHittable { app.swipeDown() }
        XCTAssertTrue(reveal.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["温暖舒适的"].exists, "回忆前不能露出答案")
        app.buttons["当时的原句"].tap()
        XCTAssertFalse(app.staticTexts["一家温暖舒适的咖啡馆，一本好书，而且绝对不要闹钟。"].exists)
        capture("review-before-reveal", app)
        reveal.tap()
        XCTAssertTrue(app.staticTexts["温暖舒适的"].exists)
        let forgot = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "忘记")).firstMatch
        if !forgot.isHittable { app.swipeUp() }
        forgot.tap()
        XCTAssertTrue(app.staticTexts["回顾了 1 个词"].waitForExistence(timeout: 5))
        app.buttons["撤销上一词"].tap()
        XCTAssertTrue(app.staticTexts["刚才已看过答案，可以修改自评。"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["温暖舒适的"].exists)
        capture("review-correct-rating", app)
        let remembered = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "记得")).firstMatch
        if !remembered.isHittable { app.swipeUp() }
        remembered.tap()
        XCTAssertTrue(app.staticTexts["回顾了 1 个词"].waitForExistence(timeout: 5))
        capture("review-summary", app)
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
