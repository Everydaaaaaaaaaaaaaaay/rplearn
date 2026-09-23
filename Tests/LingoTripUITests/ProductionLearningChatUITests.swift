import XCTest

/// Opt-in only: real signed-in account, production transport, no seeded replies or timing overrides.
@MainActor
final class ProductionLearningChatUITests: XCTestCase {
    private func openRuby(_ app: XCUIApplication) throws {
        let optIn = Bundle(for: Self.self).object(forInfoDictionaryKey: "LingoTripLiveLearningUI")
        try XCTSkipUnless((optIn as? NSNumber)?.boolValue == true || optIn as? String == "YES", "Explicit live-device acceptance only")
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
    private func practiceTurns(_ instruction: String) -> [String]? {
        // Match authored replies to the task actually shown on this account.
        // Unknown tasks stop before sending an unrelated answer to real chat.
        guard instruction.contains("说出你的选择和一个理由") else { return nil }
        if instruction.contains("周末出游") {
            return ["Let me think for a moment.", "I would choose the park for a weekend trip.",
                    "It is quiet, and I can walk there with my friend on Saturday morning."]
        }
        if instruction.contains("准备晚餐") {
            return ["Let me think for a moment.", "I would cook dinner at home.",
                    "I choose that because I can make vegetable pasta and eat with my friend at seven tonight."]
        }
        return nil
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
        if !app.buttons["结束这次练习"].exists {
            let practice = app.buttons["chat.learning.practice"]
            XCTAssertTrue(practice.waitForExistence(timeout: 60))
            let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format:"enabled == true"), object: practice)
            XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 90), .completed)
            practice.tap()
        }
        XCTAssertTrue(app.buttons["结束这次练习"].waitForExistence(timeout: 10))
        let instructions = app.scrollViews["chat.learning.card"].staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "聊聊"))
        XCTAssertTrue(instructions.firstMatch.exists, app.debugDescription)
        let instruction = instructions.firstMatch.label
        guard let turns = practiceTurns(instruction) else {
            XCTFail("No authored real-chat reply for task: \(instruction)")
            return
        }
        capture("02-live-practice-in-normal-chat", app)
        let acknowledge = app.buttons["知道了"]
        XCTAssertTrue(acknowledge.exists)
        acknowledge.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(app.buttons["chat.learning.expand"].value as? String, "已收起")
        for turn in turns { send(turn, app) }
        dismissKeyboard(app)
        capture("03-live-three-message-burst", app)
        // Wait for an actual incoming bubble, not just elapsed time or send delivery.
        let noReplyError = app.staticTexts["暂时没有收到回复，请点重试。"]
        let latest = app.descendants(matching: .any)["chat.message.latest"].firstMatch
        let incoming = latest.images.matching(NSPredicate(format: "label CONTAINS %@", "Ruby")).firstMatch
        var gotReply = false
        for _ in 0..<36 {
            XCTAssertFalse(noReplyError.exists)
            if incoming.exists { gotReply = true; break }
            RunLoop.current.run(until: Date().addingTimeInterval(5))
        }
        XCTAssertTrue(gotReply, "No completed Ruby reply after three real messages")
        let practiceEnded = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.buttons["结束这次练习"])
        XCTAssertEqual(XCTWaiter.wait(for: [practiceEnded], timeout: 90), .completed,
                       "The learning review did not complete the selected practice")
        let resultTitle = app.buttons["chat.learning.expand"].label
        XCTAssertTrue(resultTitle.contains("新收获") || resultTitle.contains("本次回顾完成"), resultTitle)
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
        let original = composer.value as? String ?? ""
        let existingDraft = !original.isEmpty && original != "用英语说点什么…" && !original.hasSuffix("正在输入，你也可以继续说…")
        let testDraft = "I am still thinking, please wait"
        if !existingDraft { composer.tap(); composer.typeText(testDraft) }
        let expectedDraft = existingDraft ? original : testDraft
        dismissKeyboard(app)
        expand(app)
        capture("07-live-unsent-draft-with-learning", app)
        XCTAssertEqual(composer.value as? String, expectedDraft)
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
        XCTAssertEqual(composer.value as? String, expectedDraft)
        capture("09-live-return-preserves-draft", app)
        if !existingDraft {
            composer.tap()
            composer.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: testDraft.count))
            XCTAssertFalse((composer.value as? String)?.contains(testDraft) == true)
        }
    }

    func testLiveListeningFullPlaybackAndResume() throws {
        let app = XCUIApplication(); try openRuby(app)
        let composer = app.descendants(matching: .any)["chat.composer"].firstMatch
        let originalDraft = composer.value as? String ?? ""
        func openListening() {
            app.buttons["chat.learning.details"].tap()
            let entry = app.buttons["learningListening.start.1"]
            for _ in 0..<8 where !entry.isHittable { app.swipeUp() }
            XCTAssertTrue(entry.isHittable)
            entry.tap()
            XCTAssertTrue(app.buttons["learningListening.play"].waitForExistence(timeout: 10))
        }
        openListening()
        let plays = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "已完整播放[0-2]/2遍")).firstMatch
        XCTAssertTrue(plays.waitForExistence(timeout: 10))
        let initial = Int(String(plays.label.first(where: \.isNumber) ?? "0")) ?? 0
        if initial < 2 {
            app.buttons["learningListening.play"].tap()
            let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "已完整播放\(initial + 1)/2遍"), object: plays)
            XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 120), .completed,
                           "Project TTS did not finish a full playback")
        }
        let completed = max(1, initial + (initial < 2 ? 1 : 0))
        XCTAssertTrue(app.buttons["learningListening.option.0"].isEnabled)
        capture("10-live-listening-playback-unlocks-answer", app)
        app.buttons["稍后继续"].tap()
        app.buttons["完成"].firstMatch.tap()
        XCTAssertEqual(composer.value as? String ?? "", originalDraft)
        openListening()
        XCTAssertEqual(plays.label, "已完整播放\(completed)/2遍")
        XCTAssertTrue(app.buttons["learningListening.option.0"].isEnabled)
        capture("11-live-listening-resumed-with-play-count", app)
        app.buttons["稍后继续"].tap()
        app.buttons["完成"].firstMatch.tap()
    }
}
