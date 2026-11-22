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
        XCTAssertLessThan(app.buttons["chat.settings"].frame.maxY, chatHeaderBottom(in: app) + 2)
        XCTAssertLessThan(app.buttons["chat.autoRead"].frame.maxY, chatHeaderBottom(in: app) + 2)
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

    func testLatestBubbleFollowsComposerBothWays() {
        checkLatestBubbleFollowsComposer()
    }

    func testShortConversationDismissesFromUpperBlankSpace() {
        checkLatestBubbleFollowsComposer(environment: ["UI_TEST_DICTIONARY_EXAMPLES": "1"], tapUpperBlankSpace: true)
    }

    func testOpeningKeyboardKeepsHistoryReadingPosition() {
        continueAfterFailure = false
        let app = launchKeyboardFixture(environment: ["UI_TEST_CHAT_SCROLL_HISTORY": "1"])
        defer { app.terminate() }
        let field = app.descendants(matching: .any)["chat.composer"].firstMatch
        let transcript = app.scrollViews["chat.messages"]
        XCTAssertTrue(field.waitForExistence(timeout: 30))
        XCTAssertTrue(app.descendants(matching: .any)["chat.message.latest"].firstMatch.waitForExistence(timeout: 10))
        transcript.swipeDown(velocity: .slow)
        let returnToBottom = app.buttons["回到底部"]
        XCTAssertTrue(returnToBottom.waitForExistence(timeout: 3))
        let readingBand = (transcript.frame.minY + 30)...(transcript.frame.minY + 180)
        let rows = transcript.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "chat.message.")).allElementsBoundByIndex
        guard let oldRowID = rows.first(where: { $0.exists && readingBand.contains($0.frame.midY) })?.identifier else {
            return XCTFail("找不到当前可见的历史气泡")
        }
        let oldRow = transcript.descendants(matching: .any)[oldRowID].firstMatch
        let oldFrame = oldRow.frame
        let collapsedY = field.frame.minY
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        waitForChatGeometry { field.frame.minY < collapsedY - 100 }
        XCTAssertTrue(returnToBottom.exists)
        XCTAssertEqual(oldRow.frame.midY, oldFrame.midY, accuracy: 2)
        dismissKeyboard(in: app)
        waitForChatGeometry { abs(field.frame.minY - collapsedY) <= 2 }
        XCTAssertEqual(oldRow.frame.midY, oldFrame.midY, accuracy: 2)
    }

    private func launchKeyboardFixture(environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_WELCOME_CAPTURE": "1",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1", "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9",
            "UI_TEST_NATIVE_CAPTURE": "chat"
        ].merging(environment) { _, override in override }
        app.launch()
        return app
    }

    private func checkLatestBubbleFollowsComposer(environment: [String: String] = [:], tapUpperBlankSpace: Bool = false) {
        continueAfterFailure = false
        let app = launchKeyboardFixture(environment: environment)
        defer { app.terminate() }
        let field = app.descendants(matching: .any)["chat.composer"].firstMatch
        let latest = app.descendants(matching: .any)["chat.message.latest"].firstMatch
        let transcript = app.scrollViews["chat.messages"]
        XCTAssertTrue(field.waitForExistence(timeout: 30))
        XCTAssertTrue(latest.waitForExistence(timeout: 10))
        let collapsedY = field.frame.minY
        let collapsedBottom = transcript.frame.maxY
        let collapsedBubble = latest.frame
        let collapsedWidth = transcript.frame.width
        let bottomGap = collapsedBottom - collapsedBubble.maxY
        XCTAssertTrue((0..<24).contains(bottomGap), "末条消息应贴近底部，实际间距 \(bottomGap)")

        for _ in 0..<2 {
            let composerCenter = field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            XCTAssertTrue(app.frame.contains(composerCenter.screenPoint), "输入框中心应在屏幕内：\(field.frame)")
            composerCenter.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            var expandedGeometry = ""
            waitForChatGeometry(diagnostics: { expandedGeometry }) {
                let composer = field.frame
                let viewport = transcript.frame
                let bubble = latest.frame
                expandedGeometry = "composer=\(composer), viewport=\(viewport), bubble=\(bubble), collapsedY=\(collapsedY), bottomGap=\(bottomGap)"
                return composer.minY < collapsedY - 100 && abs(viewport.maxY - bubble.maxY - bottomGap) <= 2
            }
            XCTAssertEqual(transcript.frame.width, collapsedWidth, accuracy: 1)
            XCTAssertEqual(latest.frame.minX, collapsedBubble.minX, accuracy: 1)
            XCTAssertEqual(latest.frame.width, collapsedBubble.width, accuracy: 1)
            if tapUpperBlankSpace {
                let headerBottom = chatHeaderBottom(in: app)
                let bubbleTop = latest.frame.minY
                XCTAssertGreaterThan(bubbleTop - headerBottom, 20, "短会话应在顶栏和气泡之间留出空白")
                app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: app.frame.width / 2, dy: (headerBottom + bubbleTop) / 2)).tap()
                XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
                XCTAssertFalse(app.navigationBars["聊天设置"].exists)
            } else {
                dismissKeyboard(in: app)
            }
            waitForChatGeometry { abs(field.frame.minY - collapsedY) <= 2 }
            XCTAssertTrue(latest.waitForExistence(timeout: 5), "键盘收起后末条消息应可见")
            let restoredViewport = transcript.frame
            let restoredBubble = latest.frame
            XCTAssertEqual(restoredViewport.maxY, collapsedBottom, accuracy: 2)
            XCTAssertEqual(restoredViewport.width, collapsedWidth, accuracy: 1)
            XCTAssertEqual(restoredBubble.minX, collapsedBubble.minX, accuracy: 1)
            XCTAssertEqual(restoredBubble.width, collapsedBubble.width, accuracy: 1)
            XCTAssertEqual(restoredViewport.maxY - restoredBubble.maxY, bottomGap, accuracy: 2,
                           "键盘收起后末条消息应回到原位：viewport=\(restoredViewport), bubble=\(restoredBubble)")
        }
    }

    private func waitForChatGeometry(
        file: StaticString = #filePath, line: UInt = #line,
        diagnostics: () -> String = { "" }, _ matches: @escaping () -> Bool
    ) {
        let layout = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in matches() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [layout], timeout: 3), .completed, diagnostics(), file: file, line: line)
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
        let blankY = (chatHeaderBottom(in: app) + field.frame.minY) / 2
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

    /// 聊天页顶栏画在页面里（不用系统导航栏），以它的下沿作为顶部边界。
    private func chatHeaderBottom(in app: XCUIApplication) -> CGFloat {
        app.descendants(matching: .any)["chat.header"].firstMatch.frame.maxY
    }

    private func dismissKeyboard(in app: XCUIApplication) {
        let field = app.descendants(matching: .any)["chat.composer"].firstMatch
        let blankY = (chatHeaderBottom(in: app) + field.frame.minY) / 2
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.width - 3, dy: blankY)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3),
                      "Functions exist: \(app.buttons["chat.functions"].exists), send exists: \(app.buttons["chat.send"].exists), keyboard: \(app.keyboards.firstMatch.frame)")
    }
}
