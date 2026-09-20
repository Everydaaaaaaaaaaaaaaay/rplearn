import XCTest

/// Uses the shipped dictionary and real production translation resolver.
/// Run explicitly: creates a small number of paid, shared-cache translations.
@MainActor
final class DictionaryExampleFlowTests: XCTestCase {
    func testTargetWordExamplesAndLiveTranslations() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_LIVE_DICTIONARY_E2E"] == "1", "Explicit live-provider opt-in required")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = [
            "UI_TEST_SKIP_ONBOARDING": "1",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
            "UI_TEST_WELCOME_CAPTURE": "1",
            "UI_TEST_DICTIONARY_EXAMPLES": "1",
            "UI_TEST_TAB": "contacts",
            "LINGOTRIP_BACKEND_URL": "https://rplearn.haruyuki.cn"
        ]
        app.launch()
        defer { app.terminate() }
        let ruby = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Ruby")).firstMatch
        XCTAssertTrue(ruby.waitForExistence(timeout: 25))
        ruby.tap()
        let chat = app.buttons["发消息"]
        XCTAssertTrue(chat.waitForExistence(timeout: 5))
        chat.tap()
        let just = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Just")).firstMatch
        XCTAssertTrue(just.waitForExistence(timeout: 10))
        just.tap()
        XCTAssertTrue(app.descendants(matching: .any)["dict.example.I've just finished my coffee."].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["dict.example.I was merely asking"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["dict.example.it is simply a matter of time"].firstMatch.exists)
        for sentence in ["I've just finished my coffee.", "I'm just looking, thank you."] {
            let row = app.descendants(matching: .any)["dict.example." + sentence].firstMatch
            XCTAssertTrue(row.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND NOT (label CONTAINS %@)", "中文翻译：", "加载中")).firstMatch.waitForExistence(timeout: 120), app.debugDescription)
        }
        capture("just-target-examples", app)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.3)).tap()
        let which = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Which")).firstMatch
        XCTAssertTrue(which.waitForExistence(timeout: 5))
        which.tap()
        XCTAssertTrue(app.descendants(matching: .any)["dict.example.Which would you prefer, tea or coffee?"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        for sentence in ["Which would you prefer, tea or coffee?", "My bike, which I bought last year, needs a new tyre."] {
            let row = app.descendants(matching: .any)["dict.example." + sentence].firstMatch
            XCTAssertTrue(row.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND NOT (label CONTAINS %@)", "中文翻译：", "加载中")).firstMatch.waitForExistence(timeout: 120), app.debugDescription)
        }
        capture("which-learner-examples", app)
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
