import XCTest

@MainActor
final class ChatTimelineEventUITests: XCTestCase {
    func testSignedInSharedReplySurvivesRelaunch() throws {
        continueAfterFailure = false
        let (app, row) = try openIsolatedConversation()
        defer { app.terminate() }
        let field = app.descendants(matching: .any)["chat.composer"].firstMatch
        let existingInput = app.buttons.matching(NSPredicate(format: "label ==[c] %@", "feeling")).firstMatch
        if existingInput.exists {
            waitForReply(word: "Thames", in: app, timeout: 165)
        } else {
            send("How are you feeling right now?", expectWord: "Thames", field: field, app: app, timeout: 165)
        }
        let mood = event(containing: "疲惫", in: app)
        XCTAssertTrue(mood.waitForExistence(timeout: 30))
        XCTAssertTrue(mood.isHittable)

        app.terminate()
        app.launch()
        XCTAssertTrue(row.waitForExistence(timeout: 25))
        row.tap()
        XCTAssertTrue(mood.waitForExistence(timeout: 15))
        capture("Synced timeline on a reopened signed-in conversation", in: app)
        signOut(from: app)
    }

    func testSignedInAppointmentCancellationAppearsOnReturnToChat() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["LINGOTRIP_TIMELINE_TEST_APPOINTMENT"] == "1" else {
            throw XCTSkip("Requires an uncancelled appointment in the isolated conversation")
        }
        let (app, row) = try openIsolatedConversation()
        defer { app.terminate() }
        let confirmed = event(containing: "约好了", in: app)
        XCTAssertTrue(confirmed.waitForExistence(timeout: 15))
        XCTAssertTrue(confirmed.isHittable)
        confirmed.tap()

        let place = app.staticTexts["Timeline Test Bookshop"]
        XCTAssertTrue(place.waitForExistence(timeout: 10))
        let options = app.buttons["appointment.details.options"]
        XCTAssertTrue(options.waitForExistence(timeout: 8))
        options.tap()
        let cancel = app.buttons["取消约定"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(app.staticTexts["已取消"].waitForExistence(timeout: 10))

        app.buttons["返回活动"].tap()
        let cancellation = event(containing: "这次约定已取消", in: app)
        XCTAssertTrue(cancellation.waitForExistence(timeout: 8), "The open chat should update after a committed cancellation")
        XCTAssertTrue(confirmed.exists, "Cancellation must preserve the original confirmation")
        capture("Confirmation and cancellation in the open conversation", in: app)

        app.terminate()
        app.launch()
        XCTAssertTrue(row.waitForExistence(timeout: 25))
        row.tap()
        XCTAssertTrue(cancellation.waitForExistence(timeout: 15))
        XCTAssertEqual(events(in: app).matching(NSPredicate(format: "label CONTAINS %@", "这次约定已取消")).count, 1)
        signOut(from: app)
    }

    private func openIsolatedConversation() throws -> (XCUIApplication, XCUIElement) {
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
        let visibleRow = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: row)
        XCTAssertEqual(XCTWaiter.wait(for: [visibleRow], timeout: 8), .completed)
        row.tap()
        let field = app.descendants(matching: .any)["chat.composer"].firstMatch
        if !field.waitForExistence(timeout: 2), row.isHittable {
            // The password prompt can animate away after UIKit exposes the row to XCTest.
            row.tap()
        }
        XCTAssertTrue(field.waitForExistence(timeout: 12))
        return (app, row)
    }

    private func signOut(from app: XCUIApplication) {
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
        XCTAssertTrue(app.buttons["使用邮箱登录或注册"].waitForExistence(timeout: 10))
    }

    func testGroundedMoodAndPacingThroughActualChatComposer() {
        continueAfterFailure = false
        let app = launchLocalConversation()
        defer { app.terminate() }
        let field = app.descendants(matching: .any)["chat.composer"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        let events = events(in: app)

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
        capture("Grounded emotion after a completed chat turn", in: app)
    }

    func testMemoryChangesAndRecallUseCommittedFacts() {
        continueAfterFailure = false
        let app = launchLocalConversation(persistAcrossLaunches: true)
        defer { app.terminate() }
        let field = app.descendants(matching: .any)["chat.composer"].firstMatch
        let remembered = event(containing: "记住了你的话", in: app)
        send("I like Earl Grey tea.", expectWord: "classic", field: field, app: app)
        XCTAssertTrue(remembered.waitForExistence(timeout: 8))

        send("Where is the station?", expectWord: "square", field: field, app: app)
        send("Is the river quiet?", expectWord: "morning", field: field, app: app)
        send("I like Earl Grey tea, by the way.", expectWord: "bergamot", field: field, app: app)
        XCTAssertLessThanOrEqual(events(in: app).count, 1, "Restating the same preference must not create a new capsule")
        XCTAssertFalse(event(containing: "更新了", in: app).exists)

        send("Correction: I meant jasmine tea.", expectWord: "Jasmine", field: field, app: app)
        let corrected = event(containing: "更正了之前的记忆", in: app)
        XCTAssertTrue(corrected.waitForExistence(timeout: 8))
        send("How about a different route?", expectWord: "bridge", field: field, app: app)
        send("I see it differently.", expectWord: "Fair", field: field, app: app)
        send("I like the rain.", expectWord: "pavement", field: field, app: app)
        send("What should we order?", expectWord: "pot", field: field, app: app)
        let recalled = event(containing: "提起了以前记下的事", in: app)
        XCTAssertTrue(recalled.waitForExistence(timeout: 8), "A fabricated quote on the preceding eligible turn must not consume the cadence window")

        app.terminate()
        app.launch()
        XCTAssertTrue(recalled.waitForExistence(timeout: 20))
        capture("Recalled memory after a native process relaunch", in: app)
    }

    func testRelationshipChangesDistinguishSupportDisagreementAndHarm() {
        continueAfterFailure = false
        let app = launchLocalConversation()
        defer { app.terminate() }
        let field = app.descendants(matching: .any)["chat.composer"].firstMatch
        send("That took courage to tell me. I can stay with you while you make the call.", expectWord: "conversation", field: field, app: app)
        let positive = events(in: app).matching(NSPredicate(
            format: "label CONTAINS %@ OR label CONTAINS %@ OR label CONTAINS %@", "好感度 +", "多了几分信任", "更自在"
        )).firstMatch
        XCTAssertTrue(positive.waitForExistence(timeout: 8))
        send("Where is the station?", expectWord: "square", field: field, app: app)
        send("How about a different route?", expectWord: "bridge", field: field, app: app)
        send("I see it differently.", expectWord: "Fair", field: field, app: app)
        let strain = event(containing: "之间有了些紧张", in: app)
        XCTAssertFalse(strain.exists)
        send("You asked me to stop, but I will share your private messages anyway.", expectWord: "confidence", field: field, app: app)
        XCTAssertTrue(strain.waitForExistence(timeout: 8), "Only the boundary violation should cause strain")
        capture("Relationship strain after a boundary violation", in: app)
    }

    private func launchLocalConversation(persistAcrossLaunches: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "UI_TEST_SKIP_ONBOARDING": "1",
            "UI_TEST_WELCOME_CAPTURE": "1",
            "UI_TEST_NATIVE_CAPTURE": "chat",
            "UI_TEST_CHAT_TIMELINE_WORKFLOW": "1",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
            "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9",
        ]
        if persistAcrossLaunches {
            app.launchEnvironment["UI_TEST_PERSISTENCE_NAMESPACE"] = UUID().uuidString
        }
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["chat.composer"].firstMatch.waitForExistence(timeout: 20))
        return app
    }

    private func events(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "chat.timeline.event")
    }

    private func event(containing text: String, in app: XCUIApplication) -> XCUIElement {
        events(in: app).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func capture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
