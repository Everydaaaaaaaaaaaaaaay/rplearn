import XCTest

@MainActor
final class LearningFormalPracticeUITests: XCTestCase {
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
        app.buttons["practice.start"].tap()
        XCTAssertTrue(app.staticTexts["七选五 · 整篇作答"].waitForExistence(timeout: 3))
        let submit = app.buttons["practice.next"]
        XCTAssertFalse(submit.isEnabled)
        app.buttons["practice.panel"].tap()
        for (index, answer) in ["A", "C", "F", "D", "B"].enumerated() {
            app.buttons["practice.question.\(index + 1)"].tap()
            let option = app.buttons["practice.option.\(answer)"]
            let answers = app.scrollViews["practice.answers"]
            for _ in 0..<8 {
                if option.isHittable && answers.frame.contains(CGPoint(x: option.frame.midX, y: option.frame.midY)) { break }
                answers.swipeUp()
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
