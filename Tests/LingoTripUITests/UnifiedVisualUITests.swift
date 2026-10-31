import XCTest

@MainActor
final class UnifiedVisualUITests: XCTestCase {
    private func launch(tab: String = "messages", large: Bool = false, dark: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_REQUIRE_AUTHENTICATION": "0",
                                 "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1", "UI_TEST_TAB": tab,
                                 "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9"]
        if dark { app.launchEnvironment["UI_TEST_CAPTURE_APPEARANCE"] = "dark" }
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        return app
    }
    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testRootsSearchProfileAndSettingsKeepRealNavigation() {
        let app = launch()
        defer { app.terminate() }
        let field = app.textFields["sceneSearch.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        capture("unified-messages", app)
        field.tap(); field.typeText("Oliver")
        app.buttons["sceneSearch.dismissKeyboard"].tap()
        XCTAssertEqual(field.value as? String, "Oliver")
        app.buttons["sceneSearch.clear"].tap()
        app.mainTabButtons["联系人"].tap()
        XCTAssertTrue(app.mainTabButtons["联系人"].isSelected)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        capture("unified-contacts", app)
        let friend = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Oliver")).firstMatch
        XCTAssertTrue(friend.waitForExistence(timeout: 10)); friend.tap()
        XCTAssertTrue(app.buttons["发消息"].waitForExistence(timeout: 5))
        capture("unified-person", app)
        app.mainTabButtons["联系人"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.mainTabButtons["我的"].tap()
        XCTAssertTrue(app.buttons["me.profile"].waitForExistence(timeout: 5))
        capture("unified-me", app)
        app.buttons["me.settings"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["settings.proactive"].exists)
        capture("unified-settings", app)
        app.mainTabButtons["我的"].tap()
        XCTAssertTrue(app.buttons["me.profile"].waitForExistence(timeout: 5))
        app.mainTabButtons["活动"].tap()
        XCTAssertTrue(app.buttons["世界地图"].waitForExistence(timeout: 10))
        capture("unified-home", app)
        app.buttons["世界地图"].tap()
        let mapBack = app.buttons["返回首页"]
        XCTAssertTrue(mapBack.waitForExistence(timeout: 10))
        XCTAssertFalse(app.mainTabButtons["活动"].exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        capture("unified-map", app)
        mapBack.tap()
        XCTAssertTrue(app.mainTabButtons["活动"].waitForExistence(timeout: 5))
        let story = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "剧情，")).firstMatch
        XCTAssertTrue(story.exists); story.tap()
        XCTAssertTrue(app.buttons["story.mainline"].waitForExistence(timeout: 5))
        capture("unified-stories", app)
    }
    func testLargeTextMyPageAndSettingsStayReachable() {
        let app = launch(tab: "me", large: true)
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["me.settings"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["me.settings"].isHittable)
        capture("unified-me-large", app)
        app.buttons["me.settings"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["settings.proactive"].waitForExistence(timeout: 5))
        capture("unified-settings-large", app)
    }

    func testDarkSubscriptionFavoritesAndSignInStayReadable() {
        let app = launch(tab: "subscription", dark: true)
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["subscription.purchase"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["subscription.purchase"].isEnabled)
        capture("unified-subscription-dark", app)
        app.mainTabButtons["我的"].tap()
        app.buttons["收藏夹，单词与语法点"].tap()
        let search = app.buttons["搜索收藏"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        XCTAssertTrue(app.buttons["取消搜索"].waitForExistence(timeout: 5))
        capture("unified-favorites-dark", app)
        app.buttons["取消搜索"].tap()

        app.terminate()
        app.launchEnvironment["UI_TEST_REQUIRE_AUTHENTICATION"] = "1"
        app.launchEnvironment["UI_TEST_FORCE_SIGNED_OUT"] = "1"
        app.launch()
        let emailEntry = app.buttons["使用邮箱登录或注册"]
        XCTAssertTrue(emailEntry.waitForExistence(timeout: 15))
        emailEntry.tap()
        let email = app.textFields["邮箱"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        email.tap(); email.typeText("visual-check@example.invalid")
        XCTAssertEqual(email.value as? String, "visual-check@example.invalid")
        capture("unified-signin-dark", app)
    }
}
