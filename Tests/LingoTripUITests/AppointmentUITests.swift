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

    func testSettingsOpensLiveAppointmentWithoutFallingBackToFixture() {
        openAppointmentTestMenu()
        app.buttons["真实赴约"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "独立测试账号")).firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["appointment.start"].exists)
        app.buttons["返回设置"].tap()
        XCTAssertTrue(app.buttons["settings.test-appointments"].waitForExistence(timeout: 8))
    }

    func testSettingsOpensNativeAppointmentRecoverySimulation() {
        let entry = openAppointmentTestMenu()
        app.buttons["模拟断线恢复"].tap()
        let retry = app.buttons["appointment.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 8))
        retry.tap()

        let start = app.buttons["appointment.start"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: start)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
        start.tap()
        XCTAssertTrue(app.buttons["appointment.next"].waitForExistence(timeout: 8))
        app.buttons["暂停并返回约定"].tap()
        XCTAssertTrue(app.buttons["appointment.resume"].waitForExistence(timeout: 8))
        app.buttons["返回设置"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
    }

    func testNativeAppointmentCustomBranchThroughBackend() throws {
        let networkMonitor = try configureAppointmentBackend()
        defer { removeUIInterruptionMonitor(networkMonitor) }
        openAppointmentTestMenu()
        app.buttons["真实赴约"].tap()

        let start = app.buttons["appointment.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 30), "The live test account must have an appointment.")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: start)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
        start.tap()
        let opening = readBackendBlock()
        let choices = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "appointment.choice."))
        let originalChoices = choices.allElementsBoundByIndex.map(\.label)
        XCTAssertGreaterThanOrEqual(originalChoices.count, 2)
        capture("backend-appointment-opening")

        let input = "Could we make a tiny paper theatre with a folding curtain?"
        let editor = actionInput
        reveal(editor)
        editor.tap()
        editor.typeText(input)
        let send = app.buttons["appointment.sendInput"]
        waitForKeyboardAndSend(send)
        XCTAssertTrue(send.isEnabled)
        send.tap()
        let changed = NSPredicate { _, _ in !editor.exists || self.app.buttons["appointment.retry"].exists }
        let submitted = XCTNSPredicateExpectation(predicate: changed, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [submitted], timeout: 175), .completed)
        XCTAssertFalse(app.buttons["appointment.retry"].exists, "The backend needs to accept the custom action.")

        let continuation = readBackendBlock()
        let nextChoices = choices.allElementsBoundByIndex.map(\.label)
        XCTAssertFalse(opening.isEmpty)
        XCTAssertNotEqual(continuation, opening)
        XCTAssertGreaterThanOrEqual(nextChoices.count, 2)
        XCTAssertNotEqual(nextChoices, originalChoices)
        let paperTheatre = #"(?i)theat(?:re|er)|stage|curtain|剧场|舞台|幕布"#
        XCTAssertNotNil(continuation.joined(separator: " ").range(of: paperTheatre, options: .regularExpression))
        XCTAssertNotNil(nextChoices.joined(separator: " ").range(of: paperTheatre, options: .regularExpression))
        capture("backend-appointment-custom-branch")
        openHistoryAndAssert(input, attachment: "backend-appointment-custom-history")

        app.buttons["暂停并返回约定"].tap()
        let resume = app.buttons["appointment.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 15))
        resume.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertEqual(choices.allElementsBoundByIndex.map(\.label), nextChoices)

        app.buttons["阅读选项"].tap()
        app.buttons["今天就到这里"].tap()
        let summary = app.buttons["appointment.summary"]
        _ = readBackendBlock(waitingForEnding: true)
        XCTAssertTrue(summary.exists)
        summary.tap()
        let affinity = app.staticTexts["appointment.affinity"]
        XCTAssertTrue(affinity.waitForExistence(timeout: 45), "The completed appointment must settle.")
        let savedInput = app.staticTexts.matching(NSPredicate(format: "label == %@", input))
        reveal(savedInput.firstMatch)
        XCTAssertEqual(savedInput.count, 1)
        capture("backend-appointment-settled-summary")

        app.buttons["appointment.back"].tap()
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        app.buttons["暂停并返回约定"].tap()
        let reopen = app.buttons["appointment.openSummary"]
        XCTAssertTrue(reopen.waitForExistence(timeout: 15))
        reopen.tap()
        reveal(savedInput.firstMatch)
        XCTAssertEqual(savedInput.count, 1)
        XCTAssertFalse(editor.exists)
    }

    func testNativeAppointmentReviewRecoversThroughBackend() throws {
        let networkMonitor = try configureAppointmentBackend()
        defer { removeUIInterruptionMonitor(networkMonitor) }
        openAppointmentTestMenu()
        app.buttons["真实赴约"].tap()

        let reopen = app.buttons["appointment.openSummary"]
        XCTAssertTrue(reopen.waitForExistence(timeout: 35), "Provision the device with the completed test appointment.")
        reopen.tap()
        let input = "Could we make a tiny paper theatre with a folding curtain?"
        let savedInput = app.staticTexts.matching(NSPredicate(format: "label == %@", input))
        XCTAssertTrue(savedInput.firstMatch.waitForExistence(timeout: 20))
        reveal(savedInput.firstMatch)
        XCTAssertEqual(savedInput.count, 1)
        XCTAssertFalse(actionInput.exists)

        let affinity = app.staticTexts["appointment.affinity"]
        let retry = app.buttons["重试整理回顾"]
        let ready = NSPredicate { _, _ in affinity.exists || (retry.exists && retry.isEnabled) }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 45), .completed)
        if !affinity.exists {
            reveal(retry)
            retry.tap()
        }
        XCTAssertTrue(affinity.waitForExistence(timeout: 45), "The completed appointment should settle after review is retried.")
        reveal(savedInput.firstMatch)
        XCTAssertEqual(savedInput.count, 1)
        capture("backend-appointment-recovered-review")
    }

    func testCustomAppointmentFromChatThroughSummary() throws {
        struct Scenario: Decodable {
            let email: String
            let password: String
            let companion: String
            let invitation: String
            let actions: [String]
            let expectedPlacePattern: String?
        }
        guard let json = ProcessInfo.processInfo.environment["LINGOTRIP_APPOINTMENT_JOURNEY"] else {
            throw XCTSkip("Provide an isolated backend and a scenario with a test account, companion, invitation and actions.")
        }
        let scenario = try JSONDecoder().decode(Scenario.self, from: Data(json.utf8))
        XCTAssertFalse(scenario.actions.isEmpty)
        let networkMonitor = try configureAppointmentBackend()
        defer { removeUIInterruptionMonitor(networkMonitor) }
        app.launchEnvironment["UI_TEST_REQUIRE_AUTHENTICATION"] = "1"
        app.launchEnvironment["UI_TEST_TAB"] = "contacts"
        app.launch()

        let emailDisclosure = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "使用邮箱登录或注册")
        ).firstMatch
        XCTAssertTrue(emailDisclosure.waitForExistence(timeout: 30))
        reveal(emailDisclosure)
        emailDisclosure.tap()
        let email = app.textFields["邮箱"]
        let password = app.secureTextFields["密码"]
        reveal(email)
        email.tap()
        email.typeText(scenario.email)
        reveal(password, aboveKeyboard: true)
        password.tap()
        password.typeText(scenario.password)
        let login = app.buttons["auth.submitCredentials"]
        reveal(login, aboveKeyboard: true)
        login.tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
        let deferSave = app.buttons.matching(NSPredicate(format: "label IN %@", ["以后", "Not Now"])).firstMatch
        if deferSave.waitForExistence(timeout: 3) { deferSave.tap() }

        let companion = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", scenario.companion)
        ).firstMatch
        XCTAssertTrue(companion.wait(for: \.isHittable, toEqual: true, timeout: 40))
        companion.tap()
        let composer = app.descendants(matching: .any)["chat.composer"].firstMatch
        if !composer.waitForExistence(timeout: 3) {
            let message = app.descendants(matching: .any).matching(
                NSPredicate(format: "label == %@", "发消息")
            ).firstMatch
            let profileLoaded = message.waitForExistence(timeout: 8)
            if !profileLoaded { capture("appointment-journey-contact") }
            XCTAssertTrue(profileLoaded, app.debugDescription)
            message.tap()
        }
        XCTAssertTrue(composer.waitForExistence(timeout: 15))
        composer.tap()
        composer.typeText(scenario.invitation)
        let send = app.buttons["chat.send"]
        waitForKeyboardAndSend(send)
        XCTAssertTrue(send.isEnabled)
        send.tap()
        XCTAssertTrue(send.wait(for: \.isEnabled, toEqual: false, timeout: 6), "The chat composer should clear the sent draft.")
        let agreement = app.buttons.matching(identifier: "chat.timeline.event").matching(
            NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", scenario.companion, "约好了")
        ).firstMatch
        XCTAssertTrue(agreement.waitForExistence(timeout: 110), "The normal chat flow should confirm the invitation after the companion replies.")
        capture("appointment-journey-chat")
        agreement.tap()
        let start = app.buttons["appointment.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 25))
        if let pattern = scenario.expectedPlacePattern {
            let place = app.staticTexts.matching(NSPredicate(format: "label MATCHES[c] %@", ".*(?:\(pattern)).*")).firstMatch
            XCTAssertTrue(place.waitForExistence(timeout: 10), "The detail should display the place chosen in chat.")
        }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: start)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
        reveal(start)
        start.tap()
        var precedingBlock = readBackendBlock()

        for (index, action) in scenario.actions.enumerated() {
            let editor = actionInput
            XCTAssertTrue(editor.exists)
            reveal(editor)
            editor.tap()
            editor.typeText(action)
            let submit = app.buttons["appointment.sendInput"]
            waitForKeyboardAndSend(submit)
            submit.tap()
            let submitted = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in !editor.exists || self.app.buttons["appointment.retry"].exists },
                object: nil
            )
            XCTAssertEqual(XCTWaiter.wait(for: [submitted], timeout: 175), .completed)
            XCTAssertFalse(app.buttons["appointment.retry"].exists)
            let continuation = readBackendBlock()
            XCTAssertNotEqual(continuation, precedingBlock, "The custom action should advance the story.")
            precedingBlock = continuation
            capture("appointment-journey-action-\(index + 1)")
        }
        let summary = app.buttons["appointment.summary"]
        if !summary.exists {
            app.buttons["阅读选项"].tap()
            app.buttons["今天就到这里"].tap()
            _ = readBackendBlock(waitingForEnding: true)
        }
        XCTAssertTrue(summary.exists)
        summary.tap()
        XCTAssertTrue(app.staticTexts["appointment.affinity"].waitForExistence(timeout: 55))
        for action in scenario.actions {
            let saved = app.staticTexts.matching(NSPredicate(format: "label == %@", action))
            XCTAssertTrue(saved.firstMatch.waitForExistence(timeout: 15))
            reveal(saved.firstMatch)
            XCTAssertEqual(saved.count, 1)
        }
        capture("appointment-journey-summary")
    }

    private func configureAppointmentBackend() throws -> NSObjectProtocol {
        guard let endpoint = ProcessInfo.processInfo.environment["LINGOTRIP_APPOINTMENT_E2E_URL"] else {
            throw XCTSkip("Provide an isolated test backend URL and provision the test device.")
        }
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = endpoint
        return addUIInterruptionMonitor(withDescription: "Test app network access") { alert in
            if alert.label.contains("使用无线数据") {
                let buttons = alert.buttons.allElementsBoundByIndex
                let wifi = buttons.filter { button in
                    let label = button.label
                    return label.contains("无线局域网") || label.localizedCaseInsensitiveContains("WLAN")
                        || label.localizedCaseInsensitiveContains("Wi-Fi")
                }
                let wifiOnly = wifi.first { !$0.label.contains("蜂窝") }
                guard let allow = wifiOnly ?? wifi.first ?? buttons.first(where: { $0.label == "允许" }) else {
                    XCTFail("No network-access option found: \(buttons.map(\.label))")
                    return false
                }
                allow.tap()
                return true
            }
            if alert.label.contains("本地网络"), alert.buttons["允许"].exists {
                alert.buttons["允许"].tap()
                return true
            }
            return false
        }
    }

    private func readBackendBlock(waitingForEnding: Bool = false) -> [String] {
        let next = app.buttons["appointment.next"]
        let summary = app.buttons["appointment.summary"]
        let line = app.scrollViews["appointment.readerScroll"].staticTexts
            .matching(NSPredicate(format: "label MATCHES %@", #".*[\p{Han}].*"#)).firstMatch
        let ready = NSPredicate { _, _ in
            next.exists || summary.exists || (!waitingForEnding && self.actionInput.exists)
                || self.app.buttons["appointment.retry"].exists
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 175), .completed)
        XCTAssertFalse(app.buttons["appointment.retry"].exists, "The backend needs to deliver a story block.")
        var lines: [String] = []
        for _ in 0..<8 {
            XCTAssertTrue(line.waitForExistence(timeout: 8))
            lines.append(line.label)
            if summary.exists || (!waitingForEnding && actionInput.exists) { return lines }
            let prior = line.label
            XCTAssertTrue(next.exists)
            next.tap()
            let moved = NSPredicate { _, _ in (line.exists && line.label != prior) || !next.exists }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: moved, object: nil)], timeout: 8), .completed)
        }
        XCTFail("The story block did not reach its choices or ending.")
        return lines
    }

    @discardableResult
    private func openAppointmentTestMenu() -> XCUIElement {
        app.launchEnvironment["UI_TEST_TAB"] = "me"
        app.launch()
        let settings = app.buttons["me.settings"]
        reveal(settings)
        settings.tap()
        let entry = app.buttons["settings.test-appointments"]
        reveal(entry)
        entry.tap()
        return entry
    }

    func testNativeSummaryDesignPreview() {
        app.launchEnvironment["UI_TEST_APPOINTMENT_SCENARIO"] = "summary-design"
        app.launch()
        XCTAssertTrue(app.staticTexts["appointment.title"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts["appointment.title"].label, "和Oliver一起散步")
        XCTAssertTrue(app.staticTexts["appointment.affinity"].exists)
        XCTAssertTrue(app.staticTexts["Could we sit by the water? 我想安静坐一会。"].exists)
        XCTAssertTrue(app.staticTexts["今天就到这里"].exists)
        capture("appointment-native-summary-design")
        app.buttons["appointment.back"].tap()
        XCTAssertTrue(app.buttons["home.appointments"].waitForExistence(timeout: 5))
    }

    func testRefreshBeforeEntryWindowDoesNotStartAppointment() {
        launch("before-window")
        let waiting = app.buttons.matching(identifier: "appointment.start")
            .matching(NSPredicate(format: "label == %@", "未到赴约时段")).firstMatch
        XCTAssertTrue(waiting.waitForExistence(timeout: 8))
        XCTAssertFalse(waiting.isEnabled)
        let refresh = app.buttons["appointment.details.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 8))
        XCTAssertLessThan(refresh.frame.midX, app.buttons["appointment.details.options"].frame.midX)
        let window = app.staticTexts["appointment.entryWindow"]
        reveal(window)
        XCTAssertTrue(window.label.contains("北京时间"))

        refresh.tap()
        let start = app.buttons.matching(identifier: "appointment.start")
            .matching(NSPredicate(format: "label == %@", "去赴约")).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        XCTAssertTrue(start.isEnabled)
        XCTAssertFalse(app.buttons["appointment.next"].exists)
        start.tap()
        XCTAssertTrue(app.buttons["appointment.next"].waitForExistence(timeout: 8))
    }

    func testFailedReadRecoversWhenReturningToAppointments() {
        launch("reconnect")
        let retry = app.buttons["appointment.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 8))
        let start = app.buttons["appointment.start"]
        XCTAssertFalse(start.isEnabled)

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 6))
        app.activate()
        let available = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: start)
        XCTAssertEqual(XCTWaiter.wait(for: [available], timeout: 8), .completed)
        XCTAssertFalse(retry.exists)
        XCTAssertFalse(app.buttons["appointment.next"].exists)
    }

    func testConfirmedCustomBilingualPathPauseFinishAndReadOnlySummary() throws {
        launch("list")
        let start = app.buttons["appointment.start"]
        reveal(start)
        capture("appointment-00-list")
        XCTAssertFalse(app.navigationBars["赴约"].exists)
        XCTAssertFalse(app.buttons["关闭约定"].exists)
        app.buttons["appointment.details.options"].tap()
        app.buttons["照片来源"].tap()
        XCTAssertTrue(app.staticTexts["照片来源"].waitForExistence(timeout: 5))
        capture("appointment-photo-credits")
        app.buttons["返回约定"].tap()
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
        reveal(returnToChat)
        XCTAssertTrue(returnToChat.isHittable)

        // Reopening exposes saved results and no editable choice/finish action.
        XCTAssertFalse(app.staticTexts["谢谢你把自己的想法说出来。我们一起商量了这段时间怎么过。"].exists)
        let back = app.buttons["appointment.back"]
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

    func testCompletedCardOpensSummaryDirectly() {
        launch("completed")
        let summary = app.buttons["appointment.openSummary"]
        reveal(summary)
        summary.tap()
        XCTAssertTrue(app.buttons["appointment.backToChat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["appointment.affinity"].exists)
        XCTAssertFalse(app.staticTexts["你们在南岸的水边坐了一会，随后沿步道走回桥边。"].exists)
        capture("appointment-completed-card-summary")
        app.buttons["appointment.back"].tap()
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["约定"].exists)
    }

    func testSummaryDisplaysZeroNegativeAndPendingValues() {
        for (scenario, label) in [("zero", "好感不变"), ("negative", "好感 -1"), ("pending", "好感待结算")] {
            launch(scenario)
            let summary = app.buttons["appointment.openSummary"]
            reveal(summary)
            summary.tap()
            let identifier = scenario == "pending" ? "appointment.affinity.pending" : "appointment.affinity"
            let affinity = app.staticTexts[identifier]
            reveal(affinity)
            XCTAssertEqual(affinity.label, label)
            capture("appointment-summary-\(scenario)")
            app.terminate()
        }
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
        let quietChoice = app.buttons["appointment.choice.quiet"]
        reveal(quietChoice, aboveKeyboard: true)
        assertInsideScreen(quietChoice)
        capture("appointment-max-text-keyboard-second-choice")
        reveal(editor, aboveKeyboard: true)
        editor.tap()
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
        reveal(app.buttons["appointment.backToChat"])
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
        let action: String
        switch scenario {
        case "active", "retry", "offline", "conflict": action = "appointment.resume"
        case "completed", "zero", "negative", "pending": action = "appointment.openSummary"
        default: action = "appointment.start"
        }
        XCTAssertTrue(app.buttons[action].waitForExistence(timeout: 20))
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
        assertComposerFollowsChoices(editor)
        capture("appointment-03-bilingual-native-input")
        let send = app.buttons["appointment.sendInput"]
        waitForKeyboardAndSend(send)
        assertInsideReader(app.buttons["appointment.choice.walk"])
        assertInsideReader(app.buttons["appointment.choice.quiet"])
        assertInsideReader(editor)
        assertComposerFollowsChoices(editor)
        capture("appointment-03-bilingual-keyboard-settled")
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
        XCTAssertTrue(app.staticTexts["实际经历"].waitForExistence(timeout: 5))
        let original = app.staticTexts.matching(NSPredicate(format: "label == %@", input))
        reveal(original.firstMatch)
        XCTAssertEqual(original.count, 1, "历史只包含一次已接受的原始输入")
        XCTAssertTrue(app.staticTexts["你 · 自定义行动"].exists)
        if let attachment { capture(attachment) }
        app.buttons["返回阅读"].tap()
    }

    private func assertComposerFollowsChoices(_ editor: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let lastChoice = app.buttons["appointment.choice.quiet"]
        XCTAssertTrue(lastChoice.exists, file: file, line: line)
        XCTAssertGreaterThanOrEqual(editor.frame.minY - lastChoice.frame.maxY, 12,
                                    "输入框必须排在完整的最后一个选项之后", file: file, line: line)
        XCTAssertLessThanOrEqual(editor.frame.minY - lastChoice.frame.maxY, 48,
                                 "聚焦输入时，选项与输入框之间不应出现撑满滚动区的空白", file: file, line: line)
    }

    private func assertInsideReader(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let viewport = app.scrollViews["appointment.readerScroll"].frame
        XCTAssertTrue(element.isHittable, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.minY, viewport.minY - 1, file: file, line: line)
        XCTAssertLessThanOrEqual(element.frame.maxY, viewport.maxY + 1, file: file, line: line)
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
            let reader = app.scrollViews["appointment.readerScroll"]
            let scroll = reader.exists ? reader : app.scrollViews.firstMatch
            let top = max(app.frame.minY + 65, scroll.exists ? scroll.frame.minY + 8 : app.frame.minY + 65)
            let bottom = aboveKeyboard && app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : app.frame.maxY - 12
            if element.exists, element.isHittable, element.frame.midY > top, element.frame.midY < bottom - 10 { return }
            let frame = element.frame
            let surface = scroll.exists ? scroll : app!
            let upper = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
            let lower = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
            if element.exists && frame.midY < top {
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
        var previousFrame = CGRect.null
        var stableSince = Date()
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard send.exists, send.isHittable, send.frame.maxY < keyboard.frame.minY else { return false }
            let frame = send.frame
            if frame != previousFrame {
                previousFrame = frame
                stableSince = Date()
            }
            return Date().timeIntervalSince(stableSince) >= 0.4
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
