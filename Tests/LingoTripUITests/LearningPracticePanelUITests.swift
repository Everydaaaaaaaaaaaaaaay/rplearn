import XCTest

@MainActor
final class LearningPracticePanelUITests: XCTestCase {
    func testCompactFixedPanelAndCleanReadingInDarkMode() throws {
        continueAfterFailure = false
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "Fixtures/learning-senior2-clean-reading.json")
        let json = try String(contentsOf: fixture, encoding: .utf8)
        let unit = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let questions = try XCTUnwrap(unit["questions"] as? [[String: Any]])
        let questionID = try XCTUnwrap(questions[4]["id"] as? String)
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_REQUIRE_AUTHENTICATION": "0",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1", "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9",
            "UI_TEST_TAB": "unit-challenge", "UI_TEST_LEARNING_UNIT_JSON": json,
            "UI_TEST_LEARNING_QUESTION_ID": questionID, "UI_TEST_CAPTURE_APPEARANCE": "dark"]
        app.launch()
        XCTAssertTrue(app.buttons["practice.start"].waitForExistence(timeout: 20))
        app.buttons["practice.start"].tap()
        let toggle = app.buttons["practice.panel"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.label, "收起答题面板")
        XCTAssertFalse(app.staticTexts["B1"].exists)
        XCTAssertFalse(app.staticTexts["PASSAGE 02"].exists)
        XCTAssertFalse(app.staticTexts["第 2 题"].exists)
        XCTAssertFalse(app.staticTexts["本篇完成后集中讲解"].exists)
        let instruction = app.staticTexts["practice.instruction"]
        XCTAssertTrue(instruction.exists)
        XCTAssertGreaterThanOrEqual(instruction.frame.height, 20)
        let next = app.buttons["practice.next"]
        let option = app.buttons["practice.option.A"]
        XCTAssertLessThan(next.frame.width, option.frame.width)
        XCTAssertGreaterThan(next.frame.width, option.frame.width * 0.9)
        XCTAssertEqual(next.frame.midX, option.frame.midX, accuracy: 1)
        let expandedY = toggle.frame.minY
        let start = toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -100)))
        XCTAssertEqual(toggle.label, "收起答题面板")
        XCTAssertEqual(toggle.frame.minY, expandedY, accuracy: 1)
        capture(app, "精简答题页-固定高度与居中按钮")
        toggle.tap()
        XCTAssertEqual(toggle.label, "展开答题面板")
        XCTAssertFalse(app.scrollViews["practice.answers"].exists)
        let collapsed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            toggle.frame.minY > expandedY + 250
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [collapsed], timeout: 3), .completed)
        XCTAssertGreaterThan(toggle.frame.minY, expandedY + 250)
        capture(app, "答题面板收起-上箭头")
        toggle.tap()
        XCTAssertEqual(toggle.label, "收起答题面板")
        let expanded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(toggle.frame.minY - expandedY) < 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 3), .completed)
        XCTAssertEqual(toggle.frame.minY, expandedY, accuracy: 1)
        app.buttons["practice.back"].tap(); app.buttons["practice.start"].tap()
        XCTAssertEqual(toggle.frame.minY, expandedY, accuracy: 1)
        app.terminate()
    }
    func testClozeSharesTheSameTwoStatePanel() {
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_REQUIRE_AUTHENTICATION": "0",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1", "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9",
            "UI_TEST_TAB": "practice-preview", "UI_TEST_PRACTICE_NAMESPACE": "practice.layout.\(UUID().uuidString)"]
        app.launch()
        XCTAssertTrue(app.buttons["practice.task.cloze"].waitForExistence(timeout: 20))
        app.buttons["practice.task.cloze"].tap(); app.buttons["practice.start"].tap()
        let toggle = app.buttons["practice.panel"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.label, "收起答题面板")
        XCTAssertFalse(app.staticTexts["第 1 空"].exists)
        XCTAssertFalse(app.staticTexts["本篇完成后集中讲解"].exists)
        let expandedY = toggle.frame.minY
        toggle.tap()
        XCTAssertEqual(toggle.label, "展开答题面板")
        XCTAssertFalse(app.scrollViews["practice.answers"].exists)
        let collapsed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in toggle.frame.minY > expandedY + 250 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [collapsed], timeout: 3), .completed)
        toggle.tap()
        XCTAssertEqual(toggle.label, "收起答题面板")
        XCTAssertTrue(app.buttons["practice.next"].exists)
        app.terminate()
    }
    func testPracticeBookendsUseEnglishCompanionMessages() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_REQUIRE_AUTHENTICATION": "0",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1", "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9",
            "UI_TEST_TAB": "practice-preview", "UI_TEST_PRACTICE_NAMESPACE": "practice.bookends.\(UUID().uuidString)"]
        app.launch()
        addTeardownBlock { app.terminate() }
        let message = app.staticTexts["practice.companion.message"]
        XCTAssertTrue(message.waitForExistence(timeout: 15))
        assertEnglish(message.label)
        capture(app, "英文角色开场")
        app.buttons["practice.start"].tap()
        for count in [3, 4] {
            for index in 1...count {
                let question = app.buttons["practice.question.\(index)"]
                XCTAssertTrue(question.waitForExistence(timeout: 5)); question.tap()
                let option = app.buttons["practice.option.A"]
                XCTAssertTrue(option.waitForExistence(timeout: 5)); option.tap()
            }
            app.buttons["practice.next"].tap()
            let next = app.buttons["practice.continue"]
            XCTAssertTrue(next.waitForExistence(timeout: 5)); next.tap()
        }
        XCTAssertTrue(app.staticTexts["practice.result.score"].waitForExistence(timeout: 5))
        XCTAssertTrue(message.exists)
        assertEnglish(message.label)
        XCTAssertTrue(app.staticTexts["practice.result.points"].exists)
        capture(app, "英文角色收尾与本次积分")
    }

    private func assertEnglish(_ message: String) {
        XCTAssertNotNil(message.range(of: "[A-Za-z]", options: .regularExpression))
        XCTAssertFalse(message.unicodeScalars.contains { CharacterSet.letters.contains($0) && !$0.isASCII })
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
