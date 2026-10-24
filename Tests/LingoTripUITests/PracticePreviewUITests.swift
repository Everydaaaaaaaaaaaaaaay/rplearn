import XCTest

@MainActor
final class PracticePreviewUITests: XCTestCase {
    func testReadingResumeAndWholePassageFeedback() throws {
        continueAfterFailure = false
        let app = launch()
        XCTAssertTrue(app.buttons["practice.start"].waitForExistence(timeout: 15))
        capture(app, "任务卡")
        app.buttons["practice.start"].tap()
        let reader = app.scrollViews["practice.article"]
        XCTAssertTrue(reader.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(reader.frame.height, 250)
        capture(app, "正文与答题面板")
        reader.swipeUp()
        let article = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Arrive at 18:15")).firstMatch
        let before = article.frame.minY
        app.buttons["practice.question.2"].tap()
        XCTAssertEqual(article.frame.minY, before, accuracy: 3, "切题应保留文章位置")
        app.buttons["practice.back"].tap()
        XCTAssertTrue(app.buttons["practice.start"].waitForExistence(timeout: 3))
        app.buttons["practice.start"].tap()
        XCTAssertEqual(article.frame.minY, before, accuracy: 5, "继续练习应恢复文章位置")
        app.buttons["practice.panel"].tap() // larger answer area
        for (index, answer) in ["C", "C", "B"].enumerated() {
            app.buttons["practice.question.\(index + 1)"].tap()
            choose(answer, in: app)
            if index == 1 { choose(answer, in: app) } // repeating a choice keeps it selected
            XCTAssertFalse(app.staticTexts["本次答对"].exists)
        }
        app.buttons["practice.next"].tap()
        XCTAssertTrue(app.staticTexts["本次答对"].waitForExistence(timeout: 3))
        app.buttons["practice.evidence"].tap()
        XCTAssertTrue(article.isHittable)
        capture(app, "整篇集中讲解与原文依据")
        app.buttons["practice.continue"].tap()
        XCTAssertTrue(app.staticTexts["The book I had not asked for"].waitForExistence(timeout: 3))
        app.buttons["practice.panel"].tap()
        for (index, answer) in ["D", "C", "A", "D"].enumerated() {
            app.buttons["practice.question.\(index + 1)"].tap(); choose(answer, in: app)
        }
        app.buttons["practice.next"].tap(); app.buttons["practice.continue"].tap()
        XCTAssertTrue(app.staticTexts["本次回顾"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["本次答对"].exists)
        capture(app, "完成与回顾")
        app.terminate()
    }

    func testSentenceSelectionAndGrammarKeyboard() {
        continueAfterFailure = false
        let app = launch()
        XCTAssertTrue(app.buttons["practice.task.insertion-grammar"].waitForExistence(timeout: 15))
        app.buttons["practice.task.insertion-grammar"].tap(); app.buttons["practice.start"].tap()
        XCTAssertTrue(app.buttons["practice.panel"].waitForExistence(timeout: 5))
        app.buttons["practice.panel"].tap()
        choose("A", in: app)
        app.buttons["practice.question.2"].tap(); choose("A", in: app)
        app.buttons["practice.question.1"].tap()
        XCTAssertFalse(app.buttons["practice.option.A"].isSelected, "共享句子移动后旧空应清空")
        for (index, answer) in ["A", "C", "F", "D", "B"].enumerated() {
            app.buttons["practice.question.\(index + 1)"].tap(); choose(answer, in: app)
        }
        app.buttons["practice.panel"].tap() // collapse to read all filled sentences
        capture(app, "七选五答案回到全文")
        app.buttons["practice.panel"].tap()
        app.buttons["practice.next"].tap(); app.buttons["practice.continue"].tap()
        XCTAssertTrue(app.textFields["practice.grammar.answer"].waitForExistence(timeout: 3))
        let input = app.textFields["practice.grammar.answer"]
        input.tap(); input.typeText("brought")
        XCTAssertEqual(input.value as? String, "brought")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        capture(app, "语法填空与键盘")
        app.buttons["practice.back"].tap()
        app.buttons["practice.start"].tap()
        XCTAssertEqual(app.textFields["practice.grammar.answer"].value as? String, "brought")
        app.terminate()
    }

    private func choose(_ id: String, in app: XCUIApplication) {
        let choice = app.buttons["practice.option.\(id)"]
        let area = app.scrollViews["practice.answers"]
        for _ in 0..<7 {
            let center = CGPoint(x: choice.frame.midX, y: choice.frame.midY)
            if choice.isHittable && area.frame.contains(center) {
                choice.tap()
                if !choice.isSelected {
                    capture(app, "选项未响应")
                }
                XCTAssertTrue(choice.isSelected, "所选答案应保持选中：\(id)")
                return
            }
            if center.y < area.frame.minY { area.swipeDown() } else { area.swipeUp() }
        }
        XCTFail("选项 \(id) 不可点击")
    }
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_REQUIRE_AUTHENTICATION": "0",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1", "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9",
            "UI_TEST_TAB": "practice-preview", "UI_TEST_PRACTICE_NAMESPACE": "practice.uitest.\(UUID().uuidString)"]
        app.launch(); return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
