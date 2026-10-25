import XCTest

@MainActor
final class LearningFormalPracticeUITests: XCTestCase {
    func testIndependentGrammarPromptUsesLocalNumber() throws {
        continueAfterFailure = false
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "Fixtures/learning-senior3-independent-passage_form.json")
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_REQUIRE_AUTHENTICATION": "0",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1", "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9",
            "UI_TEST_TAB": "unit-challenge", "UI_TEST_LEARNING_STORY": "1", "UI_TEST_LEARNING_QUESTION": "completion",
            "UI_TEST_LEARNING_UNIT_JSON": try String(contentsOf: fixture, encoding: .utf8)]
        app.launch()
        XCTAssertTrue(app.buttons["practice.start"].waitForExistence(timeout: 20))
        app.buttons["practice.start"].tap()
        XCTAssertTrue(app.textFields["practice.grammar.answer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Complete gap 1."].exists)
        XCTAssertFalse(app.staticTexts["Complete gap 56."].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "独立语法填空-本篇题号一致"; attachment.lifetime = .keepAlways; add(attachment)
        app.terminate()
    }

    func testIndependentSeniorObjectivePracticeInputs() throws {
        continueAfterFailure = false
        for (family, title) in [("shared_insertion", "七选五"), ("passage_form", "语法填空"), ("sentence_choice", "选择题")] {
            let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appending(path: "Fixtures/learning-senior3-independent-\(family).json")
            let app = XCUIApplication()
            app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_REQUIRE_AUTHENTICATION": "0",
                "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1", "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9",
                "UI_TEST_TAB": "unit-challenge", "UI_TEST_LEARNING_STORY": "1",
                "UI_TEST_LEARNING_QUESTION": family == "passage_form" ? "completion" : "choice",
                "UI_TEST_LEARNING_UNIT_JSON": try String(contentsOf: fixture, encoding: .utf8)]
            app.launch()
            XCTAssertTrue(app.buttons["practice.start"].waitForExistence(timeout: 20))
            XCTAssertEqual(app.staticTexts["practice.task.kind"].label, title)
            app.buttons["practice.start"].tap()
            if family == "passage_form" {
                let input = app.textFields["practice.grammar.answer"]
                XCTAssertTrue(input.waitForExistence(timeout: 5))
                XCTAssertTrue(app.buttons["practice.question.10"].exists)
                XCTAssertFalse(app.buttons["practice.option.A"].exists)
            } else {
                let option = app.buttons[family == "sentence_choice" ? "learning.option.o0" : "practice.option.A"]
                XCTAssertTrue(option.waitForExistence(timeout: 5)); option.tap()
                XCTAssertTrue(option.isSelected)
                if family == "shared_insertion" {
                    XCTAssertTrue(app.buttons["practice.question.5"].exists)
                    XCTAssertFalse(app.buttons["practice.question.6"].exists)
                }
            }
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "高中独立专项-\(family)"; attachment.lifetime = .keepAlways; add(attachment)
            app.terminate()
        }
    }

    func testReportedExpansionReadingGroupHasBothPassagesAndSelectableAnswers() throws {
        continueAfterFailure = false
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "Fixtures/learning-senior3-archive-reading.json")
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_REQUIRE_AUTHENTICATION": "0",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1", "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9",
            "UI_TEST_TAB": "unit-challenge", "UI_TEST_LEARNING_STORY": "1",
            "UI_TEST_LEARNING_UNIT_JSON": try String(contentsOf: fixture, encoding: .utf8)]
        app.launch()
        XCTAssertTrue(app.buttons["practice.start"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts["practice.task.kind"].label, "阅读理解")
        app.buttons["practice.start"].tap()
        XCTAssertTrue(app.buttons["practice.option.A"].waitForExistence(timeout: 5))
        for index in 1...3 {
            let question = app.buttons["practice.question.\(index)"]
            XCTAssertTrue(question.exists); question.tap()
            let option = app.buttons["practice.option.A"]
            XCTAssertTrue(option.isHittable); option.tap(); XCTAssertTrue(option.isSelected)
        }
        XCTAssertTrue(app.buttons["practice.next"].isEnabled)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "截图报错题组-阅读材料与选项正常呈现"; attachment.lifetime = .keepAlways; add(attachment)
        app.terminate()
    }

    func testActualChallengeRoutesToWholePassageWithOneSharedBank() throws {
        continueAfterFailure = false
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "Fixtures/learning-senior1-formal-practice.json")
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_REQUIRE_AUTHENTICATION": "0",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1", "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9",
            "UI_TEST_TAB": "unit-challenge", "UI_TEST_LEARNING_STORY": "1",
            "UI_TEST_LEARNING_UNIT_JSON": try String(contentsOf: fixture, encoding: .utf8)]
        app.launch()
        XCTAssertTrue(app.buttons["practice.start"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["交互预览"].exists)
        XCTAssertFalse(app.staticTexts["本地示例 · 进度单独保存 · 不计入正式成绩"].exists)
        XCTAssertEqual(app.staticTexts["practice.task.kind"].label, "七选五 · 语法填空")
        let cover = XCTAttachment(screenshot: app.screenshot())
        cover.name = "正式练习开始页-七选五与语法填空"; cover.lifetime = .keepAlways; add(cover)
        app.buttons["practice.start"].tap()
        XCTAssertTrue(app.staticTexts["共用选项 A–G"].waitForExistence(timeout: 3))
        let submit = app.buttons["practice.next"]
        XCTAssertFalse(submit.isEnabled)
        for (index, answer) in ["A", "C", "F", "D", "B"].enumerated() {
            app.buttons["practice.question.\(index + 1)"].tap()
            let option = app.buttons["practice.option.\(answer)"]
            let answers = app.scrollViews["practice.answers"]
            for _ in 0..<20 {
                let center = CGPoint(x: option.frame.midX, y: option.frame.midY)
                if option.isHittable && answers.frame.contains(center) { break }
                let distance = min(answers.frame.height * 0.45, max(24, center.y < answers.frame.minY ? answers.frame.minY - center.y + 20 : center.y - answers.frame.maxY + 20))
                let start = answers.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: center.y < answers.frame.minY ? distance : -distance)),
                            withVelocity: .slow, thenHoldForDuration: 0.05)
            }
            option.tap()
            XCTAssertTrue(option.isSelected)
            if index < 4 { XCTAssertFalse(submit.isEnabled) }
            XCTAssertFalse(app.staticTexts["本次答对"].exists)
        }
        XCTAssertTrue(submit.isEnabled)
        XCTAssertFalse(app.buttons["检查"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "正式答题入口-整篇七选五共用选项"; attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["practice.back"].tap(); app.buttons["practice.start"].tap()
        XCTAssertTrue(submit.isEnabled)
        app.terminate()
    }
}
