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
        for (index, answer) in ["D", "C", "A", "D"].enumerated() {
            app.buttons["practice.question.\(index + 1)"].tap(); choose(answer, in: app)
        }
        app.buttons["practice.next"].tap(); app.buttons["practice.continue"].tap()
        XCTAssertTrue(app.staticTexts["practice.result.score"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["practice.result.score"].label, "7/7题")
        XCTAssertFalse(app.staticTexts["错题回顾"].exists)
        XCTAssertTrue(app.buttons["practice.finish"].exists)
        capture(app, "完成与回顾")
        app.terminate()
    }

    func testMinimalBookendsAndWrongAnswerReview() {
        continueAfterFailure = false
        let app = launch(dark: true)
        XCTAssertTrue(app.buttons["practice.start"].waitForExistence(timeout: 15))
        let avatar = app.descendants(matching: .any).matching(identifier: "practice.companion.avatar").firstMatch
        let message = app.staticTexts["practice.companion.message"]
        let kind = app.staticTexts["practice.task.kind"]
        let time = app.staticTexts["practice.task.time"]
        let start = app.buttons["practice.start"]
        XCTAssertGreaterThanOrEqual(avatar.frame.width, 100)
        XCTAssertEqual(avatar.frame.midX, app.frame.midX, accuracy: 2)
        XCTAssertGreaterThan(message.frame.minY, avatar.frame.maxY + 15)
        XCTAssertGreaterThan(kind.frame.minY, message.frame.maxY + 30)
        XCTAssertGreaterThan(start.frame.minY, time.frame.maxY + 30)
        XCTAssertEqual(start.label, "开始作答")
        XCTAssertEqual(start.frame.midX, app.frame.midX, accuracy: 2)
        XCTAssertFalse(app.staticTexts["PRACTICE / 练习"].exists)
        XCTAssertFalse(app.staticTexts["给自己一段\n专注的时间。"].exists)
        capture(app, "简洁开始页-头像台词题型时间")
        start.tap()
        for (index, answer) in ["A", "C", "B"].enumerated() {
            app.buttons["practice.question.\(index + 1)"].tap(); choose(answer, in: app)
        }
        app.buttons["practice.next"].tap(); app.buttons["practice.continue"].tap()
        for (index, answer) in ["D", "C", "A", "D"].enumerated() {
            app.buttons["practice.question.\(index + 1)"].tap(); choose(answer, in: app)
        }
        app.buttons["practice.next"].tap(); app.buttons["practice.continue"].tap()
        XCTAssertTrue(app.staticTexts["practice.result.score"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["practice.result.score"].label, "6/7题")
        XCTAssertTrue(app.staticTexts["错题回顾"].exists)
        XCTAssertFalse(app.staticTexts["错题与标记"].exists)
        XCTAssertFalse(app.staticTexts["这一题，再看一眼"].exists)
        capture(app, "简洁结束页-居中成绩与错题")
        let userAnswer = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "你的答案：A.")).firstMatch
        for _ in 0..<4 {
            if userAnswer.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(userAnswer.isHittable)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "参考答案：C.")).firstMatch.exists)
        capture(app, "错题回顾-用户答案与参考答案")
        let finish = app.buttons["practice.finish"]
        XCTAssertEqual(finish.label, "结束练习")
        XCTAssertEqual(finish.frame.midX, app.frame.midX, accuracy: 2)
        let review = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "practice.review.")).firstMatch
        review.tap()
        XCTAssertTrue(app.buttons["practice.continue"].waitForExistence(timeout: 3))
        app.buttons["practice.continue"].tap()
        XCTAssertTrue(finish.waitForExistence(timeout: 3))
        finish.tap()
        XCTAssertFalse(app.buttons["practice.finish"].exists)
        app.terminate()
    }

    func testClozeGapFormattingAndSentenceReview() {
        continueAfterFailure = false
        let app = launch()
        XCTAssertTrue(app.buttons["practice.task.cloze"].waitForExistence(timeout: 15))
        app.buttons["practice.task.cloze"].tap(); app.buttons["practice.start"].tap()
        XCTAssertTrue(app.buttons["practice.panel"].waitForExistence(timeout: 5))
        app.buttons["practice.panel"].tap()
        capture(app, "完形填空-连续横线与题号")
        app.buttons["practice.panel"].tap()
        for index in 0..<15 {
            app.buttons["practice.question.\(index + 1)"].tap(); choose("A", in: app)
        }
        app.buttons["practice.panel"].tap()
        capture(app, "已填答案-句点及两格间距")
        app.buttons["practice.panel"].tap()
        app.buttons["practice.next"].tap(); app.buttons["practice.continue"].tap()
        XCTAssertTrue(app.staticTexts["practice.result.points"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["practice.result.points"].label, "获得0积分！", "离线练习不能伪造真实奖励")
        capture(app, "结束页-实际积分")
        let sentence = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "practice.review.sentence.")).firstMatch
        for _ in 0..<4 { if sentence.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(sentence.isHittable)
        XCTAssertFalse(sentence.label.contains("Choose the best"))
        XCTAssertFalse(sentence.label.contains("____"))
        XCTAssertTrue(sentence.label.contains("."))
        capture(app, "完形错题回顾-原句及正确填词")
        app.terminate()
    }

    func testLegacyCoverUsesTheSameHierarchyAtLargestTextSize() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_REQUIRE_AUTHENTICATION": "0",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1", "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9",
            "UI_TEST_TAB": "unit-challenge", "UI_TEST_LEARNING_STORY": "1", "UI_TEST_CAPTURE_APPEARANCE": "dark"]
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let start = app.buttons["practice.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["practice.companion.message"].exists)
        XCTAssertTrue(app.staticTexts["practice.task.kind"].exists)
        XCTAssertFalse(app.staticTexts["工程界面预览"].exists)
        capture(app, "其他题型开始页-最大辅助字号")
        for _ in 0..<5 { if start.isHittable { break }; app.swipeUp() }
        start.tap()
        XCTAssertTrue(app.staticTexts["A book falls open. A blue bookmark is inside."].waitForExistence(timeout: 5))
        app.terminate()
    }

    func testSentenceSelectionAndGrammarKeyboard() {
        continueAfterFailure = false
        let app = launch()
        XCTAssertTrue(app.buttons["practice.task.insertion-grammar"].waitForExistence(timeout: 15))
        app.buttons["practice.task.insertion-grammar"].tap(); app.buttons["practice.start"].tap()
        XCTAssertTrue(app.buttons["practice.panel"].waitForExistence(timeout: 5))
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
        let committed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "brought"), object: input)
        XCTAssertEqual(XCTWaiter.wait(for: [committed], timeout: 3), .completed)
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
        for _ in 0..<20 {
            let center = CGPoint(x: choice.frame.midX, y: choice.frame.midY)
            if choice.isHittable && area.frame.contains(center) {
                choice.tap()
                if !choice.isSelected {
                    capture(app, "选项未响应")
                }
                XCTAssertTrue(choice.isSelected, "所选答案应保持选中：\(id)")
                return
            }
            let distance = min(area.frame.height * 0.45, max(24, center.y < area.frame.minY ? area.frame.minY - center.y + 20 : center.y - area.frame.maxY + 20))
            let start = area.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: center.y < area.frame.minY ? distance : -distance)),
                        withVelocity: .slow, thenHoldForDuration: 0.05)
        }
        XCTFail("选项 \(id) 不可点击")
    }
    private func launch(dark: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_REQUIRE_AUTHENTICATION": "0",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1", "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9",
            "UI_TEST_TAB": "practice-preview", "UI_TEST_PRACTICE_NAMESPACE": "practice.uitest.\(UUID().uuidString)"]
        if dark { app.launchEnvironment["UI_TEST_CAPTURE_APPEARANCE"] = "dark" }
        app.launch(); return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
