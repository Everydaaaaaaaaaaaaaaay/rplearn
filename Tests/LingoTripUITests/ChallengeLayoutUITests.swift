import XCTest

@MainActor
final class ChallengeLayoutUITests: XCTestCase {
    func testQuestionControlsKeepExitAndPromptVisible() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for kind in ["choice", "arrange", "matching", "completion"] {
            app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
            app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
            app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
            app.launchEnvironment["UI_TEST_TAB"] = "unit-challenge"
            app.launchEnvironment["UI_TEST_LEARNING_QUESTION"] = kind
            app.launch()
            let exit = app.buttons["退出挑战"]
            XCTAssertTrue(exit.waitForExistence(timeout: 15), kind)
            XCTAssertGreaterThanOrEqual(exit.frame.minY, 0, kind)
            XCTAssertLessThan(exit.frame.maxY, 180, kind)
            XCTAssertTrue(exit.isHittable, kind)
            XCTAssertTrue(app.staticTexts["这是一道工程检查题，用于观察题干换行和操作区域，不计入学习记录。"].exists, kind)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "真实窗口题型布局-\(kind)"; attachment.lifetime = .keepAlways; add(attachment)
            app.terminate()
        }
    }
}
