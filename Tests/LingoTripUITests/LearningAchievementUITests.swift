import XCTest

@MainActor
final class LearningAchievementUITests: XCTestCase {
    func testReplayFirstMultipleAndNinthStarAndPromotion() {
        let app = launch(tab: "achievement-preview")
        let play = app.buttons["learning.achievement.play-star"]
        XCTAssertTrue(play.waitForExistence(timeout: 12))
        let stars = app.descendants(matching: .any)["learning.achievement.stars"].firstMatch
        play.tap(); waitForValue("4/9", element: stars)
        waitForReplay(play); capture(app, "升星落槽完成")
        play.tap(); waitForReplay(play); waitForValue("4/9", element: stars)
        app.buttons["learning.achievement.play-multiple"].tap()
        waitForReplay(play); waitForValue("6/9", element: stars)
        let picker = app.segmentedControls.firstMatch
        if !picker.isHittable { app.swipeUp() }
        picker.buttons.element(boundBy: 0).tap()
        play.tap(); waitForReplay(play); waitForValue("1/9", element: stars)
        if !picker.isHittable { app.swipeUp() }
        picker.buttons.element(boundBy: 2).tap()
        play.tap(); waitForReplay(play); waitForValue("9/9", element: stars)
        capture(app, "第九颗星完成")
        for index in 0..<2 {
            app.buttons["learning.achievement.play-promotion"].tap()
            let next = app.buttons["learning.promotion.begin-journey"]
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["大学英语四级"].waitForExistence(timeout: 5))
            if index == 0 {
                XCTAssertTrue(app.buttons["learning.promotion.skip"].waitForNonExistence(timeout: 5))
                capture(app, "晋升新档位揭晓")
            }
            next.tap()
            XCTAssertTrue(play.waitForExistence(timeout: 5))
        }
    }

    func testLargeTextPromotionAndStarControlsRemainAccessible() {
        let app = launch(tab: "achievement-preview", large: true)
        let play = app.buttons["learning.achievement.play-star"]
        XCTAssertTrue(play.waitForExistence(timeout: 12))
        XCTAssertTrue(play.isHittable)
        play.tap(); waitForReplay(play)
        app.buttons["learning.achievement.play-promotion"].tap()
        let next = app.buttons["learning.promotion.begin-journey"]
        XCTAssertTrue(next.waitForExistence(timeout: 5)); XCTAssertTrue(next.isHittable)
        XCTAssertTrue(app.buttons["learning.promotion.skip"].waitForNonExistence(timeout: 5))
        capture(app, "晋升最大辅助字号")
        next.tap(); XCTAssertTrue(play.waitForExistence(timeout: 5))
    }

    func testPromotionConfirmationFlowUsesTheSavedResult() {
        let app = launch(tab: "promotion-preview")
        let advance = app.buttons["learning.promotion.continue"]
        XCTAssertTrue(advance.waitForExistence(timeout: 12))
        reveal(advance, in: app); advance.tap()
        XCTAssertTrue(advance.waitForExistence(timeout: 5)); reveal(advance, in: app); advance.tap()
        let confirm = app.buttons["learning.promotion.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); reveal(confirm, in: app); confirm.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["继续保留当前水平"].tap()
        XCTAssertFalse(app.staticTexts["晋升完成"].exists)
        confirm.tap(); alert.buttons["确认进入下一水平"].tap()
        XCTAssertTrue(app.buttons["learning.promotion.begin-journey"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["小学四年级"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["learning.promotion.skip"].waitForNonExistence(timeout: 5))
        capture(app, "服务确认后的晋升仪式")
    }

    func testPreviewIsReachableFromLearningTrial() {
        let app = launch(tab: "me")
        let entry = app.buttons["me.learning-trial"]
        XCTAssertTrue(entry.waitForExistence(timeout: 12)); reveal(entry, in: app); entry.tap()
        let preview = app.buttons["learning.trial.achievement-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 8))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: preview)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 8), .completed)
        preview.tap()
        XCTAssertTrue(app.buttons["learning.achievement.play-star"].waitForExistence(timeout: 5))
        capture(app, "学习实测中的动效入口")
    }

    private func launch(tab: String, large: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_TEST_REQUIRE_AUTHENTICATION": "0", "UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
            "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9", "UI_TEST_TAB": tab]
        if large { app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch(); addTeardownBlock { app.terminate() }; return app
    }
    private func waitForValue(_ value: String, element: XCUIElement) {
        let condition = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [condition], timeout: 6), .completed)
    }
    private func waitForReplay(_ button: XCUIElement) {
        let condition = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "播放升星"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [condition], timeout: 6), .completed)
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.isHittable { return }; app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
