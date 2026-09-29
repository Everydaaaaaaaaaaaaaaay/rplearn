import XCTest

/// 模拟器读取本工作树的正式素材：覆盖三角色实图、真录音播放结束与选图解锁，不提交成绩。
@MainActor
final class PrimaryChallengeMediaUITests: XCTestCase {
    func testPrimaryPicturesAndRecordedAudio() throws { try exercise(large: false) }
    func testPrimaryPicturesLargeTextDark() throws { try exercise(large: true) }

    func testSecondGradeRecordedAudio() throws { try exercise(large: false, secondGrade: true) }
    func testSecondGradeLargeTextDark() throws { try exercise(large: true, secondGrade: true) }

    private func exercise(large: Bool, secondGrade: Bool = false) throws {
        continueAfterFailure = false
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = repository.appending(path: "Backend/config/learning")
        let ids = secondGrade ? ["oliver.primary2.playtime-can", "oliver.primary2.week-day-cards", "ruby.primary2.weather-window", "ruby.primary2.cafe-actions", "marcus.primary2.photo-time", "marcus.primary2.street-directions"] : ["oliver.primary1.bookmark-colours", "oliver.primary1.animal-book-covers", "ruby.primary1.shell-count", "ruby.primary1.painted-animal-flags", "marcus.primary1.photo-count", "marcus.primary1.studio-directions"]
        for id in ids {
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
            XCTAssertTrue(app.staticTexts[secondGrade ? "小学二年级" : "小学一年级"].exists)
            let check = app.buttons["检查"]
            XCTAssertFalse(check.isEnabled)
            let play = app.buttons["learning.audio.play"]
            reveal(play, in: app)
            XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "播放听力"), object: play)], timeout: 10) == .completed)
            if !large {
                let controls = app.otherElements["learning.audio.controls"]
                XCTAssertTrue(controls.exists)
                XCTAssertLessThanOrEqual(controls.frame.height, 64, "普通字号音频区应为紧凑单行")
                XCTAssertGreaterThanOrEqual(play.frame.height, 44, "保留足够的触控高度")
            }
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
