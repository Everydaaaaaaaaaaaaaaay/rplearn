import XCTest

@MainActor
final class ComposerTranslatorUITests: XCTestCase {
    func testPanelSwitchingPreservesDraftAndCompactLayout() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1", "UI_TEST_WELCOME_CAPTURE": "1",
            "UI_TEST_TAB": "contacts", "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9"]
        app.launch()
        let ruby = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Ruby")).firstMatch
        XCTAssertTrue(ruby.waitForExistence(timeout: 25)); ruby.tap()
        XCTAssertTrue(app.buttons["发消息"].waitForExistence(timeout: 5)); app.buttons["发消息"].tap()
        let toggle = app.buttons["chat.translator.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        capture("composer-normal", app)
        let english = app.descendants(matching: .any)["chat.composer"].firstMatch
        english.tap(); english.typeText("Yes, please send me the name.")
        app.buttons["chat.dismissKeyboard"].tap()
        toggle.tap()
        Thread.sleep(forTimeInterval: 0.7)
        assertLatestMessageVisible(app)
        let source = app.descendants(matching: .any)["chat.translator.source"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        app.buttons["AI"].tap()
        source.tap(); source.typeText("可以呀，把名字发给我吧。")
        // Closing and reopening preserves drafts and resigns source focus.
        toggle.tap()
        Thread.sleep(forTimeInterval: 0.7)
        toggle.tap()
        Thread.sleep(forTimeInterval: 0.7)
        XCTAssertTrue(String(describing: english.value).contains("Yes, please"))
        capture("composer-translator", app)
        assertLatestMessageVisible(app)

        XCTAssertTrue(app.buttons["翻译"].exists)
        // The edge beside bubbles is blank chat background, not a word/button target.
        let blankY = app.buttons["即时"].frame.minY - 110
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.width - 3, dy: blankY)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertTrue(source.exists)
        XCTAssertTrue(String(describing: source.value).contains("可以呀"))

        for _ in 0..<3 { toggle.tap(); toggle.tap() }
        XCTAssertTrue(source.exists)
        XCTAssertTrue(String(describing: source.value).contains("可以呀"))
        toggle.tap()
        XCTAssertFalse(source.isEnabled)
        XCTAssertEqual(toggle.label, "打开翻译器")
    }

    private func assertLatestMessageVisible(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let latest = app.descendants(matching: .any)["chat.message.latest"].firstMatch
        XCTAssertTrue(latest.waitForExistence(timeout: 5), file: file, line: line)
        let mode = app.buttons["即时"]
        XCTAssertLessThanOrEqual(latest.frame.maxY, mode.frame.minY - 4,
            "Latest message must remain above the expanded composer", file: file, line: line)
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
