import XCTest

@MainActor
final class ConversationLearningPrototypeUITests: XCTestCase {
    private func launch(namespace: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
            "UI_TEST_WELCOME_CAPTURE": "1", "UI_TEST_NATIVE_CAPTURE": "learningLab", "UI_TEST_TAB": "contacts",
            "UI_TEST_LEARNING_NAMESPACE": namespace, "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9"]
        app.launch()
        XCTAssertTrue(app.buttons["learning.start"].waitForExistence(timeout: 30))
        return app
    }
    private func send(_ app: XCUIApplication) {
        app.buttons["learning.start"].tap()
        let field = app.descendants(matching: .any)["chat.composer"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap(); field.typeText("I prefer the beach because it is quiet.")
        app.buttons["发送消息"].tap()
        XCTAssertTrue(app.buttons["learning.return"].exists)
        app.buttons["learning.return"].tap()
        XCTAssertTrue(app.buttons["learning.review"].waitForExistence(timeout: 10))
    }
    func testRealComposerResumeReviewAndDeduplicate() {
        let namespace = "ui-\(UUID().uuidString)"
        var app = launch(namespace: namespace)
        send(app)
        // Relaunch before evaluation: both the turn and pending attempt must survive.
        app.terminate(); app = launch(namespace: namespace)
        XCTAssertTrue(app.buttons["learning.review"].exists)
        app.buttons["learning.review"].tap()
        XCTAssertTrue(app.staticTexts["learning.reward"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["learning.xp"].label, "10 XP")
        capture("learning-complete", app)
        send(app)
        app.buttons["learning.review"].tap()
        XCTAssertEqual(app.staticTexts["learning.xp"].label, "10 XP")
        capture("learning-deduplicated", app)
    }
    func testOfflineReviewPreservesAttempt() {
        let app = launch(namespace: "ui-\(UUID().uuidString)")
        send(app)
        app.swipeUp()
        app.buttons["测试条件与边界"].tap()
        let offline = app.switches["模拟断网"]
        XCTAssertTrue(offline.waitForExistence(timeout: 5)); offline.tap()
        app.swipeDown()
        app.buttons["learning.review"].tap()
        XCTAssertTrue(app.staticTexts["learning.error"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["learning.xp"].label, "0 XP")
    }
    private func capture(_ name: String, _ app: XCUIApplication) {
        let item = XCTAttachment(screenshot: app.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
}
