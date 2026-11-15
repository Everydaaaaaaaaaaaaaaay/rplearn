import XCTest

/// The local fixture supplies the transport only. These exercise the production
/// appointment model, durable command handling, navigation, and native views.
@MainActor
final class AppointmentUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment = [
            "UI_TEST_SKIP_ONBOARDING": "1",
            "UI_TEST_REQUIRE_AUTHENTICATION": "0",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
            "UI_TEST_TAB": "appointments-preview",
            "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9",
        ]
    }

    override func tearDown() async throws { app.terminate() }

    func testConfirmedCustomBilingualPathPauseFinishAndReadOnlySummary() throws {
        launch("list")
        let card = app.buttons["appointment.card.a0000000-0000-4000-8000-000000000001"]
        reveal(card)
        capture("appointment-00-list")
        card.tap()
        XCTAssertTrue(app.navigationBars["约定"].waitForExistence(timeout: 5))
        app.buttons["appointment.details.options"].tap()
        app.buttons["照片来源"].tap()
        XCTAssertTrue(app.navigationBars["照片来源"].waitForExistence(timeout: 5))
        capture("appointment-photo-credits")
        app.buttons["完成"].tap()
        let start = app.buttons["appointment.start"]
        reveal(start)
        XCTAssertEqual(app.staticTexts["appointment.beijingTime"].label, "北京时间，Sun, 1 Nov 2026 · 23:00")
        XCTAssertEqual(app.staticTexts["appointment.localTime"].label, "伦敦 15:00")
        XCTAssertFalse(app.staticTexts["设备时间"].exists)
        XCTAssertTrue(start.isEnabled)
        XCTAssertGreaterThanOrEqual(start.frame.height, 44)
        capture("appointment-01-confirmed-local-time")
        start.tap()
        advanceToDecision()
        capture("appointment-02-original-paper-reader")

        let input = "Could we sit by the water? 我想安静坐一会。"
        submitCustom(input)
        XCTAssertTrue(app.buttons["appointment.next"].waitForExistence(timeout: 8))
        openHistoryAndAssert(input, attachment: "appointment-04-actual-bilingual-history")

        // Ordinary back pauses; resuming reads the same accepted block.
        app.buttons["暂停并返回约定"].tap()
        let resume = app.buttons["appointment.resume"]
        reveal(resume)
        capture("appointment-05-paused-resume")
        resume.tap()
        XCTAssertTrue(app.buttons["appointment.next"].waitForExistence(timeout: 5))
        openHistoryAndAssert(input, attachment: nil)
        advanceToDecision()
        finishNaturally()

        let affinity = app.staticTexts["appointment.affinity"]
        reveal(affinity)
        let actualAffinity = affinity.label
        XCTAssertEqual(actualAffinity, "好感 +1")
        capture("appointment-06-independent-summary")
        let acceptedInput = app.staticTexts.matching(NSPredicate(format: "label == %@", input))
        reveal(acceptedInput.firstMatch)
        XCTAssertEqual(acceptedInput.count, 1)
        let returnToChat = app.buttons["appointment.backToChat"]
        XCTAssertTrue(returnToChat.isHittable)

        // Reopening exposes saved results and no editable choice/finish action.
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.isHittable)
        back.tap()
        let showSummary = app.buttons["appointment.summary"]
        XCTAssertTrue(showSummary.waitForExistence(timeout: 5))
        XCTAssertFalse(actionInput.exists)
        app.buttons["阅读选项"].tap()
        XCTAssertFalse(app.buttons["今天就到这里"].exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.45)).tap()
        showSummary.tap()
        reveal(affinity)
        XCTAssertEqual(affinity.label, actualAffinity)
        reveal(acceptedInput.firstMatch)
        XCTAssertEqual(acceptedInput.count, 1, "只显示一次实际选择，回看不能新增另一条经历")
        capture("appointment-07-reopened-summary-read-only")
    }

    func testFailedContinuationRetriesOriginalInputAndRecordsItOnce() {
        launch("retry")
        reveal(app.buttons["appointment.resume"])
        app.buttons["appointment.resume"].tap()
        advanceToDecision()
        let input = "Could we choose the quieter path? 换条安静的小路吧。"
        submitCustom(input)
        let retry = app.buttons["appointment.retry"]
        reveal(retry)
        XCTAssertTrue(app.staticTexts["这一段暂时没接上。你的回应已经保留，可以重试或稍后继续。"].exists)
        XCTAssertFalse(app.buttons["appointment.choice.walk"].isEnabled)
        capture("appointment-retry-original-input-retained")
        retry.tap()
        XCTAssertTrue(app.buttons["appointment.next"].waitForExistence(timeout: 8))
        openHistoryAndAssert(input, attachment: "appointment-retry-one-accepted-choice")
    }

    func testMaximumAccessibilityTextKeepsChoicesKeyboardAndSummaryReachable() {
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        launch("active")
        let resume = app.buttons["appointment.resume"]
        reveal(resume)
        resume.tap()
        XCTAssertTrue(app.buttons["appointment.next"].waitForExistence(timeout: 8))
        assertInsideScreen(app.buttons["appointment.next"])
        advanceToDecision()
        reveal(app.buttons["appointment.choice.quiet"])
        assertInsideScreen(app.buttons["appointment.choice.quiet"])
        capture("appointment-max-text-choice-scroll")

        let editor = actionInput
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        reveal(editor)
        XCTAssertFalse(app.buttons["appointment.sendInput"].isEnabled)
        XCTAssertFalse(app.navigationBars["自己说一句"].exists)
        editor.tap()
        editor.typeText("Let's take our time. 慢慢来。")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        capture("appointment-max-text-native-keyboard")
        let send = app.buttons["appointment.sendInput"]
        waitForKeyboardAndSend(send)
        XCTAssertTrue(send.isEnabled)
        assertInsideScreen(send)
        capture("appointment-max-text-keyboard-send-reachable")
        send.tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 8), "发送后应收起输入框并接上故事")
        XCTAssertTrue(app.buttons["appointment.next"].waitForExistence(timeout: 8))
        advanceToDecision()
        finishNaturally()
        reveal(app.staticTexts["appointment.affinity"])
        assertInsideScreen(app.buttons["appointment.backToChat"])
        let memories = app.buttons["appointment.manageMemories"]
        reveal(memories)
        assertInsideScreen(memories)
        capture("appointment-max-text-summary-memory-controls")
    }

    private var actionInput: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "appointment.input").firstMatch
    }

    private func launch(_ scenario: String) {
        app.launchEnvironment["UI_TEST_APPOINTMENT_SCENARIO"] = scenario
        app.launch()
        XCTAssertTrue(app.navigationBars[scenario == "list" ? "赴约" : "约定"].waitForExistence(timeout: 20))
    }

    private func advanceToDecision() {
        for _ in 0..<4 {
            if actionInput.exists { return }
            let next = app.buttons["appointment.next"]
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            reveal(next)
            next.tap()
        }
        XCTFail("未停在真实的选择边界")
    }

    private func submitCustom(_ input: String) {
        let editor = actionInput
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        reveal(editor)
        XCTAssertFalse(app.buttons["appointment.sendInput"].isEnabled)
        XCTAssertFalse(app.navigationBars["自己说一句"].exists)
        editor.tap()
        editor.typeText(input)
        capture("appointment-03-bilingual-native-input")
        let send = app.buttons["appointment.sendInput"]
        waitForKeyboardAndSend(send)
        XCTAssertTrue(send.isEnabled)
        inputTrace("before-send", send: send)
        send.tap()
        let dismissed = editor.waitForNonExistence(timeout: 8)
        inputTrace("after-send", send: send)
        if !dismissed {
            // Failed continuations retain the inline draft, locked to the original command.
            XCTAssertFalse(editor.isEnabled)
        }
        XCTAssertEqual(app.buttons["appointment.history"].value as? String, "customSubmitActions:1;focused:false", "一次点击应触发且仅触发一次真实发送动作")
    }

    private func openHistoryAndAssert(_ input: String, attachment: String?) {
        app.buttons["appointment.history"].tap()
        XCTAssertTrue(app.navigationBars["实际经历"].waitForExistence(timeout: 5))
        let original = app.staticTexts.matching(NSPredicate(format: "label == %@", input))
        reveal(original.firstMatch)
        XCTAssertEqual(original.count, 1, "历史只包含一次已接受的原始输入")
        XCTAssertTrue(app.staticTexts["你 · 自定义行动"].exists)
        if let attachment { capture(attachment) }
        app.buttons["完成"].tap()
    }

    private func finishNaturally() {
        app.buttons["阅读选项"].tap()
        let finish = app.buttons["今天就到这里"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()
        let next = app.buttons["appointment.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 8))
        reveal(next)
        next.tap()
        let summary = app.buttons["appointment.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        reveal(summary)
        summary.tap()
        XCTAssertTrue(app.buttons["appointment.backToChat"].waitForExistence(timeout: 8))
    }

    private func reveal(_ element: XCUIElement, aboveKeyboard: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<14 {
            let bottom = aboveKeyboard && app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : app.frame.maxY - 12
            if element.exists, element.isHittable, element.frame.midY > app.frame.minY + 65, element.frame.midY < bottom - 10 { return }
            let frame = element.frame
            let scroll = app.scrollViews.firstMatch
            let surface = scroll.exists ? scroll : app!
            let upper = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
            let lower = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
            if element.exists && frame.midY < app.frame.minY + 65 {
                upper.press(forDuration: 0.05, thenDragTo: lower)
            } else {
                lower.press(forDuration: 0.05, thenDragTo: upper)
            }
        }
        capture("appointment-unreachable-control")
        XCTFail("控件无法滚动到可操作区域：\(element)", file: file, line: line)
    }

    private func assertInsideScreen(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.isHittable, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.minX, app.frame.minX, file: file, line: line)
        XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX, file: file, line: line)
        XCTAssertGreaterThan(element.frame.midY, app.frame.minY + 50, file: file, line: line)
        XCTAssertLessThan(element.frame.midY, app.frame.maxY - 12, file: file, line: line)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForKeyboardAndSend(_ send: XCUIElement) {
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 8), "等待原生输入法展开后再点击随键盘移动的发送按钮")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            send.exists && send.isHittable && send.frame.maxY < keyboard.frame.minY
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed, "发送按钮须完成键盘避让，完整显示在键盘上方")
    }

    private func inputTrace(_ stage: String, send: XCUIElement) {
        let keyboard = app.keyboards.firstMatch
        let trace = XCTAttachment(string: "\(stage) sendExists=\(send.exists) frame=\(send.exists ? send.frame.debugDescription : "absent") keyboardExists=\(keyboard.exists) keyboard=\(keyboard.exists ? keyboard.frame.debugDescription : "absent") action=\(app.buttons["appointment.history"].value ?? "none")")
        trace.name = "appointment-input-\(stage)"
        trace.lifetime = .keepAlways
        add(trace)
    }
}
