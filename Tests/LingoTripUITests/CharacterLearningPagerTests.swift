import XCTest

@MainActor
final class CharacterLearningPagerTests: XCTestCase {
    func testSwipePreservesDraftAndVerticalScrollStaysOnPage() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
        app.launch()
        defer { app.terminate() }
        let oliver = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Oliver Bennett")).firstMatch
        XCTAssertTrue(oliver.waitForExistence(timeout: 15)); oliver.tap()
        let composer = app.descendants(matching: .any)["chat.composer"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 8))
        composer.tap(); composer.typeText("my saved draft")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.35))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.35))
        start.press(forDuration: 0.08, thenDragTo: end)
        let page = app.descendants(matching: .any)["learning.character"].firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["角色学习"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["learning.character.identity"].firstMatch.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "聊天左滑后的角色学习页"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.swipeUp()
        XCTAssertTrue(page.exists)
        app.buttons["返回聊天"].tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 3)); XCTAssertEqual(composer.value as? String, "my saved draft")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertFalse(app.buttons["chat.learning"].exists)
        XCTAssertFalse(app.buttons["chat.debugFillLearning"].exists)
        app.buttons["chat.more"].tap()
        app.buttons["chat.debugFillLearning"].tap()
        XCTAssertTrue(page.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["learning.start"].waitForExistence(timeout: 5))
        let stars = app.descendants(matching: .any)["learning.achievement.stars"].firstMatch
        XCTAssertTrue(stars.waitForExistence(timeout: 5))
        stars.tap()
        XCTAssertFalse(app.navigationBars["学习进度"].exists)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let starY = stars.frame.midY
        origin.withOffset(CGVector(dx: stars.frame.maxX - 15, dy: starY))
            .press(forDuration: 0.08, thenDragTo: origin.withOffset(CGVector(dx: app.frame.width * 0.12, dy: starY)))
        XCTAssertTrue(app.buttons["返回聊天"].exists, "学习页向外横滑不应打开其他页面")
        XCTAssertFalse(app.navigationBars["学习进度"].exists)
        origin.withOffset(CGVector(dx: stars.frame.minX + 15, dy: starY))
            .press(forDuration: 0.08, thenDragTo: origin.withOffset(CGVector(dx: app.frame.width * 0.88, dy: starY)))
        XCTAssertTrue(composer.waitForExistence(timeout: 3))
        XCTAssertEqual(composer.value as? String, "my saved draft")
        XCTAssertFalse(app.navigationBars["学习进度"].exists)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        let returned = XCTAttachment(screenshot: app.screenshot())
        returned.name = "从星级区域横滑返回聊天并保留草稿"; returned.lifetime = .keepAlways; add(returned)
    }
}
