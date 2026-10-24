import XCTest

/// 本机已审候选的定向验收；缺少隔离素材时明确跳过，不把工程音频当正式内容。
@MainActor
final class PrimaryCandidateUITests: XCTestCase {
    private var directory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "build/learning-primary456-20261011/primary56-final/candidate-catalog")
    }

    private func unit(_ id: String) throws -> [String: Any] {
        let url = directory.appending(path: "\(id).public.json")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "需要本机已验证的小五/小六隔离候选目录")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func launch(_ unit: [String: Any], question: String? = nil, story: Bool = false, large: Bool = false) throws -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
            "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9", "UI_TEST_TAB": "unit-challenge",
            "UI_TEST_LEARNING_LOCAL_MEDIA": "1", "UI_TEST_LEARNING_MEDIA_DIRECTORY": directory.path,
            "UI_TEST_LEARNING_UNIT_JSON": String(decoding: try JSONSerialization.data(withJSONObject: unit), as: UTF8.self)]
        if let question { app.launchEnvironment["UI_TEST_LEARNING_QUESTION_ID"] = question }
        if story { app.launchEnvironment["UI_TEST_LEARNING_STORY"] = "1" }
        if large {
            app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            app.launchEnvironment["UI_TEST_CAPTURE_APPEARANCE"] = "dark"
        }
        app.launch()
        XCTAssertTrue(app.buttons[story ? "practice.start" : "退出挑战"].waitForExistence(timeout: 15))
        return app
    }

    func testFourCompleteOpeningsBeforeEighteenQuestions() throws {
        for id in ["primary5-a", "primary5-b", "primary6-a", "primary6-b"] {
            let snapshot = try unit(id)
            XCTAssertEqual((snapshot["questions"] as? [Any])?.count, 18)
            let beats = try XCTUnwrap(snapshot["beats"] as? [[String: Any]])
            XCTAssertEqual(beats.count, 3)
            let app = try launch(snapshot, story: true, large: id.hasSuffix("b"))
            XCTAssertTrue(app.buttons["practice.start"].waitForExistence(timeout: 5))
            app.buttons["practice.start"].tap()
            for (index, beat) in beats.enumerated() {
                XCTAssertEqual(beat["afterQuestion"] as? Int, 0)
                let text = try XCTUnwrap(beat["text"] as? String)
                let passage = app.staticTexts.matching(NSPredicate(format: "label == %@", text)).firstMatch
                XCTAssertTrue(passage.waitForExistence(timeout: 5))
                XCTAssertLessThan(passage.frame.minY, app.frame.midY, "新段落必须从头显示")
                XCTAssertFalse(app.buttons["检查"].exists)
                let next = app.buttons[index == 2 ? "开始答题" : "继续故事"]
                if index == 0 {
                    let translation = app.buttons["查看中文"]
                    reveal(translation, app: app, bottom: next)
                    translation.tap()
                    XCTAssertTrue(app.staticTexts[try XCTUnwrap(beat["translation"] as? String)].exists)
                }
                capture(app, name: "\(id)-开场\(index + 1)")
                next.tap()
            }
            XCTAssertTrue(app.buttons["检查"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testFourAuthoredClozeQuestionsAllowFillAndUndo() throws {
        for (id, questionID, large) in [("primary6-a", "p6.astra.a13", false), ("primary6-a", "p6.astra.a18", true),
                                         ("primary6-b", "p6.astra.b11", false), ("primary6-b", "p6.astra.b18", true)] {
            let snapshot = try unit(id)
            let questions = try XCTUnwrap(snapshot["questions"] as? [[String: Any]])
            let question = try XCTUnwrap(questions.first { $0["id"] as? String == questionID })
            XCTAssertNil(question["acceptedFills"])
            let tokens = try XCTUnwrap(question["tokens"] as? [[String: String]])
            let app = try launch(snapshot, question: questionID, large: large)
            let check = app.buttons["检查"]
            XCTAssertFalse(check.isEnabled)
            for token in tokens.prefix(2) {
                let button = app.buttons["learning.cloze.token.\(try XCTUnwrap(token["id"]))"]
                reveal(button, app: app, bottom: check); button.tap()
            }
            XCTAssertTrue(check.isEnabled)
            let first = app.buttons["learning.cloze.slot.s1"]
            reveal(first, app: app, bottom: check); first.tap()
            let undo = app.buttons["learning.cloze.undo"]
            reveal(undo, app: app, bottom: check); undo.tap()
            XCTAssertEqual(first.value as? String, "未填写")
            XCTAssertFalse(check.isEnabled)
            let replacement = app.buttons["learning.cloze.token.\(try XCTUnwrap(tokens[2]["id"]))"]
            reveal(replacement, app: app, bottom: check); replacement.tap()
            XCTAssertTrue(check.isEnabled)
            capture(app, name: "\(questionID)-真实词库撤回换词")
            app.terminate()
        }
    }

    func testAuthoredRecordingsPlayBeforeSubmission() throws {
        for (id, questionID) in [("primary5-b", "p5.astra.b16"), ("primary6-b", "p6.astra.b13")] {
            let snapshot = try unit(id)
            let questions = try XCTUnwrap(snapshot["questions"] as? [[String: Any]])
            let question = try XCTUnwrap(questions.first { $0["id"] as? String == questionID })
            XCTAssertNil((question["audio"] as? [String: Any])?["text"])
            let app = try launch(snapshot, question: questionID)
            let check = app.buttons["检查"], play = app.buttons["learning.audio.play"]
            reveal(play, app: app, bottom: check)
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "播放听力"), object: play)], timeout: 10), .completed)
            let option = app.buttons["learning.option.a"]
            reveal(option, app: app, bottom: check); option.tap()
            XCTAssertFalse(check.isEnabled)
            reveal(play, app: app, bottom: check); play.tap()
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "再听一遍"), object: play)], timeout: 30), .completed)
            XCTAssertTrue(check.isEnabled)
            XCTAssertLessThanOrEqual(app.otherElements["learning.audio.controls"].frame.height, 64)
            app.buttons["learning.audio.slow"].tap()
            XCTAssertTrue(app.buttons["停止播放"].waitForExistence(timeout: 5))
            play.tap()
            XCTAssertTrue(check.isEnabled)
            capture(app, name: "\(questionID)-真实音轨完整播放与慢速重播")
            app.terminate()
        }
    }

    private func reveal(_ element: XCUIElement, app: XCUIApplication, bottom: XCUIElement) {
        for _ in 0..<18 {
            let top = app.buttons["退出挑战"].frame.maxY + 10, limit = bottom.frame.minY - 10
            if element.isHittable && element.frame.midY > top && element.frame.midY < limit { return }
            let down = element.exists && element.frame.midY < top
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: app.frame.midX, dy: top + (limit - top) * (down ? 0.25 : 0.75)))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: app.frame.midX, dy: top + (limit - top) * (down ? 0.75 : 0.25))))
        }
        XCTAssertTrue(element.isHittable)
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
