import XCTest

@MainActor
final class LearningJourneyNavigationTests: XCTestCase {
    func testLevelChangeRequiresConfirmationAndReturnsToJourney() {
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
        let journey = app.navigationBars["英语旅程"]
        XCTAssertTrue(journey.waitForExistence(timeout: 10))
        let adjust = app.buttons["learning.changeLevel"]
        XCTAssertTrue(adjust.waitForExistence(timeout: 5))
        let target = app.staticTexts["幼儿启蒙"].exists ? "primary1" : "kindergarten"
        let targetName = target == "primary1" ? "小学一年级" : "幼儿启蒙"
        if !adjust.isHittable { app.swipeUp() }
        let overview = XCTAttachment(screenshot: app.screenshot())
        overview.name = "英语旅程总览"; overview.lifetime = .keepAlways; add(overview)
        adjust.tap()
        let choice = app.buttons["placement.level.\(target)"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.tap()
        app.buttons["完成"].tap()
        let alert = app.alerts["确认切换英语水平"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "切换不会赠送学习点数、星星或解锁主线")).firstMatch.exists)
        let confirmation = XCTAttachment(screenshot: app.screenshot())
        confirmation.name = "水平切换强提醒"; confirmation.lifetime = .keepAlways; add(confirmation)
        alert.buttons["保持当前水平"].tap()
        XCTAssertTrue(choice.isHittable, "取消应留在选择页，不能保存新水平")
        app.buttons["完成"].tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["确认切换"].tap()
        XCTAssertTrue(journey.waitForExistence(timeout: 10), "确认保存后应返回英语旅程")
        XCTAssertTrue(app.staticTexts[targetName].waitForExistence(timeout: 5), "应读取刚保存的水平")
        if !adjust.isHittable { app.swipeUp() }
        adjust.tap()
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        XCTAssertTrue(journey.waitForExistence(timeout: 10), "相同水平无需再次弹出切换确认")
        XCTAssertFalse(alert.exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        XCTAssertTrue(journey.waitForNonExistence(timeout: 5))
        XCTAssertTrue(entry.isHittable)
    }
    func testMainlineShowsLockedRequirementsInDarkAppearance() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["UI_TEST_TAB"] = "learning"
        app.launchEnvironment["UI_TEST_CAPTURE_APPEARANCE"] = "dark"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
        app.launch()
        XCTAssertTrue(app.buttons["learning.changeLevel"].waitForExistence(timeout: 15))
        let secondChapter = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "故事是谁的")).firstMatch
        for _ in 0..<4 {
            if secondChapter.exists && secondChapter.frame.maxY < app.frame.maxY - 100 { break }
            app.swipeUp()
        }
        XCTAssertTrue(secondChapter.exists)
        XCTAssertFalse(secondChapter.isEnabled, "未满足星星与前章要求时不可播放")
        XCTAssertTrue(secondChapter.label.contains("先完成前一章"))
        XCTAssertTrue(secondChapter.label.contains("累计 3 星"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "深色英语旅程主线门槛"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

}
