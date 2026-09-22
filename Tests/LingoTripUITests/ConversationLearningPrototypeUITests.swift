import XCTest

@MainActor
final class ConversationLearningPrototypeUITests: XCTestCase {
    private func launch(namespace: String, largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
            "UI_TEST_WELCOME_CAPTURE": "1", "UI_TEST_NATIVE_CAPTURE": "learningLab", "UI_TEST_TAB": "contacts",
            "UI_TEST_LEARNING_NAMESPACE": namespace, "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9"]
        if largeText {
            app.launchEnvironment["UI_TEST_CAPTURE_APPEARANCE"] = "dark"
            app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
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
        app.swipeUp()
        let restoredNetwork = app.switches["模拟断网"]
        XCTAssertTrue(restoredNetwork.waitForExistence(timeout: 5))
        restoredNetwork.tap()
        app.swipeDown()
        app.buttons["learning.review"].tap()
        XCTAssertTrue(app.staticTexts["learning.reward"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["learning.xp"].label, "10 XP")
        XCTAssertFalse(app.staticTexts["learning.error"].exists)
    }
    func testDeleteEvidenceSurvivesRelaunchAndPreservesReward() {
        let namespace = "ui-\(UUID().uuidString)"
        var app = launch(namespace: namespace)
        send(app)
        app.buttons["learning.review"].tap()
        XCTAssertTrue(app.staticTexts["learning.reward"].waitForExistence(timeout: 5))
        app.swipeUp()
        app.buttons["删除这次学习原文"].tap()
        app.buttons["删除原文"].tap()
        XCTAssertTrue(app.staticTexts["原文已清除，相关能力证据不再使用。"].waitForExistence(timeout: 10))
        app.terminate(); app = launch(namespace: namespace)
        XCTAssertEqual(app.staticTexts["learning.xp"].label, "10 XP")
        send(app)
        app.buttons["learning.review"].tap()
        XCTAssertEqual(app.staticTexts["learning.xp"].label, "10 XP")
    }
    func testFreeChatHasNoAssessmentAndCanEnd() {
        let app = launch(namespace: "ui-\(UUID().uuidString)")
        app.buttons["先随意聊聊，不设目标"].tap()
        XCTAssertTrue(app.buttons["learning.return"].waitForExistence(timeout: 15))
        app.buttons["learning.return"].tap()
        XCTAssertTrue(app.buttons["结束这次练习，不作评价"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["learning.review"].exists)
        app.buttons["结束这次练习，不作评价"].tap()
        XCTAssertTrue(app.buttons["先随意聊聊，不设目标"].exists)
        XCTAssertEqual(app.staticTexts["learning.xp"].label, "0 XP")
    }
    func testLargeTextDarkModeKeepsPracticeReachable() {
        let app = launch(namespace: "ui-\(UUID().uuidString)", largeText: true)
        capture("learning-large-dark-dashboard", app)
        let start = app.buttons["learning.start"]
        for _ in 0..<5 where !start.isHittable { app.swipeUp() }
        XCTAssertTrue(start.isHittable)
        start.tap()
        let back = app.buttons["learning.return"]
        XCTAssertTrue(back.waitForExistence(timeout: 15))
        XCTAssertTrue(back.isHittable)
        capture("learning-large-dark-chat", app)
        back.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 10))
    }
    private func capture(_ name: String, _ app: XCUIApplication) {
        let item = XCTAttachment(screenshot: app.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
}
