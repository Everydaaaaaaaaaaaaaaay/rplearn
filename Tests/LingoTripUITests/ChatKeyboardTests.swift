import XCTest

@MainActor
final class ChatKeyboardTests: XCTestCase {
    func testAutomaticReadingToggle() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
        app.launchEnvironment["UI_TEST_MARKETING_CAPTURE"] = "1"
        app.launchEnvironment["UI_TEST_NATIVE_CAPTURE"] = "chat"
        app.launch()
        defer { app.terminate() }
        let ruby = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Ruby Walker")).firstMatch
        XCTAssertTrue(ruby.waitForExistence(timeout: 15))
        ruby.tap()
        let toggle = app.buttons["chat.autoRead"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        XCTAssertEqual(toggle.value as? String, "关闭")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "开启")
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Chat automatic reading enabled"
        image.lifetime = .keepAlways
        add(image)
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "关闭")
    }

    func testDismissKeyboardPreservesDraft() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
        app.launchEnvironment["UI_TEST_TAB"] = "contacts"
        app.launch()
        defer { app.terminate() }
        let contact = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Oliver")).firstMatch
        XCTAssertTrue(contact.waitForExistence(timeout: 15), app.debugDescription)
        contact.tap()
        let message = app.buttons["发消息"]
        XCTAssertTrue(message.waitForExistence(timeout: 5), app.debugDescription)
        message.tap()
        let field = app.descendants(matching: .any)["chat.composer"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        field.typeText("what should we")
        let list = app.scrollViews["chat.messages"]
        XCTAssertTrue(list.exists)
        // ScrollView's AX frame can include offscreen content; choose the visible viewport.
        let blankY = (app.navigationBars.firstMatch.frame.maxY + field.frame.minY) / 2
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.width * 0.92, dy: blankY)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertEqual(field.value as? String, "what should we")
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Chat keyboard dismiss control"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["chat.dismissKeyboard"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertEqual(field.value as? String, "what should we")
    }
}
