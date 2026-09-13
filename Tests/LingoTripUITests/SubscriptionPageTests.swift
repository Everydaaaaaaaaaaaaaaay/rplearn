import XCTest

@MainActor
final class SubscriptionPageTests: XCTestCase {
    func testMembershipPageAndUnavailablePrice() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["UI_TEST_TAB"] = "me"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
        app.launch()
        let entry = app.buttons["me.subscription"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        entry.tap()
        XCTAssertTrue(app.staticTexts["咕游记会员"].waitForExistence(timeout: 5))
        let purchase = app.buttons["subscription.purchase"]
        XCTAssertTrue(purchase.exists)
        XCTAssertFalse(purchase.isEnabled, "未加载真实价格时不能购买")
        XCTAssertFalse(app.scrollViews["subscription.content"].staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "金币", "积分")).firstMatch.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "会员订阅页"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.swipeUp()
        XCTAssertTrue(app.buttons["subscription.restore"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["subscription.reload"].exists)
    }
    func testPlanSelectionPreview() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["UI_TEST_TAB"] = "subscription"
        app.launchEnvironment["UI_TEST_SUBSCRIPTION_PRICES"] = "1"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
        app.launch()
        XCTAssertTrue(app.staticTexts["咕游记会员"].waitForExistence(timeout: 15))
        app.swipeUp()
        let pro = app.buttons["subscription.plan.pro"]
        XCTAssertTrue(pro.waitForExistence(timeout: 5))
        pro.tap()
        XCTAssertTrue(app.buttons["subscription.purchase"].label.contains("Pro"))
        XCTAssertFalse(app.buttons["subscription.purchase"].isEnabled)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "会员方案选择（示例价格）"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

}
