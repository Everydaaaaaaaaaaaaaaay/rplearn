import XCTest

@MainActor
final class FavoriteSourceUITests: XCTestCase {
    func testSavedWordShowsOriginalContext() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = [
            "UI_TEST_SKIP_ONBOARDING": "1",
            "UI_TEST_REQUIRE_AUTHENTICATION": "0",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
            "UI_TEST_MARKETING_CAPTURE": "1",
            "UI_TEST_TAB": "favorites",
            "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9",
        ]
        app.launch()
        let source = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "当时的原句")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 20), app.debugDescription)
        source.tap()
        let sentence = app.staticTexts["A cosy café, a good book, and absolutely no alarm clocks."]
        XCTAssertTrue(sentence.waitForExistence(timeout: 5), app.debugDescription)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "favorites-original-context"
        attachment.lifetime = .keepAlways
        add(attachment)
        source.tap()
        XCTAssertTrue(sentence.waitForNonExistence(timeout: 5))
    }
}
