import XCTest

/// Opt-in only: real signed-in account, production transport, no seeded replies or timing overrides.
@MainActor
final class ProductionLearningChatUITests: XCTestCase {
    private func openRuby(_ app: XCUIApplication) throws {
        try XCTSkipUnless(Bundle.main.object(forInfoDictionaryKey: "LingoTripLiveLearningUI") as? String == "YES", "Explicit live-device acceptance only")
        continueAfterFailure = false
        app.launch()
        let messages = app.tabBars.buttons["信息"]
        if messages.waitForExistence(timeout: 30) { messages.tap() }
        let ruby = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Ruby")).firstMatch
        if ruby.waitForExistence(timeout: 10) { ruby.tap() }
        XCTAssertTrue(app.buttons["chat.learning.expand"].waitForExistence(timeout: 20), app.debugDescription)
    }
    private func capture(_ name: String, _ app: XCUIApplication) {
        let item = XCTAttachment(screenshot: app.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
    private func expand(_ app: XCUIApplication) {
        let header = app.buttons["chat.learning.expand"]
        if header.value as? String != "已展开" { header.tap() }
    }
    private func reveal(_ label: String, _ app: XCUIApplication) {
        let button = app.buttons[label]
        let card = app.scrollViews["chat.learning.card"]
        for _ in 0..<8 where !button.isHittable { card.swipeUp() }
        XCTAssertTrue(button.isHittable, app.debugDescription)
    }
    private func send(_ text: String, _ app: XCUIApplication) {
        let composer = app.descendants(matching: .any)["chat.composer"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 10)); composer.tap(); composer.typeText(text)
        app.buttons["发送消息"].tap()
    }
    private func dismissKeyboard(_ app: XCUIApplication) {
        let button = app.buttons["chat.dismissKeyboard"]
        if button.exists && button.isHittable { button.tap() }
    }
    func testOfflineInlineConsentTaskDraftAndDetails() {
        runInlineFlow(largeDark: false)
    }
    func testOfflineLargeTextDarkInlineFlow() {
        runInlineFlow(largeDark: true)
    }
    private func runInlineFlow(largeDark: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
            "UI_TEST_MARKETING_CAPTURE": "1", "UI_TEST_NATIVE_CAPTURE": "chat",
            "UI_TEST_LEARNING_CHAT_PREVIEW": "1", "UI_TEST_LEARNING_V1_OWNER": UUID().uuidString,
            "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9"]
        if largeDark {
            app.launchEnvironment["UI_TEST_CAPTURE_APPEARANCE"] = "dark"
            app.launchArguments += ["-AppleInterfaceStyle", "Dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        let ruby = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Ruby")).firstMatch
        XCTAssertTrue(ruby.waitForExistence(timeout: 20)); ruby.tap()
        XCTAssertTrue(app.buttons["chat.learning.expand"].waitForExistence(timeout: 10))
        capture("simulator-01-consent-compact", app)
        expand(app)
        capture("simulator-02-before-consent-scroll", app)
        reveal("chat.learning.enable", app)
        capture("simulator-02-consent", app)
        app.buttons["chat.learning.enable"].tap()
        expand(app)
        reveal("chat.learning.practice", app)
        app.buttons["chat.learning.practice"].tap()
        XCTAssertTrue(app.buttons["结束这次练习"].waitForExistence(timeout: 5))
        capture("simulator-03-task-inline", app)
        reveal("知道了", app)
        app.buttons["知道了"].tap()
        let field = app.descendants(matching: .any)["chat.composer"].firstMatch
        field.tap(); field.typeText("I would like to think about it")
        XCTAssertEqual(app.buttons["chat.learning.expand"].value as? String, "已收起")
        dismissKeyboard(app)
        app.buttons["chat.learning.details"].tap()
        XCTAssertTrue(app.navigationBars["共同篇章"].waitForExistence(timeout: 5))
        app.buttons["完成"].firstMatch.tap()
        XCTAssertTrue((field.value as? String)?.contains("I would like to think") == true)
        expand(app)
        reveal("结束这次练习", app)
        app.buttons["结束这次练习"].tap()
        expand(app)
        reveal("今天先不练", app)
        app.buttons["今天先不练"].tap()
        XCTAssertEqual(app.buttons["chat.learning.expand"].value as? String, "已收起")
        capture("simulator-04-deferred-draft-kept", app)
    }

    func testLiveInlineLearningAndBurstRecovery() throws {
        let app = XCUIApplication(); try openRuby(app)
        let draft = app.descendants(matching: .any)["chat.composer"].firstMatch.value as? String ?? ""
        try XCTSkipUnless(draft.isEmpty || draft == "用英语说点什么…" || draft.hasSuffix("正在输入，你也可以继续说…"), "Existing user draft preserved; do not send it as test input")
        expand(app)
        let enable = app.buttons["chat.learning.enable"]
        if enable.exists { enable.tap(); expand(app) }
        capture("01-live-inline-learning", app)
        let end = app.buttons["结束这次练习"]
        if end.exists { end.tap(); expand(app) }
        let practice = app.buttons["chat.learning.practice"]
        XCTAssertTrue(practice.waitForExistence(timeout: 60))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format:"enabled == true"), object: practice)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 90), .completed)
        practice.tap()
        XCTAssertTrue(app.buttons["结束这次练习"].waitForExistence(timeout: 10))
        capture("02-live-practice-in-normal-chat", app)
        reveal("知道了", app)
        app.buttons["知道了"].tap()
        send("Let me think for a moment.", app)
        send("I would choose the park for a weekend trip.", app)
        send("It is quiet, and I can walk there with my friend on Saturday morning.", app)
        dismissKeyboard(app)
        capture("03-live-three-message-burst", app)
        // Allow actual provider + normal NPC pace; do not inject fast responses.
        let noReplyError = app.staticTexts["暂时没有收到回复，请点重试。"]
        for _ in 0..<12 {
            XCTAssertFalse(noReplyError.exists)
            RunLoop.current.run(until: Date().addingTimeInterval(5))
        }
        capture("04-live-reply-and-learning-feedback", app)
        expand(app)
        capture("05-live-feedback-expanded", app)
        // Detailed evidence is optional and reachable directly from chat, not the contact page.
        app.buttons["chat.learning.details"].tap()
        XCTAssertTrue(app.navigationBars["共同篇章"].waitForExistence(timeout: 10))
        capture("06-live-records", app)
        app.buttons["完成"].firstMatch.tap()
        XCTAssertTrue(app.buttons["chat.learning.expand"].waitForExistence(timeout: 5))
    }

    func testLiveDraftPreservationAndListeningExit() throws {
        let app = XCUIApplication(); try openRuby(app)
        let composer = app.descendants(matching: .any)["chat.composer"].firstMatch
        composer.tap(); composer.typeText("I am still thinking, please wait")
        dismissKeyboard(app)
        expand(app)
        capture("07-live-unsent-draft-with-learning", app)
        XCTAssertTrue((composer.value as? String)?.contains("I am still thinking") == true)
        app.buttons["chat.learning.details"].tap()
        let listening = app.buttons["learningListening.start.1"]
        for _ in 0..<8 where !listening.isHittable { app.swipeUp() }
        XCTAssertTrue(listening.isHittable); listening.tap()
        let play = app.buttons["learningListening.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["learningListening.option.0"].isEnabled)
        play.tap()
        capture("08-live-listening-real-tts", app)
        app.buttons["稍后继续"].tap()
        app.buttons["完成"].firstMatch.tap()
        XCTAssertTrue((composer.value as? String)?.contains("I am still thinking") == true)
        capture("09-live-return-preserves-draft", app)
    }
}
