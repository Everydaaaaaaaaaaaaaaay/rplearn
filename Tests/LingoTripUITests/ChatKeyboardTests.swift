import XCTest

@MainActor
final class ChatKeyboardTests: XCTestCase {
    func testAutomaticReadingToggle() throws {
        continueAfterFailure = false
        var steps: [String] = []
        let evidence = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("chat-header-controls", isDirectory: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        defer {
            let result: [String: Any] = ["steps": steps, "failures": testRun?.failureCount ?? -1,
                "completed": steps.last == "learning-avatar-settings"]
            try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                .write(to: evidence.appendingPathComponent("result.json"))
        }
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
        XCTAssertFalse(app.buttons["chat.more"].exists)
        let toggle = app.buttons["chat.autoRead"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        XCTAssertEqual(toggle.value as? String, "开启")
        XCTAssertTrue(toggle.isHittable)
        XCTAssertTrue(toggle.label.contains("关闭自动朗读"))
        steps.append("default-on-visible-controls")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "关闭")
        app.terminate()
        app.launch()
        XCTAssertTrue(ruby.waitForExistence(timeout: 15))
        ruby.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "关闭", "重新进入聊天应保留手动关闭的选择")
        steps.append("off-preference-survives-relaunch")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "开启")
        app.buttons["chat.localTime"].tap()
        let clock = app.staticTexts["墨尔本当地时间"]
        XCTAssertTrue(clock.waitForExistence(timeout: 3))
        steps.append("local-time-popover")
        try app.screenshot().pngRepresentation.write(to: evidence.appendingPathComponent("clock.png"))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)).tap()
        XCTAssertTrue(clock.waitForNonExistence(timeout: 3))
        let headerImage = XCTAttachment(screenshot: app.screenshot())
        headerImage.name = "Visible chat header controls and compact online status"
        headerImage.lifetime = .keepAlways
        add(headerImage)
        try app.screenshot().pngRepresentation.write(to: evidence.appendingPathComponent("header.png"))
        app.buttons["chat.settings"].tap()
        XCTAssertTrue(app.navigationBars["聊天设置"].waitForExistence(timeout: 3))
        steps.append("direct-settings")
        app.buttons["完成"].tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.35))
            .press(forDuration: 0.08, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.35)))
        let avatar = app.buttons["learning.character.settings"]
        XCTAssertTrue(avatar.waitForExistence(timeout: 5))
        avatar.tap()
        XCTAssertTrue(app.navigationBars["聊天设置"].waitForExistence(timeout: 3))
        try app.screenshot().pngRepresentation.write(to: evidence.appendingPathComponent("learning-settings.png"))
        steps.append("learning-avatar-settings")
        app.buttons["完成"].tap()
        XCTAssertTrue(avatar.waitForExistence(timeout: 3))
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Learning avatar opens chat settings"
        image.lifetime = .keepAlways
        add(image)
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
