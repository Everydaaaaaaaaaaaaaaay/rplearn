import XCTest

@MainActor
final class TabHubTests: XCTestCase {
    func testAllCitiesUseProfileDrivenHubScenes() {
        continueAfterFailure = false
        let cities = [("london", "伦敦"), ("newyork", "纽约"), ("melbourne", "墨尔本"),
                      ("capetown", "开普敦"), ("singapore", "新加坡"), ("dublin", "都柏林"),
                      ("edinburgh", "爱丁堡"), ("vancouver", "温哥华"), ("auckland", "奥克兰"),
                      ("nairobi", "内罗毕"), ("toronto", "多伦多"), ("sydney", "悉尼"),
                      ("neworleans", "新奥尔良"), ("manchester", "曼彻斯特"), ("kingston", "金斯敦")]
        for (city, name) in cities {
            let app = launch(city: city)
            XCTAssertTrue(app.buttons["home.activities"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", "当前驻地，", name)).firstMatch.exists)
            capture(app, name: "hub-\(city)-activities")
            app.tabBars.buttons["我的"].tap()
            let profile = app.buttons["me.profile"]
            XCTAssertTrue(profile.waitForExistence(timeout: 10))
            let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", name), object: profile)
            XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 5), .completed)
            XCTAssertTrue(profile.isHittable)
            capture(app, name: "hub-\(city)-profile")
            app.terminate()
        }
    }

    func testHubRoutes() {
        continueAfterFailure = false
        let app = launch(city: "london")
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["home.activities"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons["home.activities"].label, "出去走走")
        XCTAssertTrue(app.staticTexts["home.cityName"].exists)
        capture(app, name: "hub-london-activities-entrance")
        app.swipeUp()
        XCTAssertTrue(app.buttons["世界地图"].isHittable)
        capture(app, name: "hub-london-activities-map")
        app.swipeDown()
        app.buttons["home.activities"].tap()
        XCTAssertTrue(app.buttons["activities.back"].waitForExistence(timeout: 5))
        app.buttons["activities.back"].tap()
        app.buttons["home.appointments"].tap()
        XCTAssertTrue(app.buttons["appointment.signIn.close"].waitForExistence(timeout: 5))
        app.buttons["appointment.signIn.close"].tap()
        XCTAssertTrue(app.buttons["appointment.signIn.close"].waitForNonExistence(timeout: 5))
        app.tabBars.buttons["我的"].tap()
        for id in ["me.profile", "me.favorites"] {
            let entry = app.buttons[id]
            if !entry.isHittable { app.swipeUp() }
            entry.tap()
            XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 5))
            if id == "me.profile" {
                XCTAssertFalse(app.staticTexts["AI 积分"].exists)
                XCTAssertFalse(app.buttons["积分余额与明细"].exists)
            }
            app.navigationBars.buttons.firstMatch.tap()
        }
        XCTAssertFalse(app.descendants(matching: .any)["me.memory"].exists)
        for id in ["me.coinBalance", "me.credits"] {
            XCTAssertFalse(app.buttons[id].exists)
            let balance = app.descendants(matching: .any)[id].firstMatch
            XCTAssertTrue(balance.exists)
            if !balance.isHittable { app.swipeUp() }
            XCTAssertTrue(balance.isHittable)
            XCTAssertFalse(balance.label.isEmpty)
            balance.tap()
            XCTAssertTrue(app.buttons["me.profile"].exists)
            XCTAssertFalse(app.navigationBars["个人资料"].exists)
            XCTAssertFalse(app.navigationBars["积分余额与明细"].exists)
        }
        capture(app, name: "hub-london-profile-readonly-balances")
        let settings = app.buttons["me.settings"]
        XCTAssertEqual(app.buttons.matching(identifier: "设置，AI、语音与偏好").count, 1)
        XCTAssertGreaterThan(settings.frame.width, app.frame.width * 0.8)
        XCTAssertGreaterThanOrEqual(settings.frame.height, 60)
        XCTAssertGreaterThan(settings.frame.minY, app.buttons["me.favorites"].frame.minY)
        settings.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["me.learning-trial"].exists)
    }

    func testAccessibilityLayouts() {
        continueAfterFailure = false
        let app = launch(city: "london", contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        defer { app.terminate() }
        let city = app.buttons["home.activities"]
        XCTAssertTrue(city.waitForExistence(timeout: 15))
        if !city.isHittable { app.swipeUp() }
        XCTAssertTrue(city.isHittable)
        XCTAssertGreaterThanOrEqual(city.frame.height, 44)
        XCTAssertEqual(city.label, "出去走走")
        XCTAssertTrue(app.staticTexts["home.cityName"].exists)
        capture(app, name: "hub-london-activities-accessibility")
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(app.buttons["世界地图"].isHittable)
        capture(app, name: "hub-london-activities-accessibility-bottom")
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.buttons["me.profile"].waitForExistence(timeout: 10))
        capture(app, name: "hub-london-profile-accessibility")
        let settings = app.buttons["me.settings"]
        for _ in 0..<5 where !settings.isHittable { app.swipeUp() }
        XCTAssertTrue(settings.isHittable)
        XCTAssertGreaterThan(settings.frame.width, app.frame.width * 0.8)
        capture(app, name: "hub-london-profile-settings-accessibility")
        settings.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.swipeUp()
        app.swipeUp()
        XCTAssertFalse(app.buttons["me.coinBalance"].exists)
        XCTAssertFalse(app.buttons["me.credits"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["me.coinBalance"].firstMatch.isHittable)
        let credits = app.descendants(matching: .any)["me.credits"].firstMatch
        if !credits.isHittable { app.swipeUp() }
        XCTAssertTrue(credits.isHittable)
        capture(app, name: "hub-london-profile-accessibility-bottom")
    }

    func testHeaderContrastAndDarkAppearance() {
        for (city, cityName, appearance) in [("capetown", "开普敦", "light"), ("manchester", "曼彻斯特", "light"),
                                             ("newyork", "纽约", "light"), ("sydney", "悉尼", "light"), ("london", "伦敦", "dark")] {
            let app = launch(city: city, appearance: appearance)
            XCTAssertTrue(app.buttons["home.activities"].waitForExistence(timeout: 15))
            XCTAssertEqual(app.buttons["home.activities"].label, "出去走走")
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(
                format: "label BEGINSWITH %@ AND label ENDSWITH %@", "当前驻地，", cityName
            )).firstMatch.exists)
            capture(app, name: "hub-\(city)-activities-\(appearance)")
            app.tabBars.buttons["我的"].tap()
            let profile = app.buttons["me.profile"]
            XCTAssertTrue(profile.waitForExistence(timeout: 10))
            let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", cityName), object: profile)
            XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 5), .completed)
            capture(app, name: "hub-\(city)-profile-\(appearance)")
            app.terminate()
        }
    }

    private func launch(city: String, contentSize: String? = nil, appearance: String = "light") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_WELCOME_CAPTURE": "1",
            "UI_TEST_WORLD_GATEWAY": "1", "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
            "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9",
            "UI_TEST_CITY_TAB_REGION": city, "UI_TEST_TAB": "home",
            "UI_TEST_CAPTURE_APPEARANCE": appearance
        ]
        app.launchEnvironment["UI_TEST_ACTIVITY_NAMESPACE"] = UUID().uuidString
        if let category = contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", category]
        }
        app.launch()
        return app
    }

    private func capture(_ app: XCUIApplication, name: String) {
        // Wait for the transition to settle before recording the native composition.
        XCTAssertTrue(app.tabBars.firstMatch.isHittable)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
