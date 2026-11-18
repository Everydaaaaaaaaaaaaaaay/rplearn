import XCTest

@MainActor
final class ChatKeyboardTests: XCTestCase {
    func testAutomaticReadingToggle() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = [
            "UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_WELCOME_CAPTURE": "1",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1", "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9",
            "UI_TEST_NATIVE_CAPTURE": "chat"
        ]
        app.launch()
        defer { app.terminate() }
        let functions = app.buttons["chat.functions"]
        XCTAssertTrue(functions.waitForExistence(timeout: 15))
        let field = app.descendants(matching: .any)["chat.composer"].firstMatch
        XCTAssertTrue(app.buttons["chat.settings"].isHittable)
        XCTAssertTrue(app.buttons["chat.autoRead"].isHittable)
        XCTAssertFalse(app.buttons["chat.send"].exists)
        XCTAssertFalse(app.buttons["chat.localTime"].exists)
        XCTAssertFalse(app.buttons["chat.detectAppointment"].exists)
        XCTAssertTrue(app.buttons["chat.identity"].label.contains("当地时间"))
        functions.tap()
        XCTAssertTrue(app.buttons["chat.call"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["chat.learningMode"].exists)
        XCTAssertFalse(app.buttons["chat.inputMode"].exists)
        XCTAssertEqual(functions.frame.midY, field.frame.midY, accuracy: 2)
        XCTAssertGreaterThan(app.buttons["chat.settings"].frame.maxY, 0)
        XCTAssertLessThan(app.buttons["chat.settings"].frame.maxY, app.navigationBars.firstMatch.frame.maxY + 2)
        XCTAssertLessThan(app.buttons["chat.autoRead"].frame.maxY, app.navigationBars.firstMatch.frame.maxY + 2)
        let menuImage = XCTAttachment(screenshot: app.screenshot())
        menuImage.name = "Chat composer function panel"
        menuImage.lifetime = .keepAlways
        add(menuImage)
        let toggle = app.buttons["chat.autoRead"]
        let previousValue = toggle.value as? String
        toggle.tap()
        XCTAssertNotEqual(toggle.value as? String, previousValue)
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, previousValue)
        app.buttons["chat.settings"].tap()
        XCTAssertTrue(app.navigationBars["聊天设置"].waitForExistence(timeout: 3))
        app.buttons["完成"].tap()
        field.tap()
        field.typeText("Keep this draft")
        XCTAssertTrue(app.buttons["chat.send"].waitForExistence(timeout: 3))
        XCTAssertFalse(functions.exists)
        let keyboardLayout = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            field.frame.maxY <= app.keyboards.firstMatch.frame.minY + 2
                && app.buttons["chat.send"].frame.maxY <= app.keyboards.firstMatch.frame.minY + 2
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardLayout], timeout: 3), .completed)
        let keyboardImage = XCTAttachment(screenshot: app.screenshot())
        keyboardImage.name = "Focused composer shows send action"
        keyboardImage.lifetime = .keepAlways
        add(keyboardImage)
        dismissKeyboard(in: app)
        XCTAssertTrue(functions.waitForExistence(timeout: 3))
        XCTAssertEqual(field.value as? String, "Keep this draft")
        app.buttons["切换到语音"].tap()
        XCTAssertTrue(app.buttons["切换到键盘"].waitForExistence(timeout: 3))
        app.buttons["切换到键盘"].tap()
        XCTAssertEqual(field.value as? String, "Keep this draft")
        functions.tap()
        app.buttons["chat.learningMode"].tap()
        XCTAssertTrue(app.buttons["返回聊天"].waitForExistence(timeout: 5))
        app.buttons["返回聊天"].tap()
        XCTAssertTrue(functions.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Keep this draft")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Chat header with inline time and composer function menu"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testFunctionPanelKeyboardHandoffBlankDismissalAndSettings() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = [
            "UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_WELCOME_CAPTURE": "1",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1", "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9",
            "UI_TEST_NATIVE_CAPTURE": "chat"
        ]
        app.launch()
        defer { app.terminate() }
        let field = app.descendants(matching: .any)["chat.composer"].firstMatch
        let functions = app.buttons["chat.functions"]
        let settings = app.buttons["chat.settings"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        let collapsedY = field.frame.minY
        field.tap()
        let visibleKeyboard = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.keyboards.firstMatch.exists && field.frame.minY < collapsedY - 100
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visibleKeyboard], timeout: 5), .completed)
        let keyboardY = field.frame.minY
        let keyboardImage = XCTAttachment(screenshot: app.screenshot())
        keyboardImage.name = "Keyboard and composer alignment"
        keyboardImage.lifetime = .keepAlways
        add(keyboardImage)
        // Keyboard AX bounds exclude the system suggestion bar above the keys.
        XCTAssertLessThan(field.frame.maxY, app.keyboards.firstMatch.frame.minY)
        let latest = app.descendants(matching: .any)["chat.message.latest"].firstMatch
        XCTAssertLessThan(latest.frame.maxY, field.frame.minY)
        let keyboardBubbleY = latest.frame.minY
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertEqual(latest.frame.minY, keyboardBubbleY, accuracy: 1, "键盘展开后不能再次补偿气泡位置")
        dismissKeyboard(in: app)
        XCTAssertEqual(field.frame.minY, collapsedY, accuracy: 2)

        for _ in 0..<2 {
            functions.tap()
            XCTAssertTrue(app.buttons["chat.call"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.buttons["chat.call"].isHittable)
            XCTAssertEqual(field.frame.minY, keyboardY, accuracy: 2, "功能面板复用本机键盘高度")
            XCTAssertEqual(functions.frame.midY, field.frame.midY, accuracy: 2)
            XCTAssertLessThan(latest.frame.maxY, field.frame.minY)
            let panelBubbleY = latest.frame.minY
            Thread.sleep(forTimeInterval: 0.4)
            XCTAssertEqual(latest.frame.minY, panelBubbleY, accuracy: 1, "面板展开后不能再次补偿气泡位置")
            functions.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
            XCTAssertEqual(field.frame.minY, keyboardY, accuracy: 2, "切换到键盘时保持展开位置")
            XCTAssertEqual(latest.frame.minY, panelBubbleY, accuracy: 2)
            dismissKeyboard(in: app)
            XCTAssertTrue(functions.waitForExistence(timeout: 3))
            XCTAssertEqual(field.frame.minY, collapsedY, accuracy: 2)
        }

        functions.tap()
        XCTAssertTrue(app.buttons["chat.call"].isHittable)
        let blankY = (app.navigationBars.firstMatch.frame.maxY + field.frame.minY) / 2
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.width - 2, dy: blankY)).tap()
        XCTAssertEqual(functions.value as? String, "收起")
        XCTAssertTrue(app.buttons["chat.call"].waitForNonExistence(timeout: 3))
        XCTAssertEqual(field.frame.minY, collapsedY, accuracy: 2)

        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        settings.tap()
        XCTAssertTrue(app.navigationBars["聊天设置"].waitForExistence(timeout: 3))
        app.buttons["完成"].tap()
        XCTAssertTrue(functions.waitForExistence(timeout: 3))
        functions.tap()
        settings.tap()
        XCTAssertTrue(app.navigationBars["聊天设置"].waitForExistence(timeout: 3))
        app.buttons["完成"].tap()
        XCTAssertEqual(field.frame.minY, collapsedY, accuracy: 2)
    }

    func testBubbleMenuPreservesKeyboardAndDraft() throws {
        continueAfterFailure = false
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
        let field = app.descendants(matching: .any)["chat.composer"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        field.typeText("Keep this draft")
        let latest = app.descendants(matching: .any)["chat.message.latest"].firstMatch
        XCTAssertTrue(latest.waitForExistence(timeout: 5))
        let dockSettled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            field.frame.minY < app.frame.maxY - 200
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [dockSettled], timeout: 5), .completed)
        let composerY = field.frame.minY
        latest.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)).press(forDuration: 1)
        XCTAssertTrue(app.buttons["复制"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.keyboards.firstMatch.exists, "长按菜单不能收起键盘")
        XCTAssertEqual(field.frame.minY, composerY, accuracy: 2, "菜单打开不能移动输入栏")
        XCTAssertEqual(field.value as? String, "Keep this draft")
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Bubble menu preserves keyboard and composer position"
        image.lifetime = .keepAlways
        add(image)
        app.buttons["复制"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertEqual(field.value as? String, "Keep this draft")
        field.typeText(" here")
        XCTAssertEqual(field.value as? String, "Keep this draft here")
    }

    func testClosingTranslatorTransfersFocusToComposer() throws {
        continueAfterFailure = false
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
        let field = app.descendants(matching: .any)["chat.composer"].firstMatch
        let toggle = app.buttons["chat.translator.toggle"]
        let source = app.descendants(matching: .any)["chat.translator.source"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Keep this draft")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let keyboardLayout = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            field.frame.maxY <= app.keyboards.firstMatch.frame.minY + 2
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardLayout], timeout: 3), .completed)
        let normalComposerY = field.frame.minY
        toggle.tap()
        XCTAssertTrue(source.waitForExistence(timeout: 3))
        source.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        toggle.tap()
        XCTAssertEqual(toggle.label, "打开翻译器")
        XCTAssertTrue(app.keyboards.firstMatch.exists, "收起翻译器必须把键盘交回普通输入框")
        XCTAssertFalse(app.buttons["chat.dismissKeyboard"].exists)
        XCTAssertEqual(field.value as? String, "Keep this draft")
        field.typeText(" here")
        XCTAssertEqual(field.value as? String, "Keep this draft here")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let restoredLayout = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(field.frame.minY - normalComposerY) <= 2
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [restoredLayout], timeout: 3), .completed)
        XCTAssertEqual(field.frame.minY, normalComposerY, accuracy: 2,
                       "切换动画和继续输入后，输入栏仍应位于键盘上方")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Translator closes into focused normal composer"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        // Closing while the English field owns focus also keeps the keyboard.
        toggle.tap()
        XCTAssertTrue(source.waitForExistence(timeout: 3))
        toggle.tap()
        XCTAssertEqual(toggle.label, "打开翻译器")
        XCTAssertFalse(app.buttons["chat.dismissKeyboard"].exists)
        dismissKeyboard(in: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))

        // A deliberately hidden keyboard stays hidden when switching modes.
        toggle.tap()
        XCTAssertTrue(source.waitForExistence(timeout: 3))
        toggle.tap()
        XCTAssertEqual(toggle.label, "打开翻译器")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertEqual(field.value as? String, "Keep this draft here")
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
        let beforeDismissal = XCTAttachment(screenshot: app.screenshot())
        beforeDismissal.name = "Chat before blank-area dismissal"
        beforeDismissal.lifetime = .keepAlways
        add(beforeDismissal)
        dismissKeyboard(in: app)
        XCTAssertEqual(field.value as? String, "what should we")
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Chat keyboard dismiss control"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        dismissKeyboard(in: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertEqual(field.value as? String, "what should we")
    }

    private func dismissKeyboard(in app: XCUIApplication) {
        let field = app.descendants(matching: .any)["chat.composer"].firstMatch
        let blankY = (app.navigationBars.firstMatch.frame.maxY + field.frame.minY) / 2
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.width - 3, dy: blankY)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3),
                      "Functions exist: \(app.buttons["chat.functions"].exists), send exists: \(app.buttons["chat.send"].exists), keyboard: \(app.keyboards.firstMatch.frame)")
    }
}
