import XCTest

@MainActor
final class ChatLearningSwipeTests: XCTestCase {
    func testLearningPageFollowsSwipeAndReturnsToChat() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = [
            "UI_TEST_SKIP_ONBOARDING": "1",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
            "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9",
            "UI_TEST_TAB": "contacts"
        ]
        app.launch()
        defer { app.terminate() }

        let contact = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Oliver")).firstMatch
        XCTAssertTrue(contact.waitForExistence(timeout: 15))
        contact.tap()
        let message = app.buttons["发消息"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        message.tap()
        XCTAssertTrue(app.scrollViews["chat.messages"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["chat.unitLearning.open"].exists)
        XCTAssertTrue(app.buttons["chat.unitLearning.debugFill"].exists)

        let viewport = app.scrollViews["chat.messages"]
        let start = viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.45))
        let finish = viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.45))
        start.press(forDuration: 0.1, thenDragTo: finish)
        XCTAssertTrue(app.staticTexts["登录后开启学习页"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["unitLearning.backToChat"].exists)

        let backStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.45))
        let backFinish = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.45))
        backStart.press(forDuration: 0.1, thenDragTo: backFinish)
        XCTAssertTrue(app.scrollViews["chat.messages"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["unitLearning.backToChat"].exists)
    }
}
