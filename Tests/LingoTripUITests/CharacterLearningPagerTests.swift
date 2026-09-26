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
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "聊天左滑后的角色学习页"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.swipeUp()
        XCTAssertTrue(page.exists)
        app.buttons["chat.learning"].tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 3)); XCTAssertEqual(composer.value as? String, "my saved draft")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        app.buttons["chat.learning"].tap()
        XCTAssertTrue(page.waitForExistence(timeout: 3))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.35))
            .press(forDuration: 0.08, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.35)))
        XCTAssertTrue(composer.waitForExistence(timeout: 3))
        XCTAssertEqual(composer.value as? String, "my saved draft")
    }
}
