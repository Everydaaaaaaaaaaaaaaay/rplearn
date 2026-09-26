import XCTest

/// 模拟器读取本工作树的正式素材：覆盖三角色实图、真录音播放结束与选图解锁，不提交成绩。
@MainActor
final class PrimaryChallengeMediaUITests: XCTestCase {
    func testPrimaryPicturesAndRecordedAudio() throws { try exercise(large: false) }
    func testPrimaryPicturesLargeTextDark() throws { try exercise(large: true) }

    private func exercise(large: Bool) throws {
        continueAfterFailure = false
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = repository.appending(path: "Backend/config/learning")
        for id in ["oliver.primary1.reading-bag", "ruby.primary1.picnic-fruit", "marcus.primary1.portrait-faces"] {
            let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appending(path: "units/\(id).json"))) as? [String: Any])
            let questions = try XCTUnwrap(raw["questions"] as? [[String: Any]])
            let question = try XCTUnwrap(questions.first)
            let publicQuestion = question.filter { ["id", "type", "goalId", "instruction", "prompt", "hint", "options"].contains($0.key) }
            var visible = publicQuestion
            let audio = try XCTUnwrap(question["audio"] as? [String: String])
            visible["audio"] = ["assetId": try XCTUnwrap(audio["assetId"])]
            var unit = raw.filter { ["id", "version", "schemaVersion", "roleKey", "level", "title", "summary", "scene", "estimatedMinutes", "goalIds"].contains($0.key) }
            unit["questions"] = [visible]; unit["beats"] = []
            let app = XCUIApplication()
            app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
                "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9", "UI_TEST_TAB": "unit-challenge",
                "UI_TEST_LEARNING_LOCAL_MEDIA": "1", "UI_TEST_LEARNING_MEDIA_DIRECTORY": directory.path,
                "UI_TEST_LEARNING_UNIT_JSON": String(decoding: try JSONSerialization.data(withJSONObject: unit), as: UTF8.self),
                "UI_TEST_LEARNING_QUESTION_ID": "q1"]
            if large {
                app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
                app.launchEnvironment["UI_TEST_CAPTURE_APPEARANCE"] = "dark"
            }
            app.launch()
            XCTAssertTrue(app.buttons["退出挑战"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.staticTexts["小学一年级"].exists)
            let check = app.buttons["检查"]
            XCTAssertFalse(check.isEnabled)
            let play = app.buttons["learning.audio.play"]
            reveal(play, in: app)
            XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "播放听力"), object: play)], timeout: 10) == .completed)
            play.tap()
            XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "再听一遍"), object: play)], timeout: 10) == .completed)
            for option in ["a", "b", "c"] {
                let button = app.buttons["learning.option.\(option)"]
                reveal(button, in: app)
                XCTAssertTrue(button.isEnabled)
                button.tap()
                XCTAssertTrue(button.isSelected)
                XCTAssertTrue(check.isEnabled)
            }
            XCTAssertFalse(app.buttons["重新载入"].exists)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = id + (large ? "-大字深色" : "-常规")
            attachment.lifetime = .keepAlways; add(attachment)
            app.terminate()
        }
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<24 {
            let top = app.buttons["退出挑战"].frame.maxY + 12
            let bottom = app.buttons["检查"].frame.minY - 16
            if element.isHittable, element.frame.midY >= top, element.frame.midY <= bottom { return }
            let down = element.exists && element.frame.midY < top
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: app.frame.midX, dy: top + (bottom - top) * (down ? 0.2 : 0.8)))
            let end = origin.withOffset(CGVector(dx: app.frame.midX, dy: top + (bottom - top) * (down ? 0.8 : 0.2)))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(element.isHittable, "应能滚动到完整控件：\(element.label)")
    }
}
