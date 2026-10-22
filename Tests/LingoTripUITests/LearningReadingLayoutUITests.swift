import XCTest

@MainActor
final class LearningReadingLayoutUITests: XCTestCase {
    func testMaterialTabsBookmarksAndCompactAnswers() throws {
        continueAfterFailure = false
        let first = (1...12).map { "A paragraph \($0). The reader can compare this detail with the current question without losing the place in the article." }.joined(separator: "\n\n")
        let material = "Read each article and answer its questions.\n\nA组（第1—2题）\n\n\(first)\n\nB组（第3—4题）\n\nB article describes a different place."
        let app = try launch(material: material, prompts: ["Which detail belongs to A?", "Why?", "Where?", "When?"])
        let reader = app.scrollViews["learning.material.reader"]
        XCTAssertTrue(reader.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Which detail belongs to A?"].isHittable)
        reader.swipeUp(); reader.swipeUp()
        let visible = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "A paragraph "))
            .allElementsBoundByIndex.first { reader.frame.contains($0.frame.midpoint) }
        let bookmark = try XCTUnwrap(visible?.label)
        app.buttons["learning.material.section.B"].tap()
        XCTAssertTrue(app.staticTexts["B article describes a different place."].exists)
        XCTAssertTrue(app.staticTexts["Which detail belongs to A?"].isHittable)
        app.buttons["learning.material.section.A"].tap()
        XCTAssertTrue(reader.frame.contains(app.staticTexts[bookmark].frame.midpoint))
        app.buttons["learning.material.expand"].tap()
        XCTAssertTrue(app.buttons["learning.material.done"].waitForExistence(timeout: 3))
        app.buttons["learning.material.done"].tap()
        app.buttons["learning.material.toggle"].tap()
        XCTAssertFalse(reader.exists)
        XCTAssertTrue(app.buttons["learning.option.o0"].isHittable)
        capture(app, "按篇阅读-材料收起后直接作答")
        app.terminate()

        let tools = ["A. StoryTrack offers short stories. You can read them and check new words.",
                     "B. SpeakPair gives you situations. You record your answer and try again.",
                     "C. ListenReplay contains dialogues. You can replay parts and check the script."]
        let toolApp = try launch(material: "Read all tools.\n\n" + tools.joined(separator: "\n\n"),
                                 prompts: ["Which tool helps Ada?", "Which tool helps Leo?"], options: tools)
        XCTAssertTrue(toolApp.buttons["learning.option.o0"].waitForExistence(timeout: 10))
        XCTAssertEqual(toolApp.buttons["learning.option.o0"].label, "A. StoryTrack")
        toolApp.buttons["learning.option.o0"].tap()
        XCTAssertTrue(toolApp.buttons["检查"].isEnabled)
        capture(toolApp, "旧快照-工具名选项")
        toolApp.terminate()

        let paragraphs = ["A. This is the first complete candidate paragraph. Its explanation remains available in the reading area.",
                          "B. This is the second complete candidate paragraph. No words are removed from the candidate itself.",
                          "C. This is the third complete candidate paragraph. The learner chooses its letter after comparing the context."]
        let paragraphApp = try launch(material: "The main article has a gap (1) ____ and more context.\n\n" + paragraphs.joined(separator: "\n\n"),
                                      prompts: ["Choose a paragraph for gap 1.", "Choose a paragraph for gap 2."],
                                      options: paragraphs, family: "paragraph_gap_insertion")
        XCTAssertTrue(paragraphApp.buttons["learning.material.section.candidate.o0"].waitForExistence(timeout: 10))
        paragraphApp.buttons["learning.material.section.candidate.o0"].tap()
        XCTAssertTrue(paragraphApp.staticTexts[String(paragraphs[0].dropFirst(3))].exists)
        XCTAssertEqual(paragraphApp.buttons["learning.option.o0"].label, "段落 A")
        capture(paragraphApp, "插段题-完整候选独立阅读")
        paragraphApp.terminate()
    }

    func testLargeTextUsesFullReaderWithoutSqueezingAnswers() throws {
        let app = try launch(material: String(repeating: "A complete paragraph for reading.\n\n", count: 20),
                             prompts: ["Which answer fits?"], largeText: true)
        XCTAssertTrue(app.buttons["learning.material.expand"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.scrollViews["learning.material.reader"].exists)
        app.buttons["learning.material.expand"].tap()
        XCTAssertTrue(app.buttons["learning.material.done"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["learning.material.done"].isHittable)
        capture(app, "辅助字号-展开阅读")
        app.buttons["learning.material.done"].tap()
        XCTAssertTrue(app.buttons["learning.material.expand"].isHittable)
        app.terminate()
    }

    private func launch(material: String, prompts: [String], options: [String] = ["A. One", "B. Two", "C. Three"],
                        family: String = "reading_choice", largeText: Bool = false) throws -> XCUIApplication {
        let questions = prompts.enumerated().map { index, prompt in
            ["id": "q\(index + 1)", "type": "choice", "goalId": "preview.reading", "instruction": "阅读并选择",
             "prompt": prompt, "hint": "回看材料", "material": material,
             "options": options.enumerated().map { ["id": "o\($0.offset)", "text": $0.element] }] as [String: Any]
        }
        let unit: [String: Any] = ["id": "preview.reading", "version": 1, "schemaVersion": 1, "roleKey": "companion", "level": "junior2",
            "title": "阅读排版工程检查", "summary": "界面检查", "scene": "只读预览", "estimatedMinutes": 2, "goalIds": ["preview.reading"],
            "beats": [], "originalGroup": ["id": "preview.reading", "family": family, "label": "阅读"], "questions": questions]
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_REQUIRE_AUTHENTICATION": "0",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1", "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9", "UI_TEST_TAB": "unit-challenge",
            "UI_TEST_LEARNING_QUESTION_ID": "q1", "UI_TEST_LEARNING_UNIT_JSON": String(decoding: try JSONSerialization.data(withJSONObject: unit), as: UTF8.self)]
        if largeText { app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        return app
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

private extension CGRect {
    var midpoint: CGPoint { CGPoint(x: midX, y: midY) }
}
