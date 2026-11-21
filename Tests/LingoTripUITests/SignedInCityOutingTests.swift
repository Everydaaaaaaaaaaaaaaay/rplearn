import XCTest

@MainActor
final class SignedInCityOutingTests: XCTestCase {
    func testResumesOtherDevicesOutingAfterSelectingAnotherPlace() async throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        guard let url = environment["LINGOTRIP_NATIVE_CITY_URL"],
              let baseURL = URL(string: url), baseURL.host == "127.0.0.1",
              let email = environment["LINGOTRIP_NATIVE_CITY_EMAIL"],
              let password = environment["LINGOTRIP_NATIVE_CITY_PASSWORD"] else {
            throw XCTSkip("Requires an isolated API with a fresh London account and the published activity world")
        }
        let app = XCUIApplication()
        app.launchEnvironment = [
            "LINGOTRIP_BACKEND_URL": url,
            "UI_TEST_REQUIRE_AUTHENTICATION": "1",
            "UI_TEST_SKIP_ONBOARDING": "1",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
            "UI_TEST_OUTING_AUDIO": "0",
        ]
        app.launch()
        defer { app.terminate() }

        let signIn = app.buttons["使用邮箱登录或注册"]
        let profileTab = app.tabBars.buttons["我的"]
        if profileTab.waitForExistence(timeout: 5) {
            signOut(app)
            XCTAssertTrue(signIn.waitForExistence(timeout: 12))
            app.terminate()
            app.launch()
        }
        XCTAssertTrue(signIn.waitForExistence(timeout: 20))
        signIn.tap()
        let address = app.textFields["邮箱"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        address.tap()
        address.typeText(email)
        let secret = app.secureTextFields["密码"]
        secret.tap()
        secret.typeText(password)
        let submit = app.buttons["auth.submitCredentials"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        if !submit.isHittable { app.scrollViews.firstMatch.swipeUp() }
        submit.tap()

        let activities = app.tabBars.buttons["活动"]
        XCTAssertTrue(activities.waitForExistence(timeout: 30))
        let savePasswordLater = app.buttons.matching(
            NSPredicate(format: "label IN %@", ["以后", "Not Now"])
        ).firstMatch
        if savePasswordLater.waitForExistence(timeout: 3) { savePasswordLater.tap() }
        activities.tap()
        if !activities.wait(for: \.isSelected, toEqual: true, timeout: 3) { activities.tap() }
        let open = app.buttons["home.activities"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        let riverside = app.buttons["activities.place.london-southbank"]
        XCTAssertTrue(riverside.waitForExistence(timeout: 12))

        let login = try await request("/v1/auth/login", at: baseURL, body: [
            "email": email, "password": password,
            "device": ["deviceId": UUID().uuidString, "platform": "ios"],
        ])
        let token = try XCTUnwrap(login["accessToken"] as? String)
        let world = try await request("/v2/activity-world", at: baseURL, token: token)
        let catalog = try XCTUnwrap(world["catalog"] as? [String: Any])
        let releaseID = try XCTUnwrap(catalog["releaseId"] as? String)
        let originalRunID = UUID().uuidString.lowercased()
        let placeID = "london-bloomsbury-cafe"
        let reserved = try await request("/v2/outings", at: baseURL, token: token, body: [
            "runId": originalRunID, "releaseId": releaseID, "placeId": placeID,
        ])
        XCTAssertEqual(reserved["runId"] as? String, originalRunID)
        riverside.tap()

        XCTAssertTrue(app.staticTexts["另一台设备已有外出进度，请返回地点页恢复。"].waitForExistence(timeout: 10))
        let back = app.buttons["返回地点页"]
        XCTAssertTrue(back.exists)
        back.tap()
        let resume = app.buttons["activities.resumePlaceOuting"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["继续上次在布卢姆茨伯里咖啡馆的外出"].exists)
        resume.tap()
        XCTAssertTrue(app.buttons["activities.action.next"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["布卢姆茨伯里咖啡馆"].exists)
        let active = try await request("/v2/outings/active", at: baseURL, token: token)
        XCTAssertEqual((active["outing"] as? [String: Any])?["runId"] as? String, originalRunID)
        let restored = XCTAttachment(screenshot: app.screenshot())
        restored.name = "Resumed the original city outing after a device conflict"
        restored.lifetime = .keepAlways
        add(restored)

        app.buttons["activities.action.back"].tap()
        XCTAssertTrue(resume.waitForExistence(timeout: 8))
        resume.tap()
        let menu = app.buttons["外出选项"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        let endAction = app.buttons.matching(NSPredicate(
            format: "label == %@ AND identifier != %@", "结束这次外出", "activities.action.next"
        )).firstMatch
        XCTAssertTrue(endAction.waitForExistence(timeout: 5))
        endAction.tap()
        let confirmation = app.buttons.matching(identifier: "activities.abandon.confirm").firstMatch
        if confirmation.waitForExistence(timeout: 3) {
            confirmation.tap()
        } else {
            endAction.tap()
        }
        let home = app.buttons["activities.back"]
        XCTAssertTrue(home.waitForExistence(timeout: 15))
        XCTAssertFalse(resume.exists, "The ended outing must not reappear as resumable")
        let afterEnding = try await request("/v2/outings/active", at: baseURL, token: token)
        XCTAssertTrue(afterEnding["outing"] is NSNull, "The server must acknowledge the end before returning")
        home.tap()
        XCTAssertTrue(open.waitForExistence(timeout: 8))
        open.tap()
        XCTAssertTrue(riverside.waitForExistence(timeout: 10))
        XCTAssertFalse(resume.exists)
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        home.tap()
        signOut(app)
        XCTAssertTrue(signIn.waitForExistence(timeout: 12))
    }

    private func signOut(_ app: XCUIApplication) {
        let profileTab = app.tabBars.buttons["我的"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 5))
        profileTab.tap()
        let profile = app.buttons["me.profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        profile.tap()
        let signOut = app.buttons["退出登录"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 5))
        signOut.tap()
    }

    private func request(_ path: String, at baseURL: URL, token: String? = nil,
                         body: [String: Any]? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: try XCTUnwrap(URL(string: path, relativeTo: baseURL)))
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
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
