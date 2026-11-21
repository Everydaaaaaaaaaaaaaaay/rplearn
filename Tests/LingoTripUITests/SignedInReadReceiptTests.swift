import XCTest

@MainActor
final class SignedInReadReceiptTests: XCTestCase {
    func testReadReplyStaysReadAfterTabSwitchAndRelaunch() async throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        guard let url = environment["LINGOTRIP_NATIVE_AUDIT_URL"],
              URL(string: url)?.host == "127.0.0.1",
              let email = environment["LINGOTRIP_NATIVE_AUDIT_EMAIL"],
              let password = environment["LINGOTRIP_NATIVE_AUDIT_PASSWORD"],
              let conversationID = environment["LINGOTRIP_NATIVE_AUDIT_CONVERSATION"] else {
            throw XCTSkip("Requires the isolated native audit account and API")
        }

        let app = XCUIApplication()
        app.launchEnvironment = [
            "LINGOTRIP_BACKEND_URL": url,
            "UI_TEST_REQUIRE_AUTHENTICATION": "1",
            "UI_TEST_SKIP_ONBOARDING": "1",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
        ]
        app.launch()
        defer { app.terminate() }

        let savePasswordDismissal = NSPredicate(format: "label IN %@", ["以后", "Not Now"])
        let passwordMonitor = addUIInterruptionMonitor(withDescription: "iOS Save Password") { alert in
            let later = alert.buttons.matching(savePasswordDismissal).firstMatch
            guard later.exists else { return false }
            later.tap()
            return true
        }
        defer { removeUIInterruptionMonitor(passwordMonitor) }

        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Audit Read Friend")).firstMatch
        let emailDisclosure = app.buttons["使用邮箱登录或注册"]
        if !emailDisclosure.waitForExistence(timeout: 5), app.tabBars.buttons["我的"].exists {
            signOutAuditAccount(in: app)
            XCTAssertTrue(emailDisclosure.waitForExistence(timeout: 10))
            app.terminate()
            app.launch()
        }
        XCTAssertTrue(emailDisclosure.waitForExistence(timeout: 15))
        emailDisclosure.tap()
        let emailField = app.textFields["邮箱"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        emailField.tap()
        emailField.typeText(email)
        let passwordField = app.secureTextFields["密码"]
        passwordField.tap()
        passwordField.typeText(password)
        let login = app.buttons["auth.submitCredentials"]
        if !login.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(login.isHittable)
        login.tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "Email login must reach the main tabs")
        let later = app.buttons.matching(savePasswordDismissal).firstMatch
        if later.waitForExistence(timeout: 3) { later.tap() }
        XCTAssertTrue(row.waitForExistence(timeout: 20), "The synced conversation must appear in Messages")
        let unread = NSPredicate(format: "label CONTAINS %@", "条未读")
        XCTAssertTrue(unread.evaluate(with: row), "The seeded message must start unread")
        let initial = XCTAttachment(screenshot: app.screenshot())
        initial.name = "Signed-in unread conversation"
        initial.lifetime = .keepAlways
        add(initial)
        row.tap()
        let latest = app.descendants(matching: .any)["chat.message.latest"].firstMatch
        XCTAssertTrue(latest.waitForExistence(timeout: 12))
        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 12))
        let contacts = app.tabBars.buttons["联系人"]
        let messages = app.tabBars.buttons["信息"]
        for _ in 0..<2 {
            XCTAssertTrue(contacts.waitForExistence(timeout: 5))
            contacts.tap()
            XCTAssertTrue(contacts.wait(for: \.isSelected, toEqual: true, timeout: 5))
            XCTAssertTrue(messages.waitForExistence(timeout: 5))
            messages.tap()
            XCTAssertTrue(messages.wait(for: \.isSelected, toEqual: true, timeout: 5))
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            XCTAssertFalse(unread.evaluate(with: row), "Switching tabs must not make the same reply unread")
        }
        let secondSession = try await request("/v1/auth/login", base: url, body: [
            "email": email, "password": password,
            "device": ["deviceId": UUID().uuidString, "platform": "ios"],
        ])
        let secondSessionToken = try XCTUnwrap(secondSession["accessToken"] as? String)
        let savedConversation = try await conversation(base: url, token: secondSessionToken, id: conversationID)
        let savedPayload = try XCTUnwrap(savedConversation["payload"] as? [String: Any])
        let readTimestamp = try XCTUnwrap(savedPayload["lastReadAt"] as? String)
        XCTAssertEqual(readTimestamp, savedPayload["lastMessageAt"] as? String,
                       "The same message timestamp must survive the wire round trip")
        app.terminate()
        app.launch()
        XCTAssertTrue(row.waitForExistence(timeout: 35))
        XCTAssertFalse(unread.evaluate(with: row), "A persisted read receipt must survive reloading the synced conversation")
        let final = XCTAttachment(screenshot: app.screenshot())
        final.name = "Read stays read after restart"
        final.lifetime = .keepAlways
        add(final)

        try await addReply(base: url, token: secondSessionToken, conversation: savedConversation,
                           after: readTimestamp)
        app.terminate()
        app.launch()
        let newUnread = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "A second reply", "条未读"),
            object: row
        )
        await fulfillment(of: [newUnread], timeout: 35)
        let fresh = XCTAttachment(screenshot: app.screenshot())
        fresh.name = "New same-second reply is unread"
        fresh.lifetime = .keepAlways
        add(fresh)

        signOutAuditAccount(in: app)
        XCTAssertTrue(emailDisclosure.waitForExistence(timeout: 10))
    }

    private func signOutAuditAccount(in app: XCUIApplication) {
        let profileTab = app.tabBars.buttons["我的"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 5))
        profileTab.tap()
        XCTAssertTrue(profileTab.wait(for: \.isSelected, toEqual: true, timeout: 5))
        let profile = app.buttons["me.profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        profile.tap()
        let signOut = app.buttons["退出登录"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 5))
        if !signOut.isHittable { app.scrollViews.firstMatch.swipeUp() }
        signOut.tap()
    }

    private func conversation(base: String, token: String, id: String) async throws -> [String: Any] {
        let response = try await request("/v1/content/records?limit=100", base: base, token: token)
        let records = try XCTUnwrap(response["records"] as? [[String: Any]])
        return try XCTUnwrap(records.first {
            $0["resourceType"] as? String == "conversation" && $0["resourceId"] as? String == id
        })
    }

    private func addReply(base: String, token: String, conversation: [String: Any], after readAt: String) async throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let previous = try XCTUnwrap(formatter.date(from: readAt))
        let timestamp = formatter.string(from: previous.addingTimeInterval(0.002))
        let conversationID = try XCTUnwrap(conversation["resourceId"] as? String)
        let parentID = try XCTUnwrap(conversation["parentId"] as? String)
        let version = try XCTUnwrap(conversation["version"] as? Int)
        var payload = try XCTUnwrap(conversation["payload"] as? [String: Any])
        payload["lastMessageAt"] = timestamp
        let commands: [[String: Any]] = [
            ["commandId": UUID().uuidString.lowercased(), "expectedVersion": version, "operation": "upsert",
             "resourceType": "conversation", "resourceId": conversationID, "parentId": parentID, "payload": payload],
            ["commandId": UUID().uuidString.lowercased(), "expectedVersion": 0, "operation": "upsert",
             "resourceType": "message", "resourceId": UUID().uuidString.lowercased(), "parentId": conversationID,
             "payload": ["schemaVersion": 1, "createdAt": timestamp, "role": "assistant", "kind": "text",
                         "text": "A second reply", "orderIndex": 1, "isInterrupted": false,
                         "tokenEstimate": 4, "deliveryOrigin": "proactive"]],
        ]
        let response = try await request("/v1/content/commands", base: base, token: token, body: ["commands": commands])
        let results = try XCTUnwrap(response["results"] as? [[String: Any]])
        XCTAssertEqual(results.compactMap { $0["status"] as? String }, ["applied", "applied"],
                       results.compactMap { $0["code"] as? String }.joined(separator: ", "))
    }

    private func request(_ path: String, base: String, token: String? = nil,
                         body: [String: Any]? = nil) async throws -> [String: Any] {
        let address = try XCTUnwrap(URL(string: base + path))
        var request = URLRequest(url: address)
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200, path)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
