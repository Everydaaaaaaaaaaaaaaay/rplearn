import XCTest

@MainActor
final class ChatTimelineEventUITests: XCTestCase {
    func testSignedInSharedReplySurvivesRelaunch() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        guard let url = environment["LINGOTRIP_TIMELINE_TEST_URL"],
              URL(string: url)?.host == "127.0.0.1",
              let email = environment["LINGOTRIP_TIMELINE_TEST_EMAIL"],
              let password = environment["LINGOTRIP_TIMELINE_TEST_PASSWORD"] else {
            throw XCTSkip("Requires the isolated API, worker and account")
        }
        let app = XCUIApplication()
        app.launchEnvironment = [
            "UI_TEST_SKIP_ONBOARDING": "1",
            "UI_TEST_REQUIRE_AUTHENTICATION": "1",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
            "LINGOTRIP_BACKEND_URL": url,
        ]
        app.launch()
        defer { app.terminate() }
        let passwordButtons = NSPredicate(format: "label IN %@", ["以后", "Not Now"])
        let passwordMonitor = addUIInterruptionMonitor(withDescription: "iOS Save Password") { alert in
            let later = alert.buttons.matching(passwordButtons).firstMatch
            guard later.exists else { return false }
            later.tap()
            return true
        }
        defer { removeUIInterruptionMonitor(passwordMonitor) }
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Audit Read Friend")).firstMatch
        let emailDisclosure = app.buttons["使用邮箱登录或注册"]
        if emailDisclosure.waitForExistence(timeout: 6) {
            emailDisclosure.tap()
            let address = app.textFields["邮箱"]
            XCTAssertTrue(address.waitForExistence(timeout: 5))
            address.tap()
            address.typeText(email)
            let secret = app.secureTextFields["密码"]
            secret.tap()
            secret.typeText(password)
            let submit = app.buttons["auth.submitCredentials"]
            if !submit.isHittable { app.scrollViews.firstMatch.swipeUp() }
            submit.tap()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 25))
        let later = app.buttons.matching(passwordButtons).firstMatch
        if later.waitForExistence(timeout: 3) { later.tap() }
        row.tap()
        let field = app.descendants(matching: .any)["chat.composer"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 12))
        let existingInput = app.buttons.matching(NSPredicate(format: "label ==[c] %@", "feeling")).firstMatch
        if existingInput.exists {
            waitForReply(word: "Thames", in: app, timeout: 165)
        } else {
            send("How are you feeling right now?", expectWord: "Thames", field: field, app: app, timeout: 165)
        }
        let mood = app.descendants(matching: .any).matching(identifier: "chat.timeline.event")
            .matching(NSPredicate(format: "label CONTAINS %@", "疲惫")).firstMatch
        XCTAssertTrue(mood.waitForExistence(timeout: 30))
        XCTAssertTrue(mood.isHittable)

        app.terminate()
        app.launch()
        XCTAssertTrue(row.waitForExistence(timeout: 25))
        row.tap()
        XCTAssertTrue(mood.waitForExistence(timeout: 15))
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Synced timeline on a reopened signed-in conversation"
        capture.lifetime = .keepAlways
        add(capture)
        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        let home = app.tabBars.buttons["我的"]
        XCTAssertTrue(home.waitForExistence(timeout: 6))
        home.tap()
        let profile = app.buttons["me.profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        profile.tap()
        let signOut = app.buttons["退出登录"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 5))
        if !signOut.isHittable { app.scrollViews.firstMatch.swipeUp() }
        signOut.tap()
        XCTAssertTrue(emailDisclosure.waitForExistence(timeout: 10))
    }

    func testGroundedMoodAndPacingThroughActualChatComposer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = [
            "UI_TEST_SKIP_ONBOARDING": "1",
            "UI_TEST_WELCOME_CAPTURE": "1",
            "UI_TEST_NATIVE_CAPTURE": "chat",
            "UI_TEST_CHAT_TIMELINE_WORKFLOW": "1",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
            "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9",
        ]
        app.launch()
        defer { app.terminate() }
        let field = app.descendants(matching: .any)["chat.composer"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        let events = app.descendants(matching: .any).matching(identifier: "chat.timeline.event")

        send("How are you doing?", expectWord: "sad", field: field, app: app)
        let sad = events.matching(NSPredicate(format: "label CONTAINS %@", "伤心")).firstMatch
        XCTAssertTrue(sad.waitForExistence(timeout: 8))
        XCTAssertEqual(events.count, 1)

        send("How was your walk?", expectWord: "after", field: field, app: app)
        send("Tell me more.", expectWord: "morning", field: field, app: app)
        send("Was your sister angry?", expectWord: "furious", field: field, app: app)
        XCTAssertFalse(events.matching(NSPredicate(format: "label CONTAINS %@", "生气")).firstMatch.exists)
        XCTAssertLessThanOrEqual(events.count, 1, "Repeated moods and someone else's anger must stay out of the timeline")

        send("Did it work out?", expectWord: "worked", field: field, app: app)
        let happy = events.matching(NSPredicate(format: "label CONTAINS %@", "心情不错")).firstMatch
        XCTAssertTrue(happy.waitForExistence(timeout: 8))
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Grounded emotion after a completed chat turn"
        capture.lifetime = .keepAlways
        add(capture)
    }

    private func send(_ text: String, expectWord word: String, field: XCUIElement, app: XCUIApplication, timeout: TimeInterval = 15) {
        field.tap()
        field.typeText(text)
        let send = app.buttons["chat.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()
        waitForReply(word: word, in: app, timeout: timeout)
    }

    private func waitForReply(word: String, in app: XCUIApplication, timeout: TimeInterval) {
        let delivered = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", word)).firstMatch
        if !delivered.waitForExistence(timeout: timeout) {
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = "Chat while awaiting \(word)"
            capture.lifetime = .keepAlways
            add(capture)
            XCTFail("Missing reply word: \(word)")
        }
    }
}
