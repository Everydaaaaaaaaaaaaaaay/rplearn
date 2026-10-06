import XCTest

@MainActor
final class LearningJourneyNavigationTests: XCTestCase {
    func testLevelChangeRequiresConfirmationAndReturnsToProfile() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["UI_TEST_TAB"] = "me"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
        app.launch()
        let entry = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "英语旅程，")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        entry.tap()
        let journey = app.navigationBars["英语水平校准"]
        XCTAssertTrue(journey.waitForExistence(timeout: 10))
        let adjust = app.buttons["placement.chooseLevel"]
        XCTAssertTrue(adjust.waitForExistence(timeout: 5))
        let target = app.staticTexts["幼儿启蒙"].exists ? "primary1" : "kindergarten"
        let targetName = target == "primary1" ? "小学一年级" : "幼儿启蒙"
        if !adjust.isHittable { app.swipeUp() }
        let overview = XCTAttachment(screenshot: app.screenshot())
        overview.name = "英语水平选择与校准"; overview.lifetime = .keepAlways; add(overview)
        adjust.tap()
        let choice = app.buttons["placement.level.\(target)"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.tap()
        app.buttons["完成"].tap()
        let alert = app.alerts["确认切换英语水平"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "切换不会赠送学习点数或星星")).firstMatch.exists)
        let confirmation = XCTAttachment(screenshot: app.screenshot())
        confirmation.name = "水平切换强提醒"; confirmation.lifetime = .keepAlways; add(confirmation)
        alert.buttons["保持当前水平"].tap()
        XCTAssertTrue(choice.isHittable, "取消应留在选择页，不能保存新水平")
        app.buttons["完成"].tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["确认切换"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "确认保存后应返回我的页面")
        XCTAssertTrue(entry.label.contains(targetName), "应读取刚保存的水平")
        entry.tap()
        XCTAssertTrue(adjust.waitForExistence(timeout: 5))
        adjust.tap()
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "相同水平无需再次弹出切换确认")
        XCTAssertFalse(alert.exists)
    }
    func testJourneyRestoresPlacementWithoutMainlineOrStars() {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["UI_TEST_TAB"] = "learning"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
        app.launch()
        XCTAssertTrue(app.buttons["placement.chooseLevel"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["开始水平测试"].exists)
        XCTAssertFalse(app.otherElements["learning.journey"].exists)
        XCTAssertFalse(app.staticTexts["故事的下一站"].exists)
    }
}
