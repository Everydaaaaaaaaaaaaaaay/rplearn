import XCTest

@MainActor
final class LearningRollbackUITests: XCTestCase {
    func testNormalChatHasNoRetiredLearningEntry() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = [
            "UI_TEST_SKIP_ONBOARDING": "1",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
            "UI_TEST_WELCOME_CAPTURE": "1",
            "UI_TEST_NATIVE_CAPTURE": "chat",
            "UI_TEST_TAB": "contacts",
            "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9",
        ]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["chat.composer"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["chat.learning.expand"].exists)
        XCTAssertFalse(app.buttons["chat.learning.details"].exists)
        XCTAssertFalse(app.buttons["chat.learning.practice"].exists)
    }
}
